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
      puts "\nProcess took #{start_time - Time.now} seconds" if @options.verbose
      
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
    if File.writable?("#{my_dir}/#{xml_file}")
      doc = ::Nokogiri::XML(File.open("#{my_dir}/#{xml_file}", "r")) 
      # fetch elements named 'url'
      doc.elements.xpath("//url").each do |node| 
        # fetch elements matching /.*.png/
        if node.children.first.content =~ /.*\.(png|PNG)\z/
          png_counter += 1
          indexed_pngs << node.children.first.content 
          output = `convert #{my_dir}/#{node.children.first.content} #{if @options.quiet; "-quiet"; end} -resize 1x1 -alpha on -channel o -format "%[fx:u.a]" info:`
          result = $?.success?
          # check convert exit-status
          if result
            output_array = []
            # output string into array
            output.each("\n") {|s| output_array << s.strip }
            # check if the "magic" value returned from convert-command. If it's < 1 the image contains alpha transparency and is not converted.
            unless output_array[0].to_i != 1
              my_png = ::Magick::ImageList.new("#{my_dir}#{node.children.first.content}")
              my_png.first.format = "JPG"
              old_png = node.children.first.content
              node.children.first.content = node.children.first.content.sub(/(.png)\z/,'.jpg')
              my_png.write("#{my_dir}#{node.children.first.content}") { self.quality = jpg_quality }
              File.delete("#{my_dir}#{old_png}")
              converted_png_counter += 1
            end
          else
            # something went wrong with convert-command. 
            smart_puts("ERROR - #{my_dir}/#{node.children.first.content}: Failed to check png for alpha usage")
          end
        end
      end
    else
      smart_puts("ERROR: XML file not writable!")
    end
    File.open("#{my_dir}/#{xml_file}", "w") {|f| doc.write_xml_to f}
    smart_puts("INFO: Found #{png_counter} PNGs indexed in the XML out of #{total_pngs} existing ones.")
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

  def smart_puts(my_string)
    puts my_string unless @options.quiet
  end

# Create and run the application
app = App.new(ARGV, STDIN)
app.run