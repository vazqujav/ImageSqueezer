#!/usr/bin/env ruby 

# == Synopsis 
#   This app looks for PNGs with no transparency and converts them into smaller JPGs
#
# == Examples
#   imagesqueezer /home/myimages
#   This would recursively parse /home/myimages and apply itself to all non-transparent PNGs
#
#   Other examples:
#   <Other examples go here>
#
# == Usage 
#   imagesqueezer [options] directory
#
#   For help use: imagesqueezer -h
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
#   Copyright (c) 2010 Ringier AG, Javier Vazquez
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
  VERSION = '0.0.1'
  # SET QUALITY OF OUTPUT JPGs. 85 has been tested and seems to be OK
  JPEG_QUALITY = 85
  
  attr_reader :options

  def initialize(arguments, stdin)
    @arguments = arguments
    @stdin = stdin
    
    # Set defaults
    @options = OpenStruct.new
    @options.verbose = false
    @options.quiet = false
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
      # TO DO - implement your real logic here
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
      existing_images = all_magazine_images("#{@dir}/images")
      old_png_count = existing_images[:png].count
      compress_pngs_without_alpha(@dir, "magazine.xml", JPEG_QUALITY, old_png_count) 
      # TODO implement some lossless brute-force image compression, e.g. pngcrush or jpgoptim 
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
    
    indexed_pngs.each do |indexed_png|
      if File.exists?("#{my_dir}#{indexed_png.content}")
        # read png from filesystem
        my_png = ::Magick::Image.read("#{my_dir}#{indexed_png.content}").first
        # check if image has any transparency. 0 means there's no transparency value
        if my_png.resize(1,1).pixel_color(0,0).opacity == 0
          my_png.format = "JPG"
          old_png = indexed_png.content
          # change filename in magazine.xml
          indexed_png.content = indexed_png.content.sub(/(.png)\z/,'.jpg')
          # change filename on filesystem
          File.rename("#{my_dir}#{old_png}", "#{my_dir}#{indexed_png.content}")
          # write converted png as jpg to filesystem
          my_png.write("#{my_dir}#{indexed_png.content}") { self.quality = jpg_quality }
          smart_puts("WARNING: We are at #{Dir.pwd} and PNG #{my_dir}#{old_png} was NOT DELETED") if File.exists?("#{my_dir}#{old_png}")
          smart_puts("WARNING: We are at #{Dir.pwd} and JPG #{my_dir}#{indexed_png.content} was NOT CREATED") unless File.exists?("#{my_dir}#{indexed_png.content}") 
          converted_png_counter += 1
        end
      end        
    end
    
    File.open("#{my_dir}/#{xml_file}", "w") {|f| doc.write_xml_to f}
    smart_puts("INFO: Found #{png_counter} PNGs indexed in the XML out of #{total_pngs} existing on filesystem.")
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