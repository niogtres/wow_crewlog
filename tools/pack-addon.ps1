# Packs addon folders from addon/ into one zip with each folder at the zip root,
# which is the layout Interface\AddOns expects.
#   powershell -File tools/pack-addon.ps1 Crewlog_Probe
#   powershell -File tools/pack-addon.ps1 Crewlog,Crewlog_Inbox -Out Crewlog-addon
# Entries are written with forward slashes (zip spec); PowerShell 5.1's Compress-Archive uses
# backslashes, which some unzip tools turn into odd file names.
param(
    [Parameter(Mandatory = $true, Position = 0)][string[]]$Names,
    [string]$Out
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$root = Split-Path -Parent $PSScriptRoot
# `powershell -File` passes "A,B" as one string; accept both forms.
$Names = @($Names | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if (-not $Out) { $Out = $Names[0] }

$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
$zipPath = Join-Path $dist "$Out.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($name in $Names) {
        $src = Join-Path $root "addon\$name"
        if (-not (Test-Path (Join-Path $src "$name.toc"))) { throw "No $name.toc in $src" }
        Get-ChildItem -Path $src -Recurse -File | ForEach-Object {
            $rel = $_.FullName.Substring($src.Length).TrimStart('\', '/') -replace '\\', '/'
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, "$name/$rel", [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    }
} finally { $zip.Dispose() }

Write-Output ("Packed {0} ({1:N0} bytes)" -f $zipPath, (Get-Item $zipPath).Length)
