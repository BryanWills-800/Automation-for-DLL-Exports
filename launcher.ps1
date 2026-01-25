<#
.SYNOPSIS
Optimized launcher for DLL export and scanner execution with Python fallback.

.DESCRIPTION
- Compiles a C DLL exporter (mandatory).
- Compiles a scanner C program to inspect functions from C or DLL.
- If scanner compilation fails or GCC is unavailable, falls back to Python.
- Logs all steps to a log file and safely writes JSON.
#>

param(
    [switch]$VerboseMode,
    [ValidateSet("C","DLL")]
    [string]$ScanType = "C",     # Default scan type
    [int]$SchemaVersion = 1      # JSON schema version
)

# ---------------------------
# Setup
# ---------------------------

$MainRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Logger
$Logger = Join-Path $MainRoot "log.txt"
"Launcher started at $(Get-Date)" | Out-File $Logger

# Paths
$ExporterSource = Join-Path $MainRoot "exporter.c"
$DLLFile       = Join-Path $MainRoot "my_library.dll"
$ScannerSource = Join-Path $MainRoot "scanner.c"
$ScannerExe    = Join-Path $MainRoot "scanner.exe"
$PythonRunner  = Join-Path $MainRoot "scanner.py"
$VenvPython    = Join-Path $MainRoot ".venv\Scripts\python.exe"
$ExportsFile   = Join-Path $MainRoot "exports.json"

# Ensure JSON exists
if (-not (Test-Path $ExportsFile) -or (Get-Content $ExportsFile -Raw).Trim() -eq '') {
    '{}' | Out-File -Encoding utf8 $ExportsFile
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
    Write-Error "GCC not found. Cannot compile DLL. Halting script."
    exit 1
}

# ---------------------------
# Compile DLL exporter
# ---------------------------
Write-Host "Compiling DLL exporter..."
"Compiling DLL exporter..." | Out-File $Logger -Append

gcc "`"$ExporterSource`"" -shared -o "`"$DLLFile`""
if ($LASTEXITCODE -ne 0) {
    Write-Error "DLL compilation failed. Halting script."
    exit 1
}

"Exported DLL: $DLLFile" | Out-File $Logger -Append
Write-Host "DLL compiled successfully."

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
        Write-Host "Scanner executable up-to-date. Skipping compilation."
        "Scanner executable up-to-date. Skipping compilation." | Out-File $Logger -Append
    }
}

if ($compileScanner) {
    Write-Host "Compiling scanner..."
    "Compiling scanner..." | Out-File $Logger -Append

    gcc "`"$ScannerSource`"" -o "`"$ScannerExe`""
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Scanner compilation failed. Falling back to Python."
        "Scanner compilation failed. Falling back to Python." | Out-File $Logger -Append
        $fallback = $true
    }
}

# ---------------------------
# Run scanner
# ---------------------------
if (-not $fallback) {
    Write-Host "Running scanner executable..."
    "Running scanner executable..." | Out-File $Logger -Append

    # Pass schema version as argument
    & $ScannerExe $SafeScanFile $ExportsFile $SchemaVersion 2>&1 | Tee-Object -FilePath $Logger -Append
}
else {
    Write-Host "Running Python fallback..."
    "Running Python fallback..." | Out-File $Logger -Append

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
# Read JSON safely
# ---------------------------
try {
    $data = Get-Content $ExportsFile -Raw | ConvertFrom-Json
} catch {
    Write-Warning "Failed to parse $ExportsFile. Using empty object."
    $data = [PSCustomObject]@{ dll = ""; exported_functions = @() }
}

Write-Host "DLL scanned: $($data.dll)"
Write-Host "Functions exported:"
$data.exported_functions | ForEach-Object { Write-Host "  $_" }

Write-Host "Launcher finished."
"Launcher finished at $(Get-Date)" | Out-File $Logger -Append
