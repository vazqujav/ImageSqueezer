#!/usr/bin/env ruby 

# == Synopsis 
#   Compresses all JPGs and PNGs with no transparency to smaller JPGs.
#
# == Examples
#   imagesqueezer.rb magazine/

#   This would recursively parse the directory 'magazine/' and apply itself to all non-transparent PNGs and JPGs.
#
# == Usage 
#   imagesqueezer.rb [options] directory
#
#   For help use: imagesqueezer.rb -h
#
# == Options
#   -h, --help          Displays help message
#   -v, --version       Display the version, then exit
#   -q, --quiet         Output as little as possible, overrides verbose
#   -V, --verbose       Verbose output
#
# == Author
#   Javier Vazquez
#
# == Copyright
#   Copyright 2011 Ringier AG, Javier Vazquez
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

require 'optparse' 
require 'rdoc/usage'
require 'ostruct'
require 'date'
require 'find'
require 'tempfile'

require 'RMagick'
require 'nokogiri'

class App
  VERSION = '1.1'
  # Quality of compressed JPG for former PNG
  PNG_COMPRESSION = 85
  # Quality of compressed JPG for former JPG
  JPG_COMPRESSION = 95
  
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
            
      opts.parse!(@arguments) rescue return false
      
      process_options
      true      
    end

    # Performs post-parse processing on options
    def process_options
      @options.verbose = false if @options.quiet
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
      true if @arguments.length == 1
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
      existing_images = all_magazine_images(@dir, "#{@dir}/images")
      compress_jpgs(@dir,existing_images[:jpg], JPG_COMPRESSION)
      old_png_count = existing_images[:png].count
      compress_pngs_without_alpha(@dir, "magazine.xml", PNG_COMPRESSION, old_png_count) 
      smart_puts("INFO: Size was around #{old_size.round} MB and is now around #{directory_size_in_mb(@dir).round} MB.")
      get_stats(old_size, directory_size_in_mb(@dir))
      smart_puts("INFO: Script ended.")
    end

    def process_standard_input
      input = @stdin.read      
    end
  
  end   
  
  def compress_jpgs(my_dir, my_jpgs, jpg_quality)
    smart_puts("INFO: Found #{my_jpgs.count} existing JPGs on filesystem.")
    compressed_jpgs = 0
    my_jpgs.each do |image|
      tmp_jpg = Tempfile.new('tempjpg')
      # read jpg file
      my_jpg = ::Magick::Image.read("#{my_dir}/#{image}").first
      # write jpg image to tempfile
      my_jpg.write(tmp_jpg.path) { self.quality = jpg_quality }
      # check if new jpg would be smaller than the old one
      if tmp_jpg.size < File.size("#{my_dir}/#{image}")
        my_jpg.write("#{my_dir}/#{image}") { self.quality = jpg_quality }
        compressed_jpgs += 1
      end
      tmp_jpg.close!
    end
    smart_puts("INFO: Compressed #{compressed_jpgs} JPGs.")
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
      if node.children.first.content =~ /\w*.(png|PNG)/
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
          # FIXME Possibly missing an image reference in the XML in case of Webelements/Hotspots?
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
  def all_magazine_images(my_dir, image_dir)
    image_files = { :jpg => [], :png => []}
    Find.find(image_dir) do |path|
      if FileTest.directory?(path)
        if File.basename(path)[0] == ?.
          Find.prune       # Don't look any further into this directory.
        else
          if File.basename(path) =~ /^story_.*/ || path == image_dir
            next
          else
            Find.prune
          end
        end
      else
        case
        # collect existing PNGs
        when path =~ /.*\.(png|PNG)\z/
          image_files[:png] << path.gsub("#{my_dir}/", '')
        when path =~ /.*\.(jpg|JPG|jpeg|JPEG)\z/
          image_files[:jpg] << path.gsub("#{my_dir}/", '')
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
  
  # Analyze and output result of script operation
  def get_stats(before, after)
    case 
    when before.round < after.round
      smart_puts("WARNING: Something went wrong, we gained weight!")
    when before.round > after.round
      percent = (((before - after) / before) * 100).round
      smart_puts("INFO: Magazine is now #{percent}% smaller!")
    when before.round == after.round
      smart_puts("INFO: No noteworthy compression has been achieved.")
    end
  end

# Create and run the application
app = App.new(ARGV, STDIN)
app.run