<?php

	define("NI_DEBUG"  , 0);
	define("NI_MESSAGE", 1);
	define("NI_WARNING", 2);
	define("NI_ERROR"  , 3);

    date_default_timezone_set('Europe/London');
	$log = new Log(NI_MESSAGE);

	//If we are logging to std out then open stdout
	if(isset($LOG_TO_STDERR) && $LOG_TO_STDERR) {		
		//as we don't want it to use memory
		$log->logToArray = false;
		$log->addLogFile("php://stderr", "w");
	}

	class Log {
		var $log;
		var $logLevel;
		var $logOutputList;
		var $logToArray = true;
		var $tmpLogCopyFD = NULL; //file descripter pointing at a tempoary file containing all the log lines used during the email process
		
		function Log($logLevel = NI_WARNING) {
			$this->logLevel          = $logLevel;
			$this->log               = array();
			$this->logOutputList = array();
		}

		function addLogFile($filename, $writeType="a") {
			$fd = fopen($filename, $writeType);
			if($fd === FALSE) {
				logError("Failed to open file: ".$filename."!");
				return false;
			}
			$this->logOutputList[] = $fd;
			return true;
		}
		
		
		/**
		 * This is a temp file that will store the log during the process.  Once the process dies this file will be deleted
		 */
		function enableTempFileLog() {
			$this->tmpLogCopyFD    = tmpfile();
			$this->logOutputList[] = $this->tmpLogCopyFD;
			logMessage("Temp logging enabled");
		}
		
		/**
		 * This function only works if the enableTempFileLog function has been called
		 * if not then this function will return NULL.  If it is then it will return a string 
		 * representing the log messages added to the log so far
		 */
		function getLogfileContents() {
			if($this->tmpLogCopyFD == NULL)
				return NULL;
				
			//we cannot close the tmp file as it will be deleted so we should seek to the begining of the file and read it in
			$fileSize = @ftell($this->tmpLogCopyFD);
			if($fileSize === FALSE) {
				logError("Failed to call ftell on temp log file, cannot get contents, log will not be returned");
				return NULL;
			}
			
			@fseek($this->tmpLogCopyFD, 0);
			
			//read the contents of the file
			$contents = @fread($this->tmpLogCopyFD, $fileSize);
			
			if($contents === FALSE) {				
				logError("Failed to read tmp log file!");
				return NULL;
			}
			return $contents;
		}

		function logMessage($message, $type) {
			global $LOG_TO_STDERR;

			if($type < $this->logLevel)
				return;


			switch($type) {
				case NI_DEBUG   : $typeStr = 'D'; break;
				case NI_WARNING : $typeStr = 'W'; break;
				case NI_ERROR   : $typeStr = 'E'; break;
				default         : $typeStr = 'I'; break;
			}
			
			$str = date("dMY--G:i:s ")."-$typeStr- (".getmypid().") $message\n";
			foreach($this->logOutputList as $logFP)
				fwrite($logFP, $str);

			if($this->logToArray)
				$this->log[] = new LogMessage("PHP: ".$message, $type);
		}


		function debug($message) {
			$this->logMessage($message, NI_DEBUG);
		}

		function message($message) {
			$this->logMessage($message, NI_MESSAGE);
		}

		function warning($message) {
			$this->logMessage($message, NI_WARNING);
		}

		function error($message) {
			$this->logMessage($message, NI_ERROR);
		}

		/**
		 * This is the connection object of type database_connection.php
		 */
		function sqlError($message, $connection) {
			$this->error($message.", SQL Error(".$connection->errCode."): ".$connection->errStr);
		}

		function echoLog() {
			for($i=0 ; $i != count($this->log) ; $i++) {
				echo $this->log[$i]->type . " " . $this->log[$i]->message;
			}
		}

		function jsonEncode() {
			$string = '{';
			$string .=  '"logLevel":"'.$this->logLevel.'"';
			$string .= ',"log":'.jsonEncodeObjectArray($this->log);
			return $string.'}';
		}

	}


	class LogMessage {
		var $message;
		var $type;

		function LogMessage($message, $type) {
			$this->message = $message;
			$this->type    = $type;
		}

		function jsonEncode() {
			$string = '{';
			$string .=  '"message":"'.jsonEscapeString($this->message).'"';
			$string .= ',"type":"'.$this->type.'"';
			return $string."}";
		}
	}

	//these are general functions that can be used to log to the default log (assumed to be the global var $log)
	function logDebug($message) {
		global $log;
		if(!isset($log)) return;

		$log->debug($message);
	}

	function logMessage($message) {
		global $log;
		if(!isset($log)) return;

		$log->message($message);
	}

	function logWarning($message) {
		global $log;
		if(!isset($log)) return;

		$log->warning($message);
	}

	function logError($message) {
		global $log;
		if(!isset($log)) return;

		$log->error($message);
	}
	
	/**
	 * Logs a backtrace
	 */
	function logBacktrace() {
		$backtrace = debug_backtrace();
		$count = count($backtrace);
		logError("--- Backtrace ---");
		for($i=0 ; $i < $count ; $i++) {
			$func = $backtrace[$i];			
			logError("#$i ".$func['file']."(".$func['line']."): ".$func['function']."(#".count($func['args']).")");
		}
	}

?>