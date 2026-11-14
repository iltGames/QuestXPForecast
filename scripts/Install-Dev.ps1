[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AddOnsPath
)

$ErrorActionPreference = 'Stop'
$source = Split-Path -Parent $PSScriptRoot
$addons = Get-Item -LiteralPath $AddOnsPath
if (!$addons.PSIsContainer -or $addons.Name -ne 'AddOns') {
    throw 'AddOnsPath must point to the game client''s existing Interface/AddOns directory.'
}

$target = Join-Path $addons.FullName 'ForeverQuestXPDev'
if (Test-Path -LiteralPath $target) {
    $directory = Get-Item -LiteralPath $target -Force
    if (!$directory.PSIsContainer -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "The dev destination must be a regular directory: $target"
    }
} else {
    New-Item -ItemType Directory -Path $target | Out-Null
}

$toc = Get-Content -Raw -LiteralPath (Join-Path $source 'ForeverQuestXP.toc')
$toc.Replace('## Title: Quest XP Forecast', '## Title: Quest XP Forecast (Dev)').
    Replace('ForeverQuestXPDB', 'ForeverQuestXPDevDB').
    Replace('ForeverQuestXP.lua', 'ForeverQuestXPDev.lua') |
    Set-Content -NoNewline -Encoding utf8 -LiteralPath (Join-Path $target 'ForeverQuestXPDev.toc')

$lua = Get-Content -Raw -LiteralPath (Join-Path $source 'ForeverQuestXP.lua')
$lua.Replace('local title = "Quest XP Forecast"', 'local title = "Quest XP Forecast (Dev)"').
    Replace('ForeverQuestXPDB', 'ForeverQuestXPDevDB').
    Replace('ForeverQuestXPMinimapButton', 'ForeverQuestXPDevMinimapButton') |
    Set-Content -NoNewline -Encoding utf8 -LiteralPath (Join-Path $target 'ForeverQuestXPDev.lua')

Write-Host "Installed Quest XP Forecast (Dev) in $target"
