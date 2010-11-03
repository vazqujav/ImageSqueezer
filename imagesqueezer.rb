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



require 'optparse' 
require 'rdoc/usage'
require 'ostruct'
require 'date'
require 'find'
require 'RMagick'


class App
  VERSION = '0.0.1'
  
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
      
      puts "Start at #{DateTime.now}\n\n" if @options.verbose
      
      output_options if @options.verbose # [Optional]
            
      process_arguments            
      process_command
      
      puts "\nFinished at #{DateTime.now}" if @options.verbose
      
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
      old_size = 0
      new_size = 0
      png_counter = 0
      start_time = Time.now

      Find.find(@dir) do |path|
        if FileTest.directory?(path)
          if File.basename(path)[0] == ?.
            Find.prune       # Don't look any further into this directory.
          else
            next
          end
        else
          unless /.*\.(png|PNG)/.match(path) == nil
            image = Magick::Image.read(path).first
            if image.format.to_s == "PNG"
              png_counter += 1
              old_size += FileTest.size(path)
              image.resize(1,1)
              image.alpha = "on"
              image.info.channel(OpacityChannel)

              # image.format = "JPG"
              image.write(path)
              # TODO Filename muss noch von PNG auf JPG umgeschrieben werden
              new_size += FileTest.size(path)

              
            end
          end
        end
      end
      unless @options.quiet
        puts "***********"
        puts "Processing took #{Time.now - start_time} seconds."
        puts "Found and compressed #{png_counter} PNGs."
        puts "We saved #{old_size - new_size} bytes!"
        puts "***********"
      end
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


# TO DO - Add your Modules, Classes, etc


# Create and run the application
app = App.new(ARGV, STDIN)
app.run