################################################################################
# Copyright (c) 2011-2014, Tenable Network Security
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
################################################################################

require 'nasldoc/cli/comment'

module NaslDoc
	module CLI
		class Application
			attr_accessor :error_count

			# Initializes the Application class
			#
			# - Sets the default output directory to nasldoc_output/
			# - Sets the template directory to lib/templates
			# - Sets the assets directory to lib/assets
			#
			def initialize
				@file_list = Array.new
				@function_count = 0
				@error_count = 0
				@options = Hash.new

				@options[:output_directory] = "nasldoc_ouput/"

				@functions = Array.new
				@globals = Array.new
				@includes = Array.new

				@overview = nil

				@template_dir = Pathname.new(__FILE__).realpath.to_s.gsub('cli/application.rb', 'templates')
				@asset_dir = Pathname.new(__FILE__).realpath.to_s.gsub('cli/application.rb', 'assets')
				@current_file = "(unknown)"
			end

			# For ERB Support
			#
			# @return ERB Binding for access to instance variables in templates
			def get_binding
				binding
			end

			# Generates the base name for a path
			#
			# @return htmlized file name for .inc file
			def base path
				File.basename(path, '.inc')
			end

			# Generates the HTML base name for a path
			#
			# @return htmlized file name for .inc file
			def url path
				base(path).gsub('.', '_') + '.html'
			end

			# Compiles a template for each file
			def build_template name, path=nil
				path ||= name

				dest = url(path)
				puts "[**] Creating #{dest}"
				@erb = ERB.new File.new("#{@template_dir}/#{name}.erb").read, nil, "%"
				html = @erb.result(get_binding)

				File.open("#{@options[:output_directory]}/#{dest}", 'w+') do |f|
					f.puts html
				end
			end

			# Processes each .inc file and sets instance variables for each template
			def build_file_page path
				puts "[*] Processing file: #{path}"
				@current_file = File.basename(path)
				contents = File.open(path, "rb") { |f| f.read }

				# Parse the input file.
				begin
					tree = Nasl::Parser.new.parse(contents, path)
				rescue Nasl::ParseException, Nasl::TokenException
					puts "[!!!] File '#{path}' couldn't be parsed. It should be added to the blacklist."
					return nil
				end

				# Collect the functions.
				@functions = Hash.new()
				tree.all(:Function).map do |fn|
					@functions[fn.name.name] = {
						:code => fn.context(nil, false, false),
						:params => fn.params.map(&:name)
					}
					@function_count += 1
				end

				@funcs_prv = @functions.select { |n, p| n =~ /^_/ }
				@funcs_pub = @functions.reject { |n, p| @funcs_prv.key? n }

				# Collect the globals.
				@globals = tree.all(:Global).map(&:idents).flatten.map do |id|
					if id.is_a? Nasl::Assignment
						id.lval.name
					else
						id.name
					end
				end.sort

				@globs_prv = @globals.select { |n| n =~ /^_/ }
				@globs_pub = @globals.reject { |n| @globs_prv.include? n }

				# Collect the includes.
				@includes = tree.all(:Include).map(&:filename).map(&:text).sort

				# Parse the comments.
				@comments = tree.all(:Comment)
				puts "[**] #{@comments.size} comment(s) were found"
				@comments.map! do |comm|
					begin
						NaslDoc::CLI::Comment.new(comm, path)
					rescue CommentException => e
						# A short message is okay for format errors.
						puts "[!!!] #{e.class.name} #{e.message}"
						@error_count += 1
						nil
					rescue Exception => e
						# A detailed message is given for programming errors.
						puts "[!!!] #{e.class.name} #{e.message}"
						puts e.backtrace.map{ |l| l.prepend "[!!!!] " }.join("\n")
						nil
					end
				end
				@comments.compact!
				@comments.keep_if &:valid
				puts "[**] #{@comments.size} nasldoc comment(s) were parsed"

				# Find the overview comment.
				@overview = @comments.select{ |c| c.type == :file }.shift

				build_template "file", path
			end

			# Builds each page from the file_list
			def build_file_pages
				@file_list.each do |f|
					build_file_page(f)
				end
			end

			# Copies required assets to the final build directory
			def copy_assets
				puts `cp -vr #{@asset_dir}/* #{@options[:output_directory]}/`
			end

			# Prints documentation stats to stdout
			def print_documentation_stats
				puts "\n\nDocumentation Statistics"
				puts "Files: #{@file_list.size}"
				puts "Functions: #{@function_count}"
				puts "Errors: #{@error_count}"
			end

			# Removes blacklisted files from the file list
			def remove_blacklist file_list
				blacklist = [
					"apple_device_model_list.inc",
					"blacklist_dss.inc",
					"blacklist_rsa.inc",
					"blacklist_ssl_rsa1024.inc",
					"blacklist_ssl_rsa2048.inc",
					"custom_CA.inc",
					"daily_badip.inc",
					"daily_badip2.inc",
					"daily_badurl.inc",
					"known_CA.inc",
					"oui.inc",
					"oval-definitions-schematron.inc",
					"ovaldi32-rhel5.inc",
					"ovaldi32-win-dyn-v100.inc",
					"ovaldi32-win-dyn-v90.inc",
					"ovaldi32-win-static.inc",
					"ovaldi64-rhel5.inc",
					"ovaldi64-win-dyn-v100.inc",
					"ovaldi64-win-dyn-v90.inc",
					"ovaldi64-win-static.inc",
					"plugin_feed_info.inc",
					"sc_families.inc",
					"scap_schema.inc",
					"ssl_known_cert.inc"
				]

				new_file_list = file_list.dup

				file_list.each_with_index do |file, index|
					blacklist.each do |bf|
						if file =~ /#{bf}/
							new_file_list.delete(file)
						end
					end
				end

				return new_file_list
			end

			# Parses the command line arguments
			def parse_args
				opts = OptionParser.new do |opt|
					opt.banner = "#{APP_NAME} v#{VERSION}\nTenable Network Security.\njhammack@tenable.com\n\n"
					opt.banner << "Usage: #{APP_NAME} [options] [file|directory]"

					opt.separator ''
					opt.separator 'Options'

					opt.on('-o', '--output DIRECTORY', "Directory to output results to, created if it doesn't exit") do |option|
						@options[:output_directory] = option
					end

					opt.separator ''
					opt.separator 'Other Options'

					opt.on_tail('-v', '--version', "Shows application version information") do
						puts "#{APP_NAME} - #{VERSION}"
						exit
					end

					opt.on_tail('-?', '--help', 'Show this message') do
						puts opt.to_s + "\n"
						exit
					end
				end

				if ARGV.length != 0
					opts.parse!
				else
					puts opts.to_s + "\n"
					exit
				end
			end

			# Main function for running nasldoc
			def run
				parse_args

				if File.directory?(ARGV.first) == true
					pattern = File.join(ARGV.first, '**', '*.inc')
					@file_list = Dir.glob pattern
				else
					@file_list << ARGV.first
				end

				# Ensure the output directory exists.
				if File.directory?(@options[:output_directory]) == false
					Dir.mkdir @options[:output_directory]
				end

				# Get rid of non-NASL files.
				@file_list = remove_blacklist(@file_list)

				# Ensure we process files in a consistent order.
				@file_list.sort! do |a, b|
					base(a) <=> base(b)
				end

				puts "[*] Building documentation..."

				build_template "index"
				build_file_pages
				copy_assets

				print_documentation_stats
			end
		end
	end
end
