# Save this helper with a sample under SMILE-2.0/examples/DocsFire (or DocsWater/DocsEarth).
# It copies existing repository assets. It never downloads character models or other files.
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Fire', 'Water', 'Earth')]
    [string]$Effect
)

$ErrorActionPreference = 'Stop'
$Effect = switch ($Effect) { 'Fire' { 'Fire' } 'Water' { 'Water' } 'Earth' { 'Earth' } }
$smileRepository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$assetSource = Join-Path $smileRepository "TechnicalAssets\Generation3\$Effect"
$assetDestination = Join-Path $PSScriptRoot "Assets\$Effect"
$arenaScript = Join-Path $smileRepository 'scripts\copy-arena-assets.ps1'

if (-not (Test-Path -LiteralPath $arenaScript -PathType Leaf)) {
    throw 'Put this helper and your sample in a folder directly under the SMILE repository examples folder.'
}

$filenames = switch ($Effect) {
    'Fire' { @('fire-shape-atlas.png', 'smoke-shape-atlas.png', 'ember-shape.png') }
    'Water' { @('water-sheet.png', 'water-drop.png') }
    'Earth' { @('earth-dust.png') }
}

foreach ($filename in $filenames) {
    if (-not (Test-Path -LiteralPath (Join-Path $assetSource $filename) -PathType Leaf)) {
        throw "The repository asset is missing: $assetSource\$filename"
    }
}

if ($Effect -eq 'Earth' -and -not (Test-Path -LiteralPath (Join-Path $assetSource 'earth-rocks.glb') -PathType Leaf)) {
    throw 'Earth requires TechnicalAssets\Generation3\Earth\earth-rocks.glb from the source repository.'
}

& $arenaScript -ProjectDirectory $PSScriptRoot
New-Item -ItemType Directory -Path $assetDestination -Force | Out-Null
foreach ($filename in $filenames) {
    Copy-Item -LiteralPath (Join-Path $assetSource $filename) -Destination $assetDestination -Force
}

if ($Effect -eq 'Earth') {
    $modelDestination = Join-Path $PSScriptRoot 'BuildAssets'
    New-Item -ItemType Directory -Path $modelDestination -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $assetSource 'earth-rocks.glb') -Destination $modelDestination -Force
}

Write-Host "$Effect and arena assets are ready. Open the matching .smileproj and build it."
