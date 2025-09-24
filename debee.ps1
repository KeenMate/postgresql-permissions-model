#!/usr/bin/env pwsh

param (
	# Parameter help description
	[string]$Environment,
	[Parameter(Mandatory = $true)]
	[ValidateSet("restoreDatabase", "recreateDatabase", "updateDatabase", "preUpdateScripts", "postUpdateScripts", "fullService")]
	[string[]]$Operations = @("fullService"),
	[int]$UpdateStartNumber = -1,
	[int]$UpdateEndNumber = -1
)

function Prompt-User {
	param(
		[string]$Prompt,
		[object]$Default
	)

	if (-not [string]::IsNullOrEmpty($Default)) {
		if ($Default -is [bool]) {
			$Prompt += " [$( if ($Default)
      {
        'True'
      }
      else
      {
        'False'
      } )]"
		}
		else {
			$Prompt += " [$Default]"
		}
	}

	$input = Read-Host -Prompt $Prompt

	if ( [string]::IsNullOrEmpty($input)) {
		$input = $Default
	}
	else {
		if ($Default -is [bool]) {
			$input = [bool]::Parse($input)
		}
		elseif ($Default -is [int]) {
			$input = [int]::Parse($input)
		}
		elseif ($Default -is [string]) {
			# No conversion needed for string
		}
		else {
			throw "Unsupported default value type: $( $Default.GetType().FullName )"
		}

		if ($input.GetType() -ne $Default.GetType()) {
			throw "Entered value type doesn't match default value type"
		}
	}

	return $input
}

function Set-EnvVar {
	param(
		[string]$key,
		[object]$value
	)

	[System.Environment]::SetEnvironmentVariable($key, $value, [System.EnvironmentVariableTarget]::Process)
	# Write-Host "Env var: $key, set to: $value"
}

function Prepare-Environment {
	param (
  # Parameter help description
		[Parameter(Mandatory)]
		[string]$envFilePath
	)

	# Check if the file exists
	if (Test-Path $envFilePath) {
		# Read the file line by line
		$lines = Get-Content $envFilePath

		foreach ($line in $lines) {
			# Skip empty lines and lines that are comments
			if (-not [string]::IsNullOrWhiteSpace($line) -and -not $line.Trim().StartsWith("#")) {
				# Split the line into key and value
				$pair = $line -split '='
				if ($pair.Length -eq 2) {
					$key = $pair[0].Trim()
					$value = $pair[1].Trim()

					# Set the environment variable
					Set-EnvVar -key $key -value $value
				}
				else {
					Write-Warning "Skipping invalid line: $line"
				}
			}
		}

		Write-Host "Environment variables set successfully from $envFilePath"
	}
	else {
		Write-Host "File not found: $envFilePath"
	}
}

function Set-CurrentDatabase {
	param (
		[Parameter(Mandatory)]
		[string]$databaseName
	)

	Set-EnvVar -key "PGDATABASE" -value $databaseName
}

function Get-FilesByNumericPrefix {
	param (
		[Parameter(Mandatory = $true)]
		[int]$StartNumber,
		[Parameter(Mandatory = $true)]
		[int]$EndNumber
	)

	if ($StartNumber -eq -1 -and [int]$Env:DBUPDATESTARTNUMBER -gt 0) {
		$StartNumber = [int]$Env:DBUPDATESTARTNUMBER
	}

	if ($EndNumber -eq -1 -and [int]$Env:DBUPDATEENDNUMBER -ge 1) {
		$EndNumber = [int]$Env:DBUPDATEENDNUMBER
	}
	Write-Warning "Scripts from: $StartNumber to: $EndNumber be run."
	# Ensure StartNumber is less than or equal to EndNumber
	if ($StartNumber -gt $EndNumber -and $EndNumber -ne -1) {
		Write-Error "StartNumber ($StartNumber) cannot be greater than EndNumber ($EndNumber)."
		return
	}
	# All files with xxx_ pattern
	$files = Get-ChildItem -Path "." -File -Filter "???_*"

	# Initialize an empty array to store matching files
	$matchingFiles = @()

	# Iterate through each file
	foreach ($file in $files) {
		# Extract the numeric prefix and convert it to an integer
		$prefix = [int]($file.Name -replace '^(\d{3})_.*$', '$1')

		if (($prefix -ge $StartNumber -or $StartNumber -eq -1) -and ($prefix -le $EndNumber -or $EndNumber -eq -1)) {
			Write-Host "File: $( $file.Name ) is within the update range."
			# Add the matching file to the $matchingFiles array
			$matchingFiles += $file
		}
	}

	Write-Host "Number of matching files: $( $matchingFiles.Count )"

	return $matchingFiles
}

function Recreate-Database {
	Set-CurrentDatabase -databaseName $Env:DBCONNECTDB

	Write-Host "Recreating database on host: "$Env:PGHOST", connected to: "$Env:PGDATABASE
	& $Env:DBPSQLFILE -f $Env:DBRECREATESCRIPT
}

function Restore-Database {
	param (
  # Parameter help description
		[string]$backupFilepath,
		[string]$backupType
	)

	Write-Host "Calculating backup type and path"

	if ( [string]::IsNullOrEmpty($backupFilepath)) {
		$backupFilepath = $Env:DBBACKUPFILE
	}

	if ( [string]::IsNullOrEmpty($backupFilepath)) {
		Write-Warning "No restore file defined, skipping"
		return
	}

	if ( [string]::IsNullOrEmpty($backupType)) {
		$backupType = $Env:DBBACKUPTYPE
	}

	$jobCount = 1

	if ([int]$Env:DBRESTOREJOBCOUNT -gt 0) {
		$jobCount = [int]$Env:DBRESTOREJOBCOUNT
	}

	Write-Warning "Restoring database with $jobCount jobs"

	switch ($backupType) {
		"file" {
			Write-Host "Restoring from file: "$backupFilepath

			Set-CurrentDatabase -databaseName $Env:DBDESTDB

			& $Env:DBPSQLFILE -f "$backupFilepath"
		}
		"dir" {
			Write-Host "Restoring from directory: "$backupFilepath

			Set-CurrentDatabase -databaseName $Env:DBDESTDB

			if ($Env:DBCREATEONRESTORE -eq $true) {
				& $Env:DBPGRESTOREFILE -v -F d -C -d $Env:DBCONNECTDB "$backupFilepath"
			}
			else {
				& $Env:DBPGRESTOREFILE -v -F d -d $Env:DBDESTDB "$backupFilepath"
			}
		}
		"custom" {
			Write-Host "Restoring from custom archive: "$backupFilepath

			Set-CurrentDatabase -databaseName $Env:DBDESTDB

			if ($Env:DBCREATEONRESTORE -eq $true) {
				& $Env:DBPGRESTOREFILE -v -F c -C -d $Env:DBCONNECTDB "$backupFilepath"
			}
			else {
				& $Env:DBPGRESTOREFILE -v -F c -d $Env:DBDESTDB "$backupFilepath"
			}
		}
		Default {
			Write-Host "Unknown backup type: "$backupType

		}
	}
}

function Update-Database {
	$files = Get-FilesByNumericPrefix -StartNumber $UpdateStartNumber -EndNumber $UpdateEndNumber

	Write-Host "Number of returned files: $( $files.Count )"

	Update-DatabaseWithFiles -Files $files
}

function Run-PreUpdateScripts {
	$scriptsToRun = @()

	if (($Env:DBPREUPDATESCRIPTS).Length -eq 0) {
		Write-Host "No preupdate scripts, skipping the step"
		return
	}

	# Split the paths using semicolon as delimiter
	$scripts = $Env:DBPREUPDATESCRIPTS -split ';'

	# Iterate through each script path
	foreach ($script in $scripts) {
		# Trim any leading or trailing whitespace characters
		$scriptPath = $script.Trim()

		# Check if the file exists
		if (Test-Path -Path $scriptPath -PathType Leaf) {
			$scriptsToRun += $scriptPath
			Write-Host "Pre update script file: $( $scriptPath ) to be run."
		}
		else {
			Write-Warning "File does not exist: $scriptPath"
		}
	}

	Update-DatabaseWithFiles -Filepaths $scriptsToRun
}

function Run-PostUpdateScripts {
	$scriptsToRun = @()

	if (($Env:DBPOSTUPDATESCRIPTS).Length -eq 0) {
		Write-Host "No postupdate scripts, skipping the step"
		return
	}

	# Split the paths using semicolon as delimiter
	$scripts = $Env:DBPOSTUPDATESCRIPTS -split ';'

	# Iterate through each script path
	foreach ($script in $scripts) {
		# Trim any leading or trailing whitespace characters
		$scriptPath = $script.Trim()

		if ([string]::IsNullOrEmpty($scriptPath)) {
			Write-Warning "Post update script path empty, skipping"
			continue
		}

		# Check if the file exists
		if (Test-Path -Path $scriptPath -PathType Leaf) {
			$scriptsToRun += $scriptPath
			Write-Host "Post update script file: $( $scriptPath ) to be run."
		}
		else {
			Write-Warning "File does not exist: $scriptPath"
		}
	}

	Update-DatabaseWithFiles -Filepaths $scriptsToRun
}

function Update-DatabaseWithFiles {
	param (
		[System.IO.FileInfo[]]$Files,
		[string[]]$Filepaths
	)

	Write-Host "Updating database .."
	Set-CurrentDatabase -databaseName $Env:DBDESTDB

	Write-Host "Number of update files: $( $Files.Count )"

	$Files | Sort-Object -Property FullName |
	Where-Object { $_.Length -gt 0 -and $_.Name.Length -gt 0 } |
	ForEach-Object {
		Write-Host ".. with file: $( $_.Name )"

		# -v ON_ERROR_STOP=1
		& $Env:DBPSQLFILE -q -b -n --csv -f "$_"
	}

	$Filepaths |
	Where-Object { $_.Length -gt 0 } |
	ForEach-Object {
		Write-Host ".. with file: $( $_ )"

		# -v ON_ERROR_STOP=1
		& $Env:DBPSQLFILE -q -b -n --csv -f "$_"
	}
}



# Define the path to the environment file
if (-not [string]::IsNullOrWhiteSpace($Environment)) {
	$envFilePath = "debee." + $Environment + ".env"
	$localEnvFilePath = ".debee." + $Environment + ".env"
}
else {
	$envFilePath = "debee.env"
	$localEnvFilePath = ".debee.env"
}

if (-not (Test-Path $envFilePath)) {
	Write-Warning "Could not find $envFilePath"
	exit
}

# Read common env file
Prepare-Environment -envFilePath $envFilePath

# Read local env file if defined, applicable only for local environment
if (-not [string]::IsNullOrWhiteSpace($localEnvFilePath)) {
	Prepare-Environment -envFilePath $localEnvFilePath
}

# Split the operation parameter for multiple operations in one go
# Iterate through each script path
foreach ($o in $Operations) {
	Write-Host "processing: "$o
	switch ($o) {
  "recreateDatabase" {
			Write-Host "Performing recreate operation..."
			Recreate-Database
  }
  "restoreDatabase" {
			Write-Host "Performing restore operation..."
			Restore-Database
  }
  "updateDatabase" {
			Write-Host "Performing update operation..."
			Update-Database
  }
  "preUpdateScripts" {
			Write-Host "Performing pre update operation..."
			Run-PreUpdateScripts
  }
  "postUpdateScripts" {
			Write-Host "Performing post update operation..."
			Run-PostUpdateScripts
  }
  "fullService" {
			Write-Host "Performing full service operation for us, lazy boys..."
			Recreate-Database
			Restore-Database
			Run-PreUpdateScripts
			Update-Database
			Run-PostUpdateScripts
  }
  Default {
			Write-Error "Invalid Operation specified: $o. Valid values are 'restore', 'recreate', or 'update'."
			Exit 1
  }
	}
}


