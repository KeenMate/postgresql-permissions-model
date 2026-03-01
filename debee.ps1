#!/usr/bin/env pwsh

param (
	# Parameter help description
	[string]$Environment,
	[Parameter(Mandatory = $true)]
	[ValidateSet("restoreDatabase", "recreateDatabase", "updateDatabase", "preUpdateScripts", "postUpdateScripts", "prepareVersionTable", "execSql", "runTests", "fullService")]
	[string[]]$Operations = @("fullService"),
	[int]$UpdateStartNumber = -1,
	[int]$UpdateEndNumber = -1,
	[string]$SqlFile,
	[string]$Sql,
	[string]$TestFilter = "all",
	[switch]$TestVerbose
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
		# Skip files that don't match pattern: 3 digits + underscore + name + .sql extension
		if ($file.Name -notmatch '^\d{3}_.*\.sql$') {
			Write-Host "Skipping file (not matching pattern XXX_*.sql): $($file.Name)"
			continue
		}

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

function Prepare-VersionTable {
	Write-Host "Preparing version table - extracting database objects"

	# Get configuration values
	$formatsStr = if ($env:DBVERSIONTABLEFORMATS) { $env:DBVERSIONTABLEFORMATS } else { "json;md" }
	$outputFolder = if ($env:DBVERSIONTABLEOUTPUTFOLDER) { $env:DBVERSIONTABLEOUTPUTFOLDER } else { "." }
	$baseFilename = if ($env:DBVERSIONTABLEFILENAME) { $env:DBVERSIONTABLEFILENAME } else { "db-objects" }

	# Remove comments from formats string (anything after #)
	if ($formatsStr -match '^([^#]*)') {
		$formatsStr = $matches[1].Trim()
	}

	# Parse formats
	$formats = $formatsStr -split ';' | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim().ToLower() }

	if ($formats.Count -eq 0) {
		Write-Host "No version table formats specified, using default: json, md"
		$formats = @("json", "md")
	}

	# Validate formats
	$validFormats = @("json", "md", "markdown", "csv", "html")
	$invalidFormats = $formats | Where-Object { $_ -notin $validFormats }
	if ($invalidFormats) {
		Write-Error "Invalid formats: $($invalidFormats -join ', '). Valid formats: json, md, csv, html"
		return
	}

	# Normalize markdown format
	$formats = $formats | ForEach-Object { if ($_ -eq "md") { "markdown" } else { $_ } }

	Write-Host "Version table configuration:"
	Write-Host "  Formats: $($formats -join ', ')"
	Write-Host "  Output folder: $outputFolder"
	Write-Host "  Base filename: $baseFilename"

	# Check if extract-db-objects.py exists
	if (-not (Test-Path "extract-db-objects.py")) {
		Write-Error "extract-db-objects.py not found in current directory"
		return
	}

	# Create output folder if it doesn't exist
	if (-not (Test-Path $outputFolder)) {
		try {
			New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null
			Write-Host "Created output folder: $outputFolder"
		}
		catch {
			Write-Error "Failed to create output folder: $_"
			return
		}
	}

	# Determine Python command
	$pythonCmd = if (Get-Command python3 -ErrorAction SilentlyContinue) { "python3" } else { "python" }

	$generatedFiles = @()

	try {
		# Generate each requested format
		foreach ($fmt in $formats) {
			# Determine extension
			$extension = if ($fmt -eq "markdown") { "md" } else { $fmt }
			$outputFile = Join-Path $outputFolder "$baseFilename.$extension"

			Write-Host "Generating $($fmt.ToUpper()) format: $outputFile"

			$result = & $pythonCmd "extract-db-objects.py" --format $fmt --output $outputFile 2>&1
			if ($LASTEXITCODE -ne 0) {
				Write-Error "Failed to generate $fmt`: $result"
				return
			}

			if (Test-Path $outputFile) {
				Write-Host "Successfully generated $outputFile" -ForegroundColor Green
				$generatedFiles += $outputFile
			}
			else {
				Write-Error "$outputFile was not created"
				return
			}
		}

		if ($generatedFiles.Count -gt 0) {
			Write-Host "Version table preparation completed successfully" -ForegroundColor Green
			Write-Host "Generated files: $($generatedFiles -join ', ')"
		}
		else {
			Write-Host "No files were generated" -ForegroundColor Yellow
		}
	}
	catch {
		Write-Error "Failed to prepare version table: $_"
		return
	}
}

function Exec-Sql {
	param (
		[string]$File,
		[string]$Command
	)

	Set-CurrentDatabase -databaseName $Env:DBDESTDB

	if (-not [string]::IsNullOrEmpty($File)) {
		Write-Host "Executing SQL file: $File"
		& $Env:DBPSQLFILE -f "$File"
	}
	elseif (-not [string]::IsNullOrEmpty($Command)) {
		Write-Host "Executing SQL command"
		& $Env:DBPSQLFILE -c "$Command"
	}
	else {
		Write-Host "Opening interactive psql session against $Env:DBDESTDB ..."
		& $Env:DBPSQLFILE
	}
}

function Read-TestManifest {
	param (
		[Parameter(Mandatory)]
		[string]$SuiteDir
	)

	$folderName = Split-Path $SuiteDir -Leaf
	# Default name: humanize folder name (strip test_ prefix, title case)
	$displayName = $folderName
	if ($displayName.StartsWith("test_")) {
		$displayName = $displayName.Substring(5)
	}
	$displayName = (Get-Culture).TextInfo.ToTitleCase($displayName.Replace("_", " "))

	$manifest = @{
		Name = $displayName
		Description = ""
		AlwaysCleanup = $true
		Isolation = "none"
		Setup = @()
	}

	$manifestFile = Join-Path $SuiteDir "test.json"
	if (Test-Path $manifestFile) {
		try {
			$data = Get-Content $manifestFile -Raw | ConvertFrom-Json
			if ($data.name) { $manifest.Name = $data.name }
			if ($data.description) { $manifest.Description = $data.description }
			if ($null -ne $data.always_cleanup) { $manifest.AlwaysCleanup = [bool]$data.always_cleanup }
			if ($data.isolation) {
				$validIsolations = @("none", "transaction", "database")
				if ($data.isolation -in $validIsolations) {
					$manifest.Isolation = $data.isolation
				}
				else {
					Write-Warning "Unknown isolation mode '$($data.isolation)', using 'none'"
				}
			}
			if ($null -ne $data.setup) {
				if ($data.setup -is [array]) {
					$manifest.Setup = @($data.setup)
				}
				else {
					Write-Warning "'setup' in test.json must be a list, ignoring"
				}
			}
		}
		catch {
			Write-Warning "Failed to read ${manifestFile}: $_"
		}
	}

	return $manifest
}

function Invoke-TestSqlFile {
	param (
		[Parameter(Mandatory)]
		[string]$FilePath,
		[switch]$ShowDetail
	)

	$result = @{
		Name = Split-Path $FilePath -Leaf
		Passed = $true
		PassCount = 0
		FailCount = 0
		Error = $false
	}

	$output = & $Env:DBPSQLFILE -f "$FilePath" 2>&1 | Out-String
	$exitCode = $LASTEXITCODE

	# psql nonzero exit code = automatic FAIL
	if ($exitCode -ne 0) {
		$result.Error = $true
		$result.Passed = $false
	}

	# Count PASS/FAIL occurrences
	$result.PassCount = ([regex]::Matches($output, "PASS")).Count
	$result.FailCount = ([regex]::Matches($output, "FAIL")).Count

	if ($result.FailCount -gt 0 -or $result.Error) {
		$result.Passed = $false
	}

	# Colorize and print output
	$lines = $output -split "`n"
	if ($ShowDetail) {
		foreach ($line in $lines) {
			if ($line -match "PASS") {
				Write-Host "  $line" -ForegroundColor Green
			}
			elseif ($line -match "FAIL") {
				Write-Host "  $line" -ForegroundColor Red
			}
			else {
				Write-Host "  $line"
			}
		}
	}
	elseif (-not $result.Passed) {
		# Silent mode: only print FAIL lines and error context
		foreach ($line in $lines) {
			if ($line -match "FAIL") {
				Write-Host "  $line" -ForegroundColor Red
			}
			elseif ($line -match "ERROR|error") {
				Write-Host "  $line" -ForegroundColor Red
			}
		}
	}

	return $result
}

function Invoke-SuiteTransaction {
	param (
		[Parameter(Mandatory)]
		[string]$SuiteDir,
		[Parameter(Mandatory)]
		[hashtable]$Manifest,
		[Parameter(Mandatory)]
		[array]$MainFiles,
		[array]$CleanupFiles = @(),
		[switch]$ShowDetail
	)

	$suiteResult = @{
		Name = $Manifest.Name
		Passed = $true
		PassCount = 0
		FailCount = 0
		Error = $false
		IsSuite = $true
	}

	$testsDir = "tests"

	# Build wrapper SQL
	$wrapperLines = @("\set ON_ERROR_STOP on", "BEGIN;")

	# Add shared setup files
	foreach ($setupPath in $Manifest.Setup) {
		$resolved = Join-Path $testsDir $setupPath
		if (Test-Path $resolved) {
			$posixPath = $resolved -replace '\\', '/'
			$wrapperLines += "\echo '>>>DEBEE_FILE: $setupPath<<<'"
			$wrapperLines += "\i '$posixPath'"
		}
		else {
			Write-Warning "Shared setup file not found: $setupPath"
		}
	}

	# Add main files
	foreach ($f in $MainFiles) {
		$posixPath = $f.FullName -replace '\\', '/'
		$wrapperLines += "\echo '>>>DEBEE_FILE: $($f.Name)<<<'"
		$wrapperLines += "\i '$posixPath'"
	}

	$wrapperLines += "ROLLBACK;"

	# Write temp file
	$tmpFile = [System.IO.Path]::Combine($SuiteDir, "_debee_txn_wrapper_$([System.IO.Path]::GetRandomFileName()).sql")
	try {
		$wrapperLines -join "`n" | Set-Content -Path $tmpFile -Encoding UTF8

		# Run via psql
		$output = & $Env:DBPSQLFILE -f "$tmpFile" 2>&1 | Out-String
		$exitCode = $LASTEXITCODE

		if ($exitCode -ne 0) {
			$suiteResult.Error = $true
		}

		# Parse output by >>>DEBEE_FILE: ...<<< markers
		$currentFile = "(preamble)"
		$fileOutputs = [ordered]@{}
		$lines = $output -split "`n"

		foreach ($line in $lines) {
			if ($line -match '>>>DEBEE_FILE: (.+)<<<') {
				$currentFile = $matches[1]
				if (-not $fileOutputs.Contains($currentFile)) {
					$fileOutputs[$currentFile] = @()
				}
			}
			else {
				if (-not $fileOutputs.Contains($currentFile)) {
					$fileOutputs[$currentFile] = @()
				}
				$fileOutputs[$currentFile] += $line
			}
		}

		# Print and count per section
		foreach ($sectionName in $fileOutputs.Keys) {
			$sectionText = $fileOutputs[$sectionName] -join "`n"
			$sectionPassCount = ([regex]::Matches($sectionText, "PASS")).Count
			$sectionFailCount = ([regex]::Matches($sectionText, "FAIL")).Count
			$suiteResult.PassCount += $sectionPassCount
			$suiteResult.FailCount += $sectionFailCount

			$sectionHasFailures = $sectionFailCount -gt 0

			if ($ShowDetail) {
				if ($sectionName -ne "(preamble)") {
					Write-Host "`n  -- $sectionName --"
				}
				foreach ($line in $fileOutputs[$sectionName]) {
					if ($line -match "PASS") {
						Write-Host "  $line" -ForegroundColor Green
					}
					elseif ($line -match "FAIL") {
						Write-Host "  $line" -ForegroundColor Red
					}
					else {
						Write-Host "  $line"
					}
				}
			}
			elseif ($sectionHasFailures) {
				if ($sectionName -ne "(preamble)") {
					Write-Host "`n  -- $sectionName --"
				}
				foreach ($line in $fileOutputs[$sectionName]) {
					if ($line -match "FAIL") {
						Write-Host "  $line" -ForegroundColor Red
					}
					elseif ($line -match "ERROR|error") {
						Write-Host "  $line" -ForegroundColor Red
					}
				}
			}
		}
	}
	finally {
		if (Test-Path $tmpFile) {
			Remove-Item $tmpFile -Force
		}
	}

	# Run cleanup files individually after rollback
	if ($CleanupFiles.Count -gt 0 -and ($Manifest.AlwaysCleanup -or -not $suiteResult.Error)) {
		foreach ($f in $CleanupFiles) {
			if ($ShowDetail) {
				Write-Host "`n  -- $($f.Name) (cleanup) --"
			}
			$cleanupResult = Invoke-TestSqlFile -FilePath $f.FullName -ShowDetail:$ShowDetail
			if (-not $cleanupResult.Passed -and -not $ShowDetail) {
				Write-Host "`n  -- $($f.Name) (cleanup) --"
			}
			if (-not $cleanupResult.Passed) {
				Write-Warning "Cleanup file $($f.Name) had issues (non-fatal)"
			}
		}
	}

	$suiteResult.Passed = ($suiteResult.FailCount -eq 0) -and (-not $suiteResult.Error)
	return $suiteResult
}

function Invoke-FlatTest {
	param (
		[Parameter(Mandatory)]
		[System.IO.FileInfo]$TestFile,
		[switch]$ShowDetail
	)

	if ($ShowDetail) {
		Write-Host "`n--- $($TestFile.Name) ---"
	}
	$result = Invoke-TestSqlFile -FilePath $TestFile.FullName -ShowDetail:$ShowDetail
	if (-not $ShowDetail -and -not $result.Passed) {
		Write-Host "`n--- $($TestFile.Name) --- " -NoNewline
		Write-Host "FAILED" -ForegroundColor Red
	}
	$result.IsSuite = $false
	return $result
}

function Invoke-SuiteTest {
	param (
		[Parameter(Mandatory)]
		[string]$SuiteDir,
		[switch]$ShowDetail
	)

	$manifest = Read-TestManifest -SuiteDir $SuiteDir

	$suiteResult = @{
		Name = $manifest.Name
		Passed = $true
		PassCount = 0
		FailCount = 0
		Error = $false
		IsSuite = $true
	}

	$suiteHeaderPrinted = $false
	if ($ShowDetail) {
		Write-Host "`n=== Suite: $($manifest.Name) ==="
		if ($manifest.Description) {
			Write-Host $manifest.Description
		}
		$suiteHeaderPrinted = $true
	}

	# Discover SQL files matching NNN_*.sql
	$allFiles = Get-ChildItem -Path $SuiteDir -File | Sort-Object Name
	$mainFiles = @()
	$cleanupFiles = @()

	foreach ($f in $allFiles) {
		if ($f.Name -match '^\d{3}_.*\.sql$') {
			$prefix = [int]($f.Name.Substring(0, 3))
			if ($prefix -ge 900 -and $prefix -le 999) {
				$cleanupFiles += $f
			}
			else {
				$mainFiles += $f
			}
		}
		elseif ($f.Name -ne "test.json") {
			Write-Warning "Skipping non-matching file in suite: $($f.Name)"
		}
	}

	# Branch on isolation mode
	if ($manifest.Isolation -eq "transaction") {
		$suiteResult = Invoke-SuiteTransaction -SuiteDir $SuiteDir -Manifest $manifest -MainFiles $mainFiles -CleanupFiles $cleanupFiles -ShowDetail:$ShowDetail
	}
	elseif ($manifest.Isolation -eq "database") {
		# Recreate + restore database before suite
		Write-Host "  [database isolation] Recreating database..."
		Recreate-Database
		if ($Env:DBBACKUPFILE) {
			Write-Host "  [database isolation] Restoring database..."
			Restore-Database
		}
		Set-CurrentDatabase -databaseName $Env:DBDESTDB

		# Run shared setup files individually
		$testsDir = "tests"
		foreach ($setupPath in $manifest.Setup) {
			$resolved = Join-Path $testsDir $setupPath
			if (Test-Path $resolved) {
				if ($ShowDetail) { Write-Host "`n  -- $setupPath (shared setup) --" }
				Invoke-TestSqlFile -FilePath $resolved -ShowDetail:$ShowDetail | Out-Null
			}
			else {
				Write-Warning "Shared setup file not found: $setupPath"
			}
		}

		# Run main files individually
		$mainFailed = $false
		foreach ($f in $mainFiles) {
			if ($ShowDetail) { Write-Host "`n  -- $($f.Name) --" }
			$fileResult = Invoke-TestSqlFile -FilePath $f.FullName -ShowDetail:$ShowDetail
			$suiteResult.PassCount += $fileResult.PassCount
			$suiteResult.FailCount += $fileResult.FailCount
			if (-not $fileResult.Passed) {
				if (-not $suiteHeaderPrinted) {
					Write-Host "`n=== Suite: $($manifest.Name) ==="
					$suiteHeaderPrinted = $true
				}
				if (-not $ShowDetail) { Write-Host "`n  -- $($f.Name) --" }
				$mainFailed = $true
				break
			}
		}

		if ($cleanupFiles.Count -gt 0 -and ($manifest.AlwaysCleanup -or -not $mainFailed)) {
			foreach ($f in $cleanupFiles) {
				if ($ShowDetail) { Write-Host "`n  -- $($f.Name) (cleanup) --" }
				$cleanupResult = Invoke-TestSqlFile -FilePath $f.FullName -ShowDetail:$ShowDetail
				if (-not $cleanupResult.Passed -and -not $ShowDetail) {
					Write-Host "`n  -- $($f.Name) (cleanup) --"
				}
				if (-not $cleanupResult.Passed) {
					Write-Warning "Cleanup file $($f.Name) had issues (non-fatal)"
				}
			}
		}

		$suiteResult.Passed = (-not $mainFailed) -and ($suiteResult.FailCount -eq 0)
	}
	else {
		# "none" — current behavior with shared setup
		$testsDir = "tests"
		foreach ($setupPath in $manifest.Setup) {
			$resolved = Join-Path $testsDir $setupPath
			if (Test-Path $resolved) {
				if ($ShowDetail) { Write-Host "`n  -- $setupPath (shared setup) --" }
				Invoke-TestSqlFile -FilePath $resolved -ShowDetail:$ShowDetail | Out-Null
			}
			else {
				Write-Warning "Shared setup file not found: $setupPath"
			}
		}

		# Run main phase (stop on first failure)
		$mainFailed = $false
		foreach ($f in $mainFiles) {
			if ($ShowDetail) { Write-Host "`n  -- $($f.Name) --" }
			$fileResult = Invoke-TestSqlFile -FilePath $f.FullName -ShowDetail:$ShowDetail
			$suiteResult.PassCount += $fileResult.PassCount
			$suiteResult.FailCount += $fileResult.FailCount

			if (-not $fileResult.Passed) {
				if (-not $suiteHeaderPrinted) {
					Write-Host "`n=== Suite: $($manifest.Name) ==="
					$suiteHeaderPrinted = $true
				}
				if (-not $ShowDetail) { Write-Host "`n  -- $($f.Name) --" }
				$mainFailed = $true
				break
			}
		}

		# Run cleanup phase
		if ($cleanupFiles.Count -gt 0 -and ($manifest.AlwaysCleanup -or -not $mainFailed)) {
			foreach ($f in $cleanupFiles) {
				if ($ShowDetail) { Write-Host "`n  -- $($f.Name) (cleanup) --" }
				$cleanupResult = Invoke-TestSqlFile -FilePath $f.FullName -ShowDetail:$ShowDetail
				if (-not $cleanupResult.Passed -and -not $ShowDetail) {
					Write-Host "`n  -- $($f.Name) (cleanup) --"
				}
				if (-not $cleanupResult.Passed) {
					Write-Warning "Cleanup file $($f.Name) had issues (non-fatal)"
				}
			}
		}

		$suiteResult.Passed = (-not $mainFailed) -and ($suiteResult.FailCount -eq 0)
	}

	$status = if ($suiteResult.Passed) { "PASSED" } else { "FAILED" }
	if ($suiteResult.Passed) {
		if ($ShowDetail) {
			Write-Host "`nSuite $($manifest.Name): $status" -ForegroundColor Green
		}
	}
	else {
		if (-not $suiteHeaderPrinted) {
			Write-Host "`n=== Suite: $($manifest.Name) ==="
		}
		Write-Host "`nSuite $($manifest.Name): $status" -ForegroundColor Red
	}

	return $suiteResult
}

function Run-Tests {
	param (
		[string]$Filter = "all",
		[switch]$ShowDetail
	)

	$testsDir = "tests"

	if (-not (Test-Path $testsDir)) {
		Write-Warning "Tests directory not found: $testsDir"
		return
	}

	Set-CurrentDatabase -databaseName $Env:DBDESTDB

	# Discover test items: flat test_*.sql files + test_*/ directories
	$testItems = @()

	$allEntries = Get-ChildItem -Path $testsDir | Sort-Object Name
	foreach ($entry in $allEntries) {
		if ($entry.PSIsContainer -and $entry.Name -like "test_*") {
			$testItems += @{ Type = "suite"; Path = $entry.FullName; Name = $entry.Name }
		}
		elseif (-not $entry.PSIsContainer -and $entry.Name -like "test_*.sql") {
			$testItems += @{ Type = "file"; Path = $entry; Name = $entry.Name }
		}
	}

	# Apply global ordering from tests/tests.json
	$testsJsonPath = Join-Path $testsDir "tests.json"
	if (Test-Path $testsJsonPath) {
		try {
			$testsConfig = Get-Content $testsJsonPath -Raw | ConvertFrom-Json
			if ($testsConfig.order) {
				$ordered = @()
				$remaining = [System.Collections.ArrayList]@($testItems)
				foreach ($name in $testsConfig.order) {
					for ($i = 0; $i -lt $remaining.Count; $i++) {
						if ($remaining[$i].Name -eq $name) {
							$ordered += $remaining[$i]
							$remaining.RemoveAt($i)
							break
						}
					}
				}
				$testItems = $ordered + @($remaining)
			}
		}
		catch {
			Write-Warning "Failed to read ${testsJsonPath}: $_"
		}
	}

	# Apply filter
	if ($Filter -ne "all") {
		$testItems = $testItems | Where-Object { $_.Name -match $Filter }
	}

	if ($testItems.Count -eq 0) {
		Write-Warning "No test items found matching filter: $Filter"
		return
	}

	$fileCount = ($testItems | Where-Object { $_.Type -eq "file" }).Count
	$suiteCount = ($testItems | Where-Object { $_.Type -eq "suite" }).Count
	if ($ShowDetail) {
		Write-Host "Running $($testItems.Count) test item(s) ($fileCount file(s), $suiteCount suite(s))..."
	}

	$results = @()

	foreach ($item in $testItems) {
		if ($item.Type -eq "file") {
			$results += Invoke-FlatTest -TestFile $item.Path -ShowDetail:$ShowDetail
		}
		else {
			$results += Invoke-SuiteTest -SuiteDir $item.Path -ShowDetail:$ShowDetail
		}
	}

	# Summary
	$totalPass = ($results | ForEach-Object { $_.PassCount } | Measure-Object -Sum).Sum
	$totalFail = ($results | ForEach-Object { $_.FailCount } | Measure-Object -Sum).Sum
	$errorOnly = ($results | Where-Object { $_.Error -and $_.FailCount -eq 0 }).Count

	$suitePassed = ($results | Where-Object { $_.IsSuite -and $_.Passed }).Count
	$suiteFailed = ($results | Where-Object { $_.IsSuite -and -not $_.Passed }).Count
	$filePassed = ($results | Where-Object { -not $_.IsSuite -and $_.Passed }).Count
	$fileFailed = ($results | Where-Object { -not $_.IsSuite -and -not $_.Passed }).Count

	Write-Host "`n=== Test Summary ==="
	Write-Host "PASSED: $totalPass" -ForegroundColor Green
	if ($totalFail -gt 0 -or $errorOnly -gt 0) {
		$failMsg = "FAILED: $totalFail"
		if ($errorOnly -gt 0) { $failMsg += " (+$errorOnly error(s))" }
		Write-Host $failMsg -ForegroundColor Red
	}
	else {
		Write-Host "FAILED: $totalFail"
	}
	Write-Host "Total:  $($totalPass + $totalFail)"
	if ($suiteCount -gt 0) {
		Write-Host "Suites: $suitePassed passed, $suiteFailed failed"
	}
	if ($fileCount -gt 0) {
		Write-Host "Files:  $filePassed passed, $fileFailed failed"
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
  "prepareVersionTable" {
			Write-Host "Performing prepare version table operation..."
			Prepare-VersionTable
  }
  "execSql" {
			Write-Host "Performing exec SQL operation..."
			Exec-Sql -File $SqlFile -Command $Sql
  }
  "runTests" {
			Write-Host "Performing run tests operation..."
			Run-Tests -Filter $TestFilter -ShowDetail:$TestVerbose
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

