#!/usr/bin/env pwsh

[CmdletBinding(DefaultParameterSetName = "Run")]
param (
	# Parameter help description
	[string]$Environment,
	[Parameter(ParameterSetName = "Run")]
	[ValidateSet("restoreDatabase", "recreateDatabase", "updateDatabase", "preUpdateScripts", "postUpdateScripts", "prepareVersionTable", "execSql", "runTests", "fullService")]
	[string[]]$Operations,
	[int]$UpdateStartNumber = -1,
	[int]$UpdateEndNumber = -1,
	[string]$SqlFile,
	[string]$Sql,
	[string]$TestFilter = "all",
	[switch]$TestVerbose,
	[Alias("q")]
	[switch]$Silent,
	[Alias("y")]
	[switch]$Yes,
	[Parameter(Mandatory = $true, ParameterSetName = "Version")]
	[Alias("V")]
	[switch]$Version,
	[Parameter(Mandatory = $true, ParameterSetName = "Llm")]
	[switch]$Llm,
	[Parameter(Mandatory = $true, ParameterSetName = "Help")]
	[Alias("h", "?")]
	[switch]$Help
)

$DebeeVersion = "1.1.0"

function Show-DebeeHelp {
	Write-Host ""
	Write-Host "  debee v$DebeeVersion" -ForegroundColor Cyan -NoNewline
	Write-Host " — PostgreSQL Migration Orchestrator"
	Write-Host "  Use -Help for full reference"
	Write-Host ""
	Write-Host "  Usage:"
	Write-Host "    .\debee.ps1 -Operations <op>[,<op>...] [options]"
	Write-Host ""
	Write-Host "  Operations:"
	Write-Host "    recreateDatabase             " -NoNewline -ForegroundColor Green
	Write-Host "Drop and recreate database from script"
	Write-Host "    restoreDatabase              " -NoNewline -ForegroundColor Green
	Write-Host "Restore from backup (file/dir/custom)"
	Write-Host "    updateDatabase               " -NoNewline -ForegroundColor Green
	Write-Host "Apply numbered migration files in NNN_*.sql range"
	Write-Host "    preUpdateScripts             " -NoNewline -ForegroundColor Green
	Write-Host "Run scripts listed in DBPREUPDATESCRIPTS"
	Write-Host "    postUpdateScripts            " -NoNewline -ForegroundColor Green
	Write-Host "Run scripts listed in DBPOSTUPDATESCRIPTS"
	Write-Host "    prepareVersionTable          " -NoNewline -ForegroundColor Green
	Write-Host "Extract DB objects to JSON/MD/CSV/HTML"
	Write-Host "    execSql                      " -NoNewline -ForegroundColor Green
	Write-Host "Run ad-hoc SQL via -Sql or -SqlFile (interactive if neither)"
	Write-Host "    runTests                     " -NoNewline -ForegroundColor Green
	Write-Host "Run SQL test files / suites from tests/"
	Write-Host "    fullService                  " -NoNewline -ForegroundColor Green
	Write-Host "recreate + restore + pre/post + update (destructive)"
	Write-Host ""
	Write-Host "  Options:"
	Write-Host "    -Environment <name>          Load debee.<name>.env instead of debee.env"
	Write-Host "    -UpdateStartNumber <n>       First migration file number (default: env DBUPDATESTARTNUMBER)"
	Write-Host "    -UpdateEndNumber <n>         Last migration file number (default: env DBUPDATEENDNUMBER)"
	Write-Host "    -SqlFile <path>              SQL file to execute (execSql)"
	Write-Host "    -Sql ""<query>""               SQL command to execute inline (execSql)"
	Write-Host "    -TestFilter <pattern>        Filter test files by pattern (runTests, default: all)"
	Write-Host "    -TestVerbose                 Show all test output including PASS lines"
	Write-Host "    -Silent, -q                  Suppress orchestration messages (env load, banners, progress)"
	Write-Host "    -Yes, -y                     Skip production confirmation (DBPRODENVIRONMENT=true bypass)"
	Write-Host "    -Version, -V                 Print version and exit"
	Write-Host "    -Help, -h                    Show this help"
	Write-Host "    -Llm                         Print full CLI reference for LLM/AI assistants and exit"
	Write-Host ""
	Write-Host "  Examples:"
	Write-Host "    .\debee.ps1 -Operations execSql -Sql ""SELECT 1;"""
	Write-Host "    .\debee.ps1 -Operations execSql -Sql ""SELECT version();"" -Silent"
	Write-Host "    .\debee.ps1 -Operations updateDatabase -UpdateStartNumber 10 -UpdateEndNumber 20"
	Write-Host "    .\debee.ps1 -Operations runTests -TestFilter connection"
	Write-Host "    .\debee.ps1 -Environment prod -Operations fullService"
	Write-Host ""
}

function Show-DebeeLlm {
	Write-Host "debee v$DebeeVersion - PostgreSQL Migration Orchestrator"
	Write-Host @'

Cross-platform database migration runner for PostgreSQL. Three interchangeable implementations:
  debee.ps1 (PowerShell, Windows-primary) | debee.sh (Bash, Linux/macOS) | debee.py (Python, cross-platform)

CONCEPT

debee is a pure orchestration layer: all database logic lives in external .sql files. It reads
connection + behavior settings from .env files, then runs a sequence of operations (recreate /
restore / migrate / test / document) against a target PostgreSQL database using the system `psql`
and `pg_restore` binaries. It performs no DB logic of its own beyond invoking those SQL files.

INVOCATION

  PowerShell:  .\debee.ps1 -Operations <op>[,<op>...] [options]
  Bash:        ./debee.sh   -o <op>[,<op>...] [options]
  Python:      python debee.py -o <op>[,<op>...] [options]

Run from the directory that holds your .env file, migration files (NNN_*.sql), and (as needed) the
recreate script, backup file, tests/ folder, and extract-db-objects.py. Migration files and tests
are discovered relative to the current working directory.

OPERATIONS  (comma-separated; default: fullService)

  recreateDatabase     Drop and recreate the target DB by running the SQL script in DBRECREATESCRIPT,
                       connected to DBCONNECTDB. Destructive.
  restoreDatabase      Restore the target DB from DBBACKUPFILE using pg_restore (or psql for plain
                       SQL). Format set by DBBACKUPTYPE (custom/plain/dir/tar). Parallel jobs via
                       DBRESTOREJOBCOUNT. Optionally creates the DB first when DBCREATEONRESTORE=true.
  updateDatabase       Apply numbered migration files matching ^NNN_*.sql in the current directory,
                       ascending, within the [start..end] range. Empty files are skipped.
  preUpdateScripts     Run the semicolon-separated SQL files in DBPREUPDATESCRIPTS (before update).
  postUpdateScripts    Run the semicolon-separated SQL files in DBPOSTUPDATESCRIPTS (after update).
  prepareVersionTable  Extract DB objects via extract-db-objects.py and emit documentation in the
                       formats from DBVERSIONTABLEFORMATS (json;md;csv;html) to DBVERSIONTABLEOUTPUTFOLDER.
  execSql              Run ad-hoc SQL: inline via --sql / -Sql, or a file via --sql-file / -SqlFile.
                       With neither, opens an interactive psql session against the target DB.
  runTests             Run SQL test files / suites from the tests/ folder. Global ordering from
                       tests/tests.json. Filter with --test-filter; show PASS lines with --test-verbose.
  fullService          recreateDatabase + restoreDatabase + preUpdateScripts + updateDatabase +
                       postUpdateScripts, in sequence. Destructive - recreates and restores the DB.

MIGRATION FILE NAMING

  Pattern: NNN_description.sql
    NNN          exactly 3 digits (001, 060, 999) - the ordering/selection key
    _            underscore separator
    description  any text
    .sql         required extension
  Files not matching ^\d{3}_.*\.sql$ are ignored. The range is inclusive; -1 means unbounded on that
  end (start=-1, end=-1 -> all files). Start must not exceed a non-(-1) end.

OPTIONS  (PowerShell / Bash + Python)

  -Operations        / -o, --operations      Comma-separated operations (default fullService)
  -Environment       / -e, --environment      Load debee.<name>.env instead of debee.env
  -UpdateStartNumber / -s, --start-number     First migration number (default: env DBUPDATESTARTNUMBER, else all)
  -UpdateEndNumber   / -n, --end-number       Last migration number  (default: env DBUPDATEENDNUMBER, else all)
  -SqlFile           / --sql-file             SQL file to run (execSql)
  -Sql               / --sql                  Inline SQL to run (execSql)
  -TestFilter        / --test-filter          Filter test files by pattern (runTests; default all)
  -TestVerbose       / --test-verbose         Show all test output including PASS lines
  -Silent, -q        / -q, --silent           Suppress orchestration messages; errors + psql output remain
  -Yes, -y           / -y, --yes              Skip production confirmation (needed for automation when DBPRODENVIRONMENT=true)
  -Version, -V       / -V, --version          Print version and exit
  -Help, -h          / -h, --help             Show short help
  -Llm               / --llm                  Print this reference document

ENVIRONMENT FILES  (loaded from the current directory)

  With -Environment/-e NAME:  debee.<NAME>.env   then  .debee.<NAME>.env   (local overrides, gitignored)
  Without an environment:     debee.env          then  .debee.env
  The base file must exist; the .local file is optional and layered on top (later wins).

ENVIRONMENT VARIABLES

  Connection (standard libpq):
    PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE
  Core:
    DBDESTDB              Target database name (required by most operations)
    DBCONNECTDB           Maintenance/connect DB used while dropping/creating (e.g. postgres)
    DBRECREATESCRIPT      SQL file run by recreateDatabase
  Restore:
    DBBACKUPFILE          Path to the backup to restore
    DBBACKUPTYPE          Backup format: custom (default) / plain / dir / tar
    DBRESTOREJOBCOUNT     Parallel pg_restore jobs (-j)
    DBCREATEONRESTORE     true -> create the DB before restoring
  Migrations:
    DBUPDATESTARTNUMBER   Default start number when -s/-UpdateStartNumber not given
    DBUPDATEENDNUMBER     Default end number when -n/-UpdateEndNumber not given
    DBPREUPDATESCRIPTS    Semicolon-separated SQL files for preUpdateScripts
    DBPOSTUPDATESCRIPTS   Semicolon-separated SQL files for postUpdateScripts
  Version table:
    DBVERSIONTABLEFORMATS       Semicolon list: json;md;csv;html (default json;md)
    DBVERSIONTABLEOUTPUTFOLDER  Output directory (default .)
    DBVERSIONTABLEFILENAME      Base output filename (default db-objects)
  Tooling / safety:
    DBPSQLFILE            psql binary/path (default psql)
    DBPGRESTOREFILE       pg_restore binary/path (default pg_restore)
    DBPRODENVIRONMENT     true -> require typed 'yes' confirmation before running (bypass with -Yes/-y)

PRODUCTION CONFIRMATION

  When DBPRODENVIRONMENT=true, debee prints the host/user/target-DB and operation list and requires
  the user to type 'yes' before proceeding. Pass -Yes/-y to skip it in automated/CI runs.

EXAMPLES

  .\debee.ps1 -Operations fullService -Environment prod
  ./debee.sh      -e dev -o restoreDatabase,updateDatabase
  python debee.py -o updateDatabase -s 10 -n 20
  .\debee.ps1 -Operations execSql -Sql "SELECT version();" -Silent
  ./debee.sh      -o execSql --sql-file script.sql
  python debee.py -o runTests --test-filter connection
'@
}

if ($Version) {
	Write-Host "debee.ps1 $DebeeVersion"
	exit 0
}

if ($Llm) {
	Show-DebeeLlm
	exit 0
}

if ($Help -or -not $Operations) {
	Show-DebeeHelp
	exit 0
}

function Write-Info {
	param([Parameter(ValueFromRemainingArguments = $true)]$Message)
	if (-not $Silent) {
		Write-Host @Message
	}
}

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

		Write-Info "Environment variables set successfully from $envFilePath"
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

	$rangeText = if ($StartNumber -eq -1 -and $EndNumber -eq -1) { "all" }
		elseif ($EndNumber -eq -1) { "$StartNumber onwards" }
		elseif ($StartNumber -eq -1) { "up to $EndNumber" }
		else { "$StartNumber -> $EndNumber" }
	Write-Warning "Scripts to run: $rangeText"
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
			Write-Info "Skipping file (not matching pattern XXX_*.sql): $($file.Name)"
			continue
		}

		# Extract the numeric prefix and convert it to an integer
		$prefix = [int]($file.Name -replace '^(\d{3})_.*$', '$1')

		if (($prefix -ge $StartNumber -or $StartNumber -eq -1) -and ($prefix -le $EndNumber -or $EndNumber -eq -1)) {
			Write-Info "File: $( $file.Name ) is within the update range."
			# Add the matching file to the $matchingFiles array
			$matchingFiles += $file
		}
	}

	Write-Info "Number of matching files: $( $matchingFiles.Count )"

	return $matchingFiles
}

function Recreate-Database {
	Set-CurrentDatabase -databaseName $Env:DBCONNECTDB

	Write-Info "Recreating database on host: "$Env:PGHOST", connected to: "$Env:PGDATABASE
	& $Env:DBPSQLFILE -f $Env:DBRECREATESCRIPT
}

function Restore-Database {
	param (
  # Parameter help description
		[string]$backupFilepath,
		[string]$backupType
	)

	Write-Info "Calculating backup type and path"

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
			Write-Info "Restoring from file: "$backupFilepath

			Set-CurrentDatabase -databaseName $Env:DBDESTDB

			& $Env:DBPSQLFILE -f "$backupFilepath"
		}
		"dir" {
			Write-Info "Restoring from directory: "$backupFilepath

			Set-CurrentDatabase -databaseName $Env:DBDESTDB

			if ($Env:DBCREATEONRESTORE -eq $true) {
				& $Env:DBPGRESTOREFILE -v -F d -C -d $Env:DBCONNECTDB "$backupFilepath"
			}
			else {
				& $Env:DBPGRESTOREFILE -v -F d -d $Env:DBDESTDB "$backupFilepath"
			}
		}
		"custom" {
			Write-Info "Restoring from custom archive: "$backupFilepath

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

	Write-Info "Number of returned files: $( $files.Count )"

	Update-DatabaseWithFiles -Files $files
}

function Run-PreUpdateScripts {
	$scriptsToRun = @()

	if (($Env:DBPREUPDATESCRIPTS).Length -eq 0) {
		Write-Info "No preupdate scripts, skipping the step"
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
			Write-Info "Pre update script file: $( $scriptPath ) to be run."
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
		Write-Info "No postupdate scripts, skipping the step"
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
			Write-Info "Post update script file: $( $scriptPath ) to be run."
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

	Write-Info "Updating database .."
	Set-CurrentDatabase -databaseName $Env:DBDESTDB

	Write-Info "Number of update files: $( $Files.Count )"

	$Files | Sort-Object -Property FullName |
	Where-Object { $_.Length -gt 0 -and $_.Name.Length -gt 0 } |
	ForEach-Object {
		Write-Info ".. with file: $( $_.Name )"

		# -v ON_ERROR_STOP=1
		& $Env:DBPSQLFILE -q -b -n --csv -f "$_"
	}

	$Filepaths |
	Where-Object { $_.Length -gt 0 } |
	ForEach-Object {
		Write-Info ".. with file: $( $_ )"

		# -v ON_ERROR_STOP=1
		& $Env:DBPSQLFILE -q -b -n --csv -f "$_"
	}
}

function Prepare-VersionTable {
	Write-Info "Preparing version table - extracting database objects"

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
		Write-Info "No version table formats specified, using default: json, md"
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

	Write-Info "Version table configuration:"
	Write-Info "  Formats: $($formats -join ', ')"
	Write-Info "  Output folder: $outputFolder"
	Write-Info "  Base filename: $baseFilename"

	# Check if extract-db-objects.py exists
	if (-not (Test-Path "extract-db-objects.py")) {
		Write-Error "extract-db-objects.py not found in current directory"
		return
	}

	# Create output folder if it doesn't exist
	if (-not (Test-Path $outputFolder)) {
		try {
			New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null
			Write-Info "Created output folder: $outputFolder"
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

			Write-Info "Generating $($fmt.ToUpper()) format: $outputFile"

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
			Write-Info "Generated files: $($generatedFiles -join ', ')"
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
		Write-Info "Executing SQL file: $File"
		& $Env:DBPSQLFILE -f "$File"
	}
	elseif (-not [string]::IsNullOrEmpty($Command)) {
		Write-Info "Executing SQL command"
		& $Env:DBPSQLFILE -c "$Command"
	}
	else {
		Write-Info "Opening interactive psql session against $Env:DBDESTDB ..."
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

			$sectionErrorCount = ([regex]::Matches($sectionText, "ERROR")).Count
			$sectionHasFailures = $sectionFailCount -gt 0 -or $sectionErrorCount -gt 0

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

# Resolve migration range: CLI param wins; otherwise fall back to env vars loaded above.
if ($UpdateStartNumber -eq -1 -and [int]$Env:DBUPDATESTARTNUMBER -gt 0) {
	$UpdateStartNumber = [int]$Env:DBUPDATESTARTNUMBER
}
if ($UpdateEndNumber -eq -1 -and [int]$Env:DBUPDATEENDNUMBER -ge 1) {
	$UpdateEndNumber = [int]$Env:DBUPDATEENDNUMBER
}

# Production confirmation
function Confirm-Production {
	$prodFlag = if ($Env:DBPRODENVIRONMENT) { $Env:DBPRODENVIRONMENT.Trim().ToLower() } else { "" }
	if ($prodFlag -ne "true" -and $prodFlag -ne "1") {
		return
	}
	if ($Yes) {
		return
	}

	$opsCsv = $Operations -join ","
	$sep = "=" * 50

	Write-Host ""
	Write-Host $sep -ForegroundColor Red
	Write-Host "  PRODUCTION ENVIRONMENT - CONFIRMATION REQUIRED" -ForegroundColor Red
	Write-Host $sep -ForegroundColor Red
	Write-Host ""
	if ($Environment) {
		Write-Host "  Environment:  $Environment"
	}
	$pgHost = if ($Env:PGHOST) { $Env:PGHOST } else { "localhost" }
	$pgPort = if ($Env:PGPORT) { $Env:PGPORT } else { "5432" }
	$pgUser = if ($Env:PGUSER) { $Env:PGUSER } else { "<unset>" }
	$destDb = if ($Env:DBDESTDB) { $Env:DBDESTDB } else { "<unset>" }
	Write-Host "  Host:         ${pgHost}:${pgPort}"
	Write-Host "  User:         $pgUser"
	Write-Host "  Target DB:    $destDb"
	Write-Host "  Operations:   $opsCsv"
	if ($Operations -contains "execSql") {
		if ($SqlFile) {
			Write-Host "  SQL file:     $SqlFile"
		}
		elseif ($Sql) {
			Write-Host "  SQL command:  $Sql"
		}
		else {
			Write-Host "  SQL:          (interactive psql session)"
		}
	}
	if ($Operations -contains "updateDatabase") {
		$rangeText = if ($UpdateStartNumber -eq -1 -and $UpdateEndNumber -eq -1) { "all" }
			elseif ($UpdateEndNumber -eq -1) { "$UpdateStartNumber onwards" }
			elseif ($UpdateStartNumber -eq -1) { "up to $UpdateEndNumber" }
			else { "$UpdateStartNumber -> $UpdateEndNumber" }
		Write-Host "  Migration range: $rangeText"
	}
	Write-Host ""

	$response = Read-Host '  Type "yes" to proceed (anything else aborts)'
	Write-Host ""

	if ($response.Trim().ToLower() -ne "yes") {
		Write-Host "Production run aborted by user." -ForegroundColor Red
		exit 1
	}
}

Confirm-Production

# Split the operation parameter for multiple operations in one go
# Iterate through each script path
foreach ($o in $Operations) {
	Write-Info "processing: "$o
	switch ($o) {
  "recreateDatabase" {
			Write-Info "Performing recreate operation..."
			Recreate-Database
  }
  "restoreDatabase" {
			Write-Info "Performing restore operation..."
			Restore-Database
  }
  "updateDatabase" {
			Write-Info "Performing update operation..."
			Update-Database
  }
  "preUpdateScripts" {
			Write-Info "Performing pre update operation..."
			Run-PreUpdateScripts
  }
  "postUpdateScripts" {
			Write-Info "Performing post update operation..."
			Run-PostUpdateScripts
  }
  "prepareVersionTable" {
			Write-Info "Performing prepare version table operation..."
			Prepare-VersionTable
  }
  "execSql" {
			Write-Info "Performing exec SQL operation..."
			Exec-Sql -File $SqlFile -Command $Sql
  }
  "runTests" {
			Write-Info "Performing run tests operation..."
			Run-Tests -Filter $TestFilter -ShowDetail:$TestVerbose
  }
  "fullService" {
			Write-Info "Performing full service operation for us, lazy boys..."
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

