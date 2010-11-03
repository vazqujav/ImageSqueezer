<?php
	$LOG_TO_STDERR = true;
	require_once(dirname(__FILE__).'/Log.php');
	
	//This is a just in case number that will prevent more than 1 email being sent.
	//The reason for this is the exception and error handlers will genrally be calling the send mail
	//and this could be bad if in doing the send an exception occurs that calls sendmail again
	//and then we have 1000's of emails.
	$MAIL_SENT_COUNT        = 0;
	
	//Use the following global to set any data that should be included in any error/exception email
	$PROCESS_DESCRIPTION = array();
	
	// redefine the user error constants
	define("FATAL", E_USER_ERROR);
	define("ERROR", E_USER_WARNING);
	define("WARNING", E_USER_NOTICE);
	
	function customExceptionHandler($exception) {
		global $SEND_ERROR_EMAILS, $SCRIPT_NAME;
		logError("An error ({$exception->getCode()}) occurred at line ({$exception->getLine()}) of file ({$exception->getFile()}). Exiting.");
		logError($exception->getMessage());
		logError($exception->getTraceAsString());
		
		if($SEND_ERROR_EMAILS === true)
			sendExceptionMail($exception, !empty($SCRIPT_NAME) ? $SCRIPT_NAME : __FILE__);
			
		endExit(1);
	}
	
	// My error handler
	function customErrorHandler($errno, $errstr, $errfile, $errline) {
		global $SEND_ERROR_EMAILS, $SCRIPT_NAME;
		
		//ignore errors if switched off
		if(error_reporting() == 0)
			return;
		
		switch ($errno) {
		  case ERROR:
		  case FATAL:
			logError("A error ($errno) occured at line ($errline) of file ($errfile), exiting");
			logError($errstr);
			logBacktrace();
			if($SEND_ERROR_EMAILS === true)
				sendErrorMail($errno, $errstr, $errfile, $errline, !empty($SCRIPT_NAME) ? $SCRIPT_NAME : __FILE__);
			endExit(1);
			break;
	
		  case WARNING:
			logWarning("A warning ($errno) occured at line ($errline) of file ($errfile), continuing");
			logWarning($errstr);
			logBacktrace();
			if($SEND_ERROR_EMAILS === true)
				sendErrorMail($errno, $errstr, $errfile, $errline, !empty($SCRIPT_NAME) ? $SCRIPT_NAME : __FILE__);
			endExit(1);	
			break;
	
		  default:
			logError("An unknown type of error ($errno) occured at line ($errline) of file ($errfile), exiting");
			logError($errstr);
			logBacktrace();
			if($SEND_ERROR_EMAILS === true)
				sendErrorMail($errno, $errstr, $errfile, $errline, !empty($SCRIPT_NAME) ? $SCRIPT_NAME : __FILE__);
			endExit(1);
			break;
		}		   
	}
	
	/**
	 * endExit() -
	 *
	 * Exits gracefully with the supplied exit code.
	 */
	function endExit($rv) {
		//if a local end exit is defined call that first (and it will probebly exit anyway
		if(function_exists('localEndExit'))
			localEndExit($rv);
			
		global $argv, $database;
		
		if(isset($database))
			$database->disconnect();
	
		logMessage("Exiting $argv[0] with exit status ($rv)");
	
		exit($rv);
	}
	
	/**
	 * Loads the json data or throws an exception if it cannot be loaded
	 */
	function loadJSONFile($filename) {
		if (empty($filename)) 
			throw new Exception("<controlFile> not specified");		
			
		if (!file_exists($filename))
			throw new Exception("Specified <controlFile> ($filename) un-readable");
		
		$jsonData = getDataFromJSONFile($filename);
		
		if ($jsonData === false)
			throw new Exception("Failed to load json metadata from file ($filename)");
			
		return $jsonData;			
	}
	
	
	function sendErrorMail($errno, $errstr, $errfile, $errline, $scriptName, $additionalText=array()) {
		$errorType = '';
		switch ($errno) {
			case ERROR:   $errorType = "Error";   break;
			case FATAL:   $errorType = "Fatal Error";   break;		
			case WARNING: $errorType = "Warning"; break;		
			default:      $errorType = "Unknown"; break;
		}		
		
		$message = array();
		$message[] = '<table class="error" cellspacing="0" cellpadding="3">';
			$message[] = '<tr><th colspan="2" class="errorHeader" style="text-align:left;">Error Report</th></tr>';			
			$message[] = '<tr><th>Message</th><td style="font-weight: bold;">'.replaceEOLWithBR($errstr).'</td></tr>';
			$message[] = '<tr><th>Details</th><td class="errorDesc">'.$errorType.' ('.$errno.') error occured at line ('.$errline.') of file ('.$errfile.'). Exiting.</td></tr>';			
		$message[] = '</table>';
		
		//append additional 
		if(count($additionalText) > 0) {
			$message[] = '<pre>';
				$message[] = implode("\n", $additionalText);
			$message[] = '</pre>';
		}			   
				   
		sendMailToSupport(implode("\n", $message), $scriptName);
	}
	
	function sendExceptionMail($exception, $scriptName, $additionalText=array()) {
		
		$message = array();
		$message[] = '<table class="error" cellspacing="0" cellpadding="3">';
			$message[] = '<tr><th colspan="2" class="errorHeader" style="text-align: left;">Exception Report</th></tr>';			
			$message[] = '<tr><th>Message</th><td style="font-weight: bold;">'.replaceEOLWithBR($exception->getMessage()).'</td></tr>';
			$message[] = '<tr><th>Details</th><td>An Exception ('.$exception->getCode().') occurred at line ('.$exception->getLine().') of file ('.$exception->getFile().'). Exiting.</td></tr>';		
			$message[] = '<tr><th>Stacktrace</th><td>'.replaceEOLWithBR($exception->getTraceAsString()).'</td></tr>';	
		$message[] = '</table>';	
		
		//append additional 
		if(count($additionalText) > 0) {
			$message[] = '<pre>';
				$message[] = implode("\n", $additionalText);
			$message[] = '</pre>';
		}
		
		sendMailToSupport(implode("\n", $message), $scriptName);	
	}
	
	/**
	 * Replaces all EOL chars with <br />
	 */
	function replaceEOLWithBR($str) {
		$str = str_replace("\n", "<br />", $str);
		$str = str_replace("\r", "", $str);
		
		return $str;
	}
	
	function sendMailToSupport($errorMessage, $scriptName) {
		global $MAIL_SENT_COUNT, $PROCESS_DESCRIPTION, $argv, $log;
		
		//see notice above (basically prevents the error handler sending more than one error message)
		if($MAIL_SENT_COUNT >= 1) {
			logMessage("Not sending mail as one has already been sent!");
			return;
		}
			
		$MAIL_SENT_COUNT++;
		
		$to = ERROR_EMAIL_LIST; //if is empty string or null then do not send error emails
		if(empty($to))
			return;
		
		//set the script name to the $argv value	
		if(count($argv[0]) > 0) {
			$scriptName = $argv[0];
		}
			
		$hostname = determineHost();	
		$subject = "ERROR: Karma CS2 ".basename($scriptName)." ($hostname)";	
		
		$random_hash = md5(date('r', time()));		
		$headers  = "From: $hostname\r\n";		
		$headers .= "Content-Type: multipart/mixed; boundary=\"".$random_hash."\""; //add boundary string and mime type specification
		
		//we have two parts to this email 
		//1. The html content
		//2. An optional text file attachment
		$message   = array();
		$message[] = '--'.$random_hash; 
		$message[] = 'Content-Type: text/html; charset="iso-8859-1"';
		$message[] = 'Content-Transfer-Encoding: 7bit';
		$message[] = '';
		//add the process description if set
		//if($PROCESS_DESCRIPTION !== NULL) 
		//	$message .= $PROCESS_DESCRIPTION."\n\n";
		
		$message[]  = '<html>';
			$message[] = '<head>';
				$message[] = '<style type="text/css"><!--';
					$message[] = 'body {font-family: Arial, Helvetica, sans-serif;}';
										
					$message[] = 'table.detailsTable    {border: 2px solid #AAAAAA; background-color: EEFFEE;}';
					$message[] = 'table.detailsTable td {border: 1px solid #AAAAAA;}';
					$message[] = 'table.detailsTable th {border: 1px solid #AAAAAA; text-align: right;}';
					$message[] = 'th.detailsHeader      {font-weight: bold; font-size: 1.2em; text-align: left;}';
																					
					$message[] = 'table.error {background-color: #FFAAAA; border: 2px solid red;}';
					$message[] = 'table.error td {border: 1px solid red;}';
					$message[] = 'table.error th {border: 1px solid red; text-align: right;}';
					$message[] = 'th.errorHeader {font-weight: bold; font-size: 1.2em; text-align: left;}';
					
				$message[] = '--></style>';
			$message[] = '</head>';
			
			$message[] = '<body>';
				//default message
				$message[] = '<table class="detailsTable" cellspacing="0" cellpadding="3">';
					$message[] = '<tr><th class="detailsHeader" style="text-align: left;" colspan="2">Process Details</th></tr>';					
					$message[] = '<tr><th>Host</td><td>'.$hostname.'</td></tr>';
					$message[] = '<tr><th>Script Name</td><td>'.basename($scriptName).'</td></tr>';
					$message[] = '<tr><th>Script Path</td><td>'.dirname($scriptName).'</td></tr>';
					
					if($argv !== NULL && count($argv) > 0) 						
						$message[] = '<tr><th>Command Options</th><td>'.implode(' ', array_slice($argv, 1)).'</td></tr>';				
					$message[] = '<tr><th>PID</td><td>'.        getmypid().'</td></tr>';
					
					
					//add any additional items added by the process
					$count = count($PROCESS_DESCRIPTION);
					for($i=0 ; $i < $count ; $i++)
						$message[] = '<tr><th>'.$PROCESS_DESCRIPTION[$i]->name.'</th><td>'.$PROCESS_DESCRIPTION[$i]->description.'</td>';
					
					
				$message[] = '</table>';
				$message[] = '<br />';
				$message[] = $errorMessage;
				
			$message[] = '</body>';		
		
		//if the logger object is defined and temp log file is enabled get the contents and attach to the email
		$logContents = NULL;
		if($log != NULL)
			$logContents = $log->getLogfileContents();
		
		if($logContents !== NULL) {
			$message[] = '--'.$random_hash;	
			$message[] = 'Content-Type: text/plain; name=log.txt';
			$message[] = 'Content-Transfer-Encoding: base64';
			$message[] = 'Content-Disposition: attachment';
			$message[] = '';
			$message[] = chunk_split(base64_encode($logContents));	
						
		}		
		$message[] = '--'.$random_hash.'--';


		logMessage("Sending email to: $to");
		   
		mail($to, $subject, implode("\n", $message), $headers);   		
	}
	
	/**
	 * Used to add lines to the process description table created in the email
	 */
	class ProcessDescription {
		public $name;
		public $description;
		
		public function __construct($name, $description) {
			$this->name        = $name;
			$this->description = $description;
		}
	}
		
	/**
	 * Given an exception object this function will determine what exit code should be returned from this script.
	 * The reason this is important is if we have a database timeout or deadlock then the script that called this
	 * script may wish to retry the processes on db deadlock or timeout since that is all we would do manually
	 */
	function getExceptionExitCode($exception) {

		switch($exception->getCode()) {
			case 1213 : //SQL LOCK DEADLOCK
				return 110;
			case 1205 : //SQL LOCK WAIT TIMEOUT
				return 111;				
			case 2002 : //CR_CONNECTION_ERROR - I.E cannot connect to mysql socket
				return 113;
			case STALE_DATA_EXCEPTION_CODE : //Object has been updated by another process
				return 112; //general failure				
			default:
				return 1;			
		}
	}
	
	//echo the params
	if(isset($argv)) 
		logMessage("---- Starting ".$argv[0]." with options: ".implode(' ', array_slice($argv, 1))." ----");
?>