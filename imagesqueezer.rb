#!/usr/bin/env ruby 

# == Synopsis 
#   Compresses all JPGs and PNGs with no transparency to JPGs with a certain quality value. 
#   Quality option and the directory are required arguments!
#
# == Examples
#   imagesqueezer.rb -Q 95 /home/myimages
#   This would recursively parse /home/myimages and apply itself to all non-transparent PNGs and JPGs. 
#   Both would be converted to JPGs with quality-value 95.
#
#   Other examples:
#   <Other examples go here>
#
# == Usage 
#   imagesqueezer.rb -Q <INTEGER> [options] directory
#
#   For help use: imagesqueezer.rb -h
#
# == Options
#   -Q, --quality       Sets the JPG image quality. Integer value from 0 (worst) to 100 (best).
#   -h, --help          Displays help message
#   -v, --version       Display the version, then exit
#   -q, --quiet         Output as little as possible, overrides verbose
#   -V, --verbose       Verbose output
#
# == Author
#   Javier Vazquez
#
# == Copyright
#   Copyright 2010 Ringier AG, Javier Vazquez
# == License
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.

require "rubygems"
require "bundler/setup"

require 'optparse' 
require 'rdoc/usage'
require 'ostruct'
require 'date'
require 'find'
require 'RMagick'
require 'nokogiri'

class App
  VERSION = '1.0'
  
  attr_reader :options

  def initialize(arguments, stdin)
    @arguments = arguments
    @stdin = stdin
    
    # Set defaults
    @options = OpenStruct.new
    @options.verbose = false
    @options.quiet = false
    @options.quality = 95
  end

  # Parse options, check arguments, then process the command
  def run
        
    if parsed_options? && arguments_valid? 
      start_time = Time.now
      puts "Start at #{Time.now}\n\n" if @options.verbose
      
      output_options if @options.verbose # [Optional]
            
      process_arguments            
      process_command
      
      puts "\nFinished at #{Time.now}" if @options.verbose
      puts "\nProcess took #{Time.now - start_time} seconds" if @options.verbose
      
    else
      output_usage
    end
      
  end
  
  protected
  
    def parsed_options?
      
      # Specify options
      opts = OptionParser.new 
      opts.on('-v', '--version')    { output_version ; exit 0 }
      opts.on('-h', '--help')       { output_help }
      opts.on('-V', '--verbose')    { @options.verbose = true }  
      opts.on('-q', '--quiet')      { @options.quiet = true }
      # FIXME passing the option using a block probably isn't the most elegant way to do it...
      opts.on('-Q', '--quality NUM', Integer, "JPG Quality") { |n| @options.quality = n }
            
      opts.parse!(@arguments) rescue return false
      
      process_options
      true      
    end

    # Performs post-parse processing on options
    def process_options
      @options.verbose = false if @options.quiet
      @jpg_quality = @options.quality
    end
    
    def output_options
      puts "Options:\n"
      
      @options.marshal_dump.each do |name, val|        
        puts "  #{name} = #{val}"
      end
      puts " "
    end

    # True if required arguments were provided
    def arguments_valid?
      # TODO arguments should be validated in a better way.
      # The path and the quality value are required arguments.
      true if @arguments.length == 2
    end
    
    # Setup the arguments
    def process_arguments
      @dir = @arguments.first
    end
    
    def output_help
      output_version
      RDoc::usage() #exits app
    end
    
    def output_usage
      RDoc::usage('usage') # gets usage from comments above
    end
    
    def output_version
      puts "#{File.basename(__FILE__)} version #{VERSION}"
    end
    
    def process_command    
      old_size = directory_size_in_mb(@dir) 
      smart_puts("INFO: Starting script...")
      existing_images = all_magazine_images("#{@dir}/images")
      compress_jpgs(existing_images[:jpg], @jpg_quality)
      old_png_count = existing_images[:png].count
      compress_pngs_without_alpha(@dir, "magazine.xml", @jpg_quality, old_png_count) 
      smart_puts("INFO: Size was #{old_size.round} MB and is now #{directory_size_in_mb(@dir).round} MB. We saved #{(old_size - directory_size_in_mb(@dir)).round} MB!")
      smart_puts("INFO: Script ended.")
    end

    def process_standard_input
      input = @stdin.read      
      # TO DO - process input
      
      # [Optional]
      # @stdin.each do |line| 
      #  # TO DO - process each line
      #end
    end
  
  end   
  
  def compress_jpgs(my_jpgs, jpg_quality)
    smart_puts("INFO: Found #{my_jpgs.count} existing JPGs on filesystem.")
    my_jpgs.each do |image|
      my_jpg = ::Magick::Image.read("#{@dir}/#{image}").first
      my_jpg.write("#{@dir}/#{image}") { self.quality = jpg_quality }
    end
  end
  
  # convert PNGs with no alpha value to JPGs, reduce JPG quality and change filename in XML file
  def compress_pngs_without_alpha(my_dir, xml_file, jpg_quality, total_pngs)
    png_counter = 0
    converted_png_counter = 0
    indexed_pngs = []

    # read magazine.xml from filesystem
    doc = ::Nokogiri::XML(File.open("#{my_dir}/#{xml_file}", "r")) 
    # fetch elements named 'url'
    doc.elements.xpath("//url").each do |node| 
      # fetch elements in magazine.xml matching /.*.png/
      if node.children.first.content =~ /.*\.(png|PNG)\z/
        png_counter += 1
        indexed_pngs << node.children.first 
      end
    end
    smart_puts("INFO: Found #{png_counter} PNGs indexed in the XML out of #{total_pngs} existing on filesystem.")
    indexed_pngs.each do |indexed_png|
      if File.exists?("#{my_dir}/#{indexed_png.content}")
        # read png from filesystem
        my_png = ::Magick::Image.read("#{my_dir}/#{indexed_png.content}").first
        # check if image has any transparency. 0 means there's no transparency value
        if my_png.resize(1,1).pixel_color(0,0).opacity == 0
          my_png.format = "JPG"
          old_png = indexed_png.content
          # change filename in magazine.xml
          indexed_png.content = indexed_png.content.sub(/(.png)\z/,'.jpg')
          # change filename on filesystem
          File.rename("#{my_dir}/#{old_png}", "#{my_dir}/#{indexed_png.content}")
          # write converted png as jpg to filesystem
          my_png.write("#{my_dir}/#{indexed_png.content}") { self.quality = jpg_quality }
          smart_puts("WARNING: We are at #{Dir.pwd} and PNG #{my_dir}/#{old_png} was NOT DELETED") if File.exists?("#{my_dir}/#{old_png}")
          smart_puts("WARNING: We are at #{Dir.pwd} and JPG #{my_dir}/#{indexed_png.content} was NOT CREATED") unless File.exists?("#{my_dir}/#{indexed_png.content}") 
          converted_png_counter += 1
        end
      end        
    end
    
    File.open("#{my_dir}/#{xml_file}", "w") {|f| doc.write_xml_to f}
    smart_puts("INFO: Converted #{converted_png_counter} PNGs with no alpha-value to JPGs.")
  end   
  
  # return array containing all PNG and JPG files in my_dir
  def all_magazine_images(my_dir)
    image_files = { :jpg => [], :png => []}
    Find.find(my_dir) do |path|
      if FileTest.directory?(path)
        if File.basename(path)[0] == ?.
          Find.prune       # Don't look any further into this directory.
        else
          next
        end
      else
        case
        # collect existing PNGs
        when path =~ /.*\.(png|PNG)\z/
          image_files[:png] << path.gsub("#{@dir}/", '')
        # collect existing JPGs
        when path =~ /.*\.(jpg|JPG|jpeg|JPEG)\z/
          image_files[:jpg] << path.gsub("#{@dir}/", '')
        end
      end
    end
    return image_files
  end
  
  # return directory size in MB
  def directory_size_in_mb(path)
    counter = 0
    Find.find(path) {|f| counter += File.size(f) }
    # Megabyte has 1048576.0 bytes
    return counter / 1048576.0
  end  

  # return my_string if quiet-option wasn't set
  def smart_puts(my_string)
    puts my_string unless @options.quiet
  end

# Create and run the application
app = App.new(ARGV, STDIN)
app.run