<#
.SYNOPSIS
Optimised launcher for DLL export and scanner execution with Python fallback.

.DESCRIPTION
- Compiles a C DLL exporter (mandatory).
- Compiles a scanner C program to inspect functions from C or a DLL.
- If scanner compilation fails or GCC is unavailable, falls back to Python.
- Logs all steps to a log file and safely writes JSON.
#>

param(
    [switch]$VerboseMode,
    [ValidateSet("C", "DLL")]
    [string]$ScanType = "C",     # Default scan type
    [int]$SchemaVersion = 1      # JSON schema version
)

# ---------------------------
# Setup
# ---------------------------

$MainRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Logging Stuff
$Logger = Join-Path $MainRoot "logger.log"
$Global:Logger = $Logger
[System.IO.File]:: WriteAllText($Global: Logger, "", [System.Text.Encoding]:: UTF8)

function Logger {
    param (
        [String]$Date = ([DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")),
        [String]$LogLevel = "INFO",
        [String]$Message,
        [String]$OutFile = $Global:Logger
    )

    if (-not $Message) { return }

    if (-not $OutFile) {
        Write-Warning "Logger file path not set. Message: $Message"
        return
    }

    $LogTypes = @{
        DEBUG = { param($msg) Write-Host "[DEBUG] $msg" -ForegroundColor Cyan }
        INFO  = { param($msg) Write-Output "[INFO]  $msg" }
        WARN  = { param($msg) Write-Warning "[WARN]  $msg" }
        ERROR = { param($msg) Write-Error "[ERROR] $msg" }
        FATAL = { param($msg) throw [System.Exception]::new($msg) }
    }

    $LogLevel = $LogLevel.ToUpper()
    if (-not $LogTypes.ContainsKey($LogLevel)) {
        Write-Warning "Unknown log level '$LogLevel', defaulting to INFO"
        $LogLevel = "INFO"
    }

    & $LogTypes[$LogLevel] $Message

    if ($LogLevel -ne "DEBUG") {
        "$Date $LogLevel $Message" | Out-File -FilePath $OutFile -Append -Encoding UTF8
    }
}

Logger -Message "Launcher has been activated!" -LogLevel "INFO"

# Version Check
$SchemaVersion = python read_config.py schema_version
if ($LASTEXITCODE -eq 0) {
    Logger -Message "Schema Version of scanner is $SchemaVersion" -LogLevel "debug"
} 
else {
    Logger -Message "Schema Version of Scanner was not found!!!" -LogLevel "warn"
    Logger -Message "Launcher finished." -LogLevel "info"
    $SchemaVersion = 1
}

# Paths
$ExporterSource = Join-Path $MainRoot "exporter.c"
$DLLFile        = Join-Path $MainRoot "my_library.dll"
$ScannerSource  = Join-Path $MainRoot "scanner.c"
$ScannerExe     = Join-Path $MainRoot "scanner.exe"
$PythonRunner   = Join-Path $MainRoot "scanner.py"
$VenvPython     = Join-Path $MainRoot ".venv\Scripts\python.exe"
$ExportsFile    = Join-Path $MainRoot "exports.json"

# Ensure JSON exists
if (-not (Test-Path $ExportsFile) -or (Get-Content $ExportsFile -Raw).Trim() -eq '') {
    '{}' | Out-File -Encoding utf8 $ExportsFile
    Logger -Message "Created empty exports JSON file." -LogLevel "DEBUG"
}

# ---------------------------
# Choose file to scan
# ---------------------------
switch ($ScanType) {
    "C"   { $ScanFile = $ExporterSource }
    "DLL" { $ScanFile = $DLLFile }
}

# Make JSON-safe path for Windows backslashes
$SafeScanFile = $ScanFile -replace '\\','/'

# ---------------------------
# Check GCC availability
# ---------------------------
if (-not (Get-Command gcc -ErrorAction SilentlyContinue)) {
    Logger -Message "GCC not found. Cannot compile DLL. Halting script." -LogLevel "fatal"
}

# ---------------------------
# Compile DLL exporter
# ---------------------------
Logger -Message "Compiling DLL exporter..." -LogLevel "info"

gcc "`"$ExporterSource`"" -shared -o "`"$DLLFile`""
if ($LASTEXITCODE -ne 0) {
    Logger -Message "DLL compilation failed. Halting script." -LogLevel "error"
}

Logger -Message "Exported DLL: $DLLFile" -LogLevel "info"

# ---------------------------
# Compile scanner executable
# ---------------------------
$fallback = $false
$compileScanner = $true

if (Test-Path $ScannerExe) {
    $scannerTime = (Get-Item $ScannerExe).LastWriteTime
    $dllTime     = (Get-Item $DLLFile).LastWriteTime
    if ($scannerTime -gt $dllTime) {
        $compileScanner = $false
        Logger -Message "Scanner executable up-to-date. Skipping compilation." -LogLevel "debug"
    }
}

if ($compileScanner) {
    Logger -Message "Compiling scanner..." -LogLevel "debug"

    gcc "`"$ScannerSource`"" -o "`"$ScannerExe`""
    if ($LASTEXITCODE -ne 0) {
        Logger -Message "Scanner compilation failed. Falling back to Python." -LogLevel "info"
        $fallback = $true
    }
}

# ---------------------------
# Run scanner
# ---------------------------
if (-not $fallback) {
    Logger -Message "Running scanner executable..." -LogLevel "debug"

    # Pass schema version as argument
    & $ScannerExe $SafeScanFile $ExportsFile $SchemaVersion 2>&1 | Tee-Object -FilePath $Logger -Append
}
else {
    Logger -Message "Running Python fallback..." -LogLevel "info"

    $PythonArgs = @(
        "--version", $SchemaVersion
        "--source", $SafeScanFile
        "--out", $ExportsFile
    )
    if ($VerboseMode) { $PythonArgs += "--verbose" }

    $PythonInterpreter = if (Test-Path $VenvPython) { $VenvPython } else { "python.exe" }

    & $PythonInterpreter $PythonRunner $PythonArgs 2>&1 | Tee-Object -FilePath $Logger -Append
}

# ---------------------------
# Complete Execution
# ---------------------------

Logger -Message "DLL scanned: $(Split-Path $DLLFile -Leaf)" -LogLevel "INFO"

Write-Host "Press Enter to exit..."

do {
    $key = [Console]::ReadKey($true)
} while ($key.Key -ne "Enter")

Logger "Launcher finished."
