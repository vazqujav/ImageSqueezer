<?php

require_once(dirname(__FILE__).'/util/command_line_support.php');
require_once(dirname(__FILE__).'/config/config.inc.php');

function runCommand($cmd, $error) {
	$output      = array();
	$returnValue = 0;
	logMessage("About to run command: '$cmd'");
	exec($cmd, $output, $returnValue);
	foreach($output as $line) logMessage("CMD: ".$line);
	if($returnValue != 0) throw new Exception($error);
}

function optimiseMagazinePackage($baseURL) {
	logMessage("About to run optimisation on the magazine package...");
	runCommand(OPTIMISE_IMAGE_CMD." --MAGAZINE_DIR=".$baseURL, "Failed to run optimisation command!");
}

optimiseMagazinePackage(BASE_MAGAZINE_CONTENT_PATH);

?>
