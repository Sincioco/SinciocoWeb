# Regression: the original three-column table produced separate name-only cards.
# Added 2026-10-05. Retire after 10 consecutive relevant successful test runs.
# Exercises real snapshot conversion and checks each rendered card independently.
#requires -Version 7.0
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'Format-SinStarReadme.ps1')
. (Join-Path $PSScriptRoot 'Convert-ProjectReadme.ps1')
$source = Get-Content -LiteralPath (Join-Path $projectRoot 'content/sinstar/source.json') -Raw | ConvertFrom-Json
$markdown = Get-Content -LiteralPath (Join-Path $projectRoot 'content/sinstar/README.md') -Raw
$document = Convert-ProjectReadme $source (Format-SinStarReadme $markdown) $projectRoot
$section = [regex]::Match($document.Html, '(?is)<h2 id="towns">Towns</h2>(.*?)(?=<h2\b|\z)')
if (!$section.Success) { throw 'Expected a Towns heading with the towns anchor.' }
$townLinks = @($document.Sections | Where-Object { $_.id -eq 'towns' -and $_.label -eq 'Towns' })
if ($townLinks.Count -ne 1) { throw 'Expected one Towns entry for the left navigation.' }
$expectedTowns = @(
    'Neris Metropolis', 'Neris Town', 'Neris Spaceport', 'Horizon Airport', 'Neris Canals',
    'Neris Star Lake', 'Neris Crown Isles', 'East Valley', "Orin's Village", 'Neris Waterworks',
    'Verdant Reach', 'Greyglass Pass', 'Sunglass Expanse', 'Ancient Relay', 'Neris Relief Quarter',
    'Willowstep Highlands', 'Silverfall Basin'
)
$figures = [regex]::Matches($section.Groups[1].Value, '(?is)<figure\b[^>]*>(.*?)</figure>')
if ($figures.Count -ne $expectedTowns.Count) { throw "Expected exactly 17 town cards; found $($figures.Count)." }
for ($index = 0; $index -lt $expectedTowns.Count; $index++) {
    $town = $expectedTowns[$index]
    $card = $figures[$index].Groups[1].Value
    $labels = [regex]::Matches($card, '(?is)<strong>(.*?)</strong>')
    $images = [regex]::Matches($card, '(?is)<img\b[^>]*\bsrc="([^"]+)"[^>]*>')
    if ($labels.Count -ne 1 -or [Net.WebUtility]::HtmlDecode($labels[0].Groups[1].Value) -cne $town -or $images.Count -ne 1) {
        throw "Town card $($index + 1) must contain both the name '$town' and exactly one image."
    }
    $view = if ($town -eq 'Neris Metropolis') { 'night' } else { 'day' }
    $original = 'docs/images/towns/' + [Uri]::EscapeDataString($town) + '-' + $view + '.png'
    $expectedImage = @($source.images | Where-Object source -CEQ $original)
    if ($expectedImage.Count -ne 1 -or [Net.WebUtility]::HtmlDecode($images[0].Groups[1].Value) -cne $expectedImage[0].localPath) {
        throw "Town card '$town' must use its $view image."
    }
}
if ([regex]::Matches($section.Groups[1].Value, '(?i)<img\b').Count -ne 17) { throw 'The Towns section must contain only its 17 selected images.' }
if ($document.Html -match 'Towns, day and night') { throw 'The old town heading must not remain in the displayed content.' }
Write-Output 'PASS: Towns heading/navigation; 17 cards with names and images together; Neris Metropolis night, other 16 day.'
