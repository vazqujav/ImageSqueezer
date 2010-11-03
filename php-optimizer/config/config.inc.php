<?php
 	//Base Build Dirs
 	define('BASE_BUILD_PATH', dirname(__FILE__).'/../build');
 	define('BASE_PROJECT', 'DigiMag_Base');
 	define('BASE_PROJECT_PATH', BASE_BUILD_PATH.'/'.BASE_PROJECT);
 	define('BASE_MAGAZINE_CONTENT_PATH', BASE_PROJECT_PATH.'/magazine');
	define('OPTIMISE_IMAGE_CMD', 'php '.dirname(__FILE__).'/../validatePackage.php');
