$ErrorActionPreference = "Stop";
trap { $host.SetShouldExit(1) }

function Unzip {
    param([string]$ZipFile, [string]$OutPath, [Switch]$Keep)

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipFile, $OutPath)

    if (!$Keep) {
        Write-Host "Unzip: removing zipfile ${ZipFile}"
        Remove-Item -Path $ZipFile -Force
    }
}

$path = "C:\Program Files\WindowsPowerShell\Modules"
Remove-Item -Path (Join-Path $path "BOSH.*") -Force -Recurse

while (!(Test-Path "C:\provision\bosh-psmodules.zip")) { Start-Sleep 5 }
Unzip -ZipFile "C:\provision\bosh-psmodules.zip" -OutPath $path -Keep $false
Import-Module BOSH.Utils