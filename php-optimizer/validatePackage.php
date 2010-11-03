<?php
	require_once(dirname(__FILE__).'/util/command_line_support.php');
	$old_exception_handler = set_exception_handler("customExceptionHandler");
	$old_error_handler     = set_error_handler("customErrorHandler");
	
	
	abstract class MagPath {
		public $path;
		public $basename;
		public $dirname;
		
		public function MagPath($path) {
			global $FILE_LOOKUP;
			$this->path = $path;
			$this->basename = basename($this->path);
			$this->dirname  = dirname($this->path);
			
			//Add this to the global lookup
			$FILE_LOOKUP[$this->path] = $this;
		}
		public function isDir() {
			return false;
		}
		
		public function isFile() {
			return false;
		}
		
		abstract public function getSize();
	}
	
	class MagFile extends MagPath {
		public $size;
		public $basename;
		public $dirname;
		public $isInUse = FALSE;//a flag to mark all files that are used as in use
		
		public function MagFile($path) {
			parent::__construct($path);
			$this->size = filesize($this->path);
		}
		
		public function isFile() {
			return true;
		}
		
		public function getSize() {
			return $this->size;
		}
	}
	
	class MagDir extends MagPath {
		
		public $fileList;
		public $dirList;
		
		public function MagDir($path) {
			parent::__construct($path);
			
			$this->fileList = array();
			$this->dirList  = array();
			
			$this->readDir();
		}
		
		public function isDir() {
			return true;
		}
		
		/**
		 * Returns a list of files where the filename matches the given regExp
		 */
		public function find($regExp) {
			$foundFiles = array();
			//look at the files
			foreach($this->fileList as $magFile) {
				if(preg_match($regExp, $magFile->path) == 1)
					$foundFiles[] = $magFile;
			}
			
			//look in the sub dirs
			foreach($this->dirList as $magDir) {
				$foundFiles = array_merge($foundFiles, $magDir->find($regExp));
			}
			
			return $foundFiles;
		}
		
		
		private function readDir() {
			$files = array();
		
			if(!($dh = opendir($this->path)))
				throw new Exception("Failed to open directory: ".$this->path);

			while(($tmpPath = readdir($dh)) !== FALSE) {
				if(substr($tmpPath, 0, 1) == ".") continue;
				
				$fullPath = $this->path.'/'.$tmpPath;
				
				if(is_dir($fullPath)) {
					$this->dirList[] = new MagDir($fullPath);
				} else if(is_file($fullPath)) {
					$this->fileList[] = new MagFile($fullPath);
				} else {
					logWarning("Cannot determine type of file: ".$fullPath);
				}
			}
			
			closedir($dh);
		}
		
		
		/**
		 * Returns the size in bytes of all the files containied in this subdir
		 * @return the total size of all the containted files
		 */
		public function getSize() {
			$total = 0;
			foreach($this->dirList as $dir) {
				$total += $dir->getSize();
			}
			
			foreach($this->fileList as $file) {
				$total += $file->getSize();
			}
			
			return $total;
		}
		
		/**
		 * This returns an array of MagFile objects that do not have the isInUse flag set to TRUE!
		 * @return an array of MagFile objects that are not marked as isInUse
		 */
		public function getFilesNotInUse() {
			
			$filesNotInUse = array();
			
			foreach($this->fileList as $file) {
				if($file->isInUse !== TRUE)
					$filesNotInUse[] = $file;
			}
			
			foreach($this->dirList as $dir) {
				//This is really crap and slow but its quick and dirty
				$filesNotInUse = array_merge($filesNotInUse, $dir->getFilesNotInUse());
			}
			
			return $filesNotInUse;
		}
	}
	
	/**
	 * Returns the size in bytes KB or MB
	 */
	function getSizeString($size) {
		//get the size in Kb or Mb
		if($size > 1048576) {
			return round(($size/1048576))."MB";
		} else if($size > 1024) {
			return round(($size/1024))."KB";
		} else
			return $size." bytes";
	}
	
	function usage() {
		global $argv;
		logError("USAGE: ".$argv[0]." --MAGAZINE_DIR=<iPad Mag dir>");
		endExit(1);
	}
	
	/**
	 * Runs the command throwing an exception with the specified error message and returns the results
	 * @param $cmd the command to run
	 * @param $error the error message on failure
	 * @return An array of lines returned by the command
	 */
	function runCommand($cmd, $error) {
		$output      = array();
		$returnValue = 0;
		logMessage("About to run command: '$cmd'");
		exec($cmd, $output, $returnValue);
		if($returnValue != 0) throw new Exception($error);
		return $output;
	}
	
	/**
	 * This function takes a full path to a file in the ipad package and returns the relative name that
	 * the package magazine.xml should use.
	 * NOTE: This assumes the MAGAZINE_PATH is set and that is has no slash at the end
	 */
	function getInternalPath($path) {
		global $MAGAZINE_DIR;
		return str_replace($MAGAZINE_DIR."/", "", $path);
	}
	
	//This is a global lookup containing all the files for quick access
	$FILE_LOOKUP = array();
	
	
	$MAGAZINE_DIR = NULL;
	
	//read the command line options
	for($i=1 ; $i < $argc ; $i++) {
		
		//Split on equals
		$parts = preg_split("/=/", $argv[$i]);
		
		$OPT = $parts[0];
		$OPTARG = count($parts) == 2 ? $parts[1] : NULL;
		
		switch($OPT) {
			case '--MAGAZINE_DIR'    : $MAGAZINE_DIR = $OPTARG; break;
			default : logWarning("Unknown option: ".$OPT);
		}
	}
	
	if($MAGAZINE_DIR === NULL)
		usage();
		
	//strip off any slashes at the end of the pathname
	$matches = array();
	if(preg_match("/^(.*\/[^\/]+)[\/]+$/", $MAGAZINE_DIR, $matches))
		$MAGAZINE_DIR = $matches[1];
	
	//check that the dir exists
	if(!is_dir($MAGAZINE_DIR))
		throw new Exception("Cannot read magazine directory: ".$MAGAZINE_DIR);

	//first generate a report for the total size and the size of each section
	
	//get a listing of all the files
	$magDir = new MagDir($MAGAZINE_DIR);
	
	
	//Read the XML File
	$magXMLFile = $MAGAZINE_DIR.'/magazine.xml';
	if(!is_file($magXMLFile))
		throw new Exception("Cannot read magazine.xml file from: ".$magXMLFile);
		
	$magXMLDoc = new DOMDocument();
	$magXMLDoc->load($magXMLFile);
	$xPath = new DOMXPath($magXMLDoc);
	
	//attach the dom to the associated story directories
	$items = $xPath->query("/issue/items/item");

	//display the file size statistics per story
	foreach($items as $item) {

		//get the id
		$ids = $xPath->query("id", $item);
		foreach($ids as $theId) {$id = $theId->nodeValue; break;} //Should only have one value	
		
		$titles = $xPath->query("title", $item);
		foreach($titles as $titleStr) {$title = $titleStr; break;}
		
		//now locate the story directory
		$storyPath = $MAGAZINE_DIR.'/images/story_'.$id;
		
		//lookup the path in the FILE_LOOKUP
		if(!array_key_exists($storyPath, $FILE_LOOKUP))
			throw new Exception("Cannot find story_".$id." in magazine package!");
		$storyDir = $FILE_LOOKUP[$storyPath];
			
		$sizeStr = getSizeString($storyDir->getSize());
			
		logMessage("Story ".$id.", using ".$sizeStr.", title '".$title->nodeValue."'");
	}
	
	
	logMessage("Total size: ".getSizeString($magDir->getSize())." bytes");
	
	//now grep the xml file to extract ALL the paths that start images/story_, and mark each of those files as in use
	$allXMLLines = file($magXMLFile);
	foreach($allXMLLines as $line) {
		$matches = array();
		if(preg_match_all("(images/story_[^\"'<]+)", $line, $matches) == 0)
			continue;
		
		foreach($matches as $match) {
			$matchedFilename = $MAGAZINE_DIR.'/'.$match[0];
			if(!array_key_exists($matchedFilename, $FILE_LOOKUP)) {
				logError("Cannot find ".$matchedFilename);
				continue;
			}
			
			$FILE_LOOKUP[$matchedFilename]->isInUse = TRUE;		
		}
	}
	
	//go and find all the files that are not in use
	$filesNotInUse = $magDir->getFilesNotInUse();
	
	logMessage("------ The following files are not referenced in the XML file... -------");
	foreach($filesNotInUse as $file) {
		logMessage($file->path);
	}
	
	logMessage("------ Analizing any png files ------");
	//get a list of all the png files
	$pngFiles = $magDir->find("/.png$/i");
	
	$count = 0;
	
	
	//aassoc array with [<OLDNAME>] = <NEWNAME>
	$originalPaths = array();
	$newPaths      = array();
	
	foreach($pngFiles as $pngFile) {
		logMessage("Checking ".$pngFile->path."....");
		$result = runCommand('convert '.$pngFile->path.' -resize 1x1 -alpha on -channel o -format "%[fx:u.a]" info:', "Failed to check png for alpha usage: ".$pngFile->path);
		if(count($result) == 0)
			throw new Exception("Failed to get result from convert for png file: ".$pngFile->path);
		
		if($result[0] != 1) {
			logMessage("PNG file contains some alpha transparency and will not be modified");
			continue;
		}
		$count++;
		logMessage("PNG file contains NO alpha transparency, converting to JPG file....");
			
		//convert from png to jpeg
		//work out the new name / path
		$matches = array();
		if(preg_match("/^(.*\/[^\/]+).png$/i", $pngFile->path, $matches) != 1) 
			throw new Exception("Failed to parse the filename: ".$pngFile->path);
		
		$newPath = $matches[1].".jpg";
		$originalPaths[] = getInternalPath($pngFile->path);
		$newPaths[]      = getInternalPath($newPath);
		
		$image = @imagecreatefrompng($pngFile->path);
		if(!$image)
			throw new Excepton("Failed to load PNG file: ".$pngFile->path);
			
		//TEST WATERMARK CODE
		/*$watermark = @imagecreatefrompng(dirname(__FILE__)."/TestWatermark.png");
		if(!$watermark)
			throw new Exception("Failed to load watermark file!");
		if(!imagecopymerge($image, $watermark, 0, 0, 0, 0, imagesx($watermark), imagesy($watermark), 100))
			throw new Exception("Failed to merge with watermark");*/
		//END TEST WATERMARK CODE	
			
		if(!imagejpeg($image, $newPath, 85))
			throw new Exception("Failed to write JPG file to ".$newPath);	
		
		//delete the old file
		if(!@unlink($pngFile->path)) 
			throw new Exception("Failed to delete file: ".$pngFile->path);
	}
	
	logMessage("---- The following files have been converted from PNG to JPG ----");
	foreach($newPaths as $path)
		logMessage($path);
	logMessage("------------");
	
	//update the XML so that the png's are changed to jpg's
	$count = 0;
	$allXMLLines = str_replace($originalPaths, $newPaths, $allXMLLines, $count);
	logMessage("Found $count lines to replace");
	
	
	if(!$fh = fopen($magXMLFile, 'w')) 
		throw new Exception("Failed to open magazine.xml file for write: ".$magXMLFile);
		
	$count = count($allXMLLines);
	for($i=0 ; $i < $count ; $i++) {
		fwrite($fh, $allXMLLines[$i]);
	}
	fclose($fh);
	
	//now get the new size
	$newMagDir = new MagDir($MAGAZINE_DIR);
	
	$totalSaving = $magDir->getSize() - $newMagDir->getSize();
	
	logMessage("Compression complete, total saving: ".getSizeString($totalSaving));
?>