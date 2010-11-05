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
require 'nokogiri'


class App
  VERSION = '0.0.1'
  MEGABYTE = 1048576.0
  
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
      
      # Array mit real existierenden PNG- und JPG-Files
      # Per XPath alle PNG- und JPG-Files in magazine.xml durchlaufen
      # Bei jedem File checken ob in XML verlinkt. Falls nein: Löschen
      # Falls ja, PNG und alpha-channel:  pngcrush
      # Falls ja, PNG und kein alpha-channel: optimieren, in jpg umwandeln und referenz in xml anpassen
      
      old_size = directory_size_in_mb(@dir)
      png_counter = 0
      start_time = Time.now
      # find existing PNG files
      existing_pngs = all_magazine_pngs("#{@dir}/images")
      indexed_pngs = []
      
      file = File.open("#{@dir}/magazine.xml")
      doc = Nokogiri::XML(file) 
      # fetch elements named 'url'
      doc.elements.xpath("//url").each do |node| 
        # fetch elements matching /.*.png/
        if  /.*.png/.match(node.children.first.content)
          png_counter += 1
          indexed_pngs << node.children.first.content 
        end
      end  
        
      file.close
      unless @options.quiet
        puts "***********"
        puts "Processing took #{Time.now - start_time} seconds."
        puts "Found #{png_counter} PNGs indexed in the XML out of #{existing_pngs.count} existing ones."
        if existing_pngs.sort! == indexed_pngs.sort!
          puts "Existing PNGs match indexed PNGs."
        else
          puts "Existing PNGs DO NOT match indexed PNGs."
        end
        puts "We saved #{old_size - directory_size_in_mb(@dir)} MB!"
        puts "***********"
        puts "Dir is: #{@dir}"
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
    
    def all_magazine_pngs(my_dir)
      image_files = []
      Find.find(my_dir) do |path|
        if FileTest.directory?(path)
          if File.basename(path)[0] == ?.
            Find.prune       # Don't look any further into this directory.
          else
            next
          end
        else
          unless /.*\.(png|PNG)/.match(path) == nil
            image_files << path.gsub("#{@dir}/", '')
          end
        end
      end
      return image_files
    end
    
    def directory_size_in_mb(path)
      counter = 0
      Find.find(path) {|f| counter += File.size(f) }
      return counter / MEGABYTE
    end
end


# TO DO - Add your Modules, Classes, etc


# Create and run the application
app = App.new(ARGV, STDIN)
app.run