# Regression: repeated builds must not append blank lines to the shared sitemap.
# Added 2026-10-05. Retire after 10 consecutive relevant successful test runs.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$siteRoot = Split-Path $projectRoot -Parent
$projectBuild = Join-Path $PSScriptRoot 'Build-Projects.ps1'
$docsBuild = Join-Path $siteRoot 'smile2/tools/Build-Docs.ps1'
foreach ($builder in @($docsBuild, $projectBuild)) {
    & $builder
    $before = Get-FileHash -LiteralPath (Join-Path $siteRoot 'sitemap.xml')
    & $builder
    $after = Get-FileHash -LiteralPath (Join-Path $siteRoot 'sitemap.xml')
    if ($before.Hash -ne $after.Hash) { throw "Repeated build changed the sitemap: $builder" }
    [xml]$sitemap = Get-Content -LiteralPath (Join-Path $siteRoot 'sitemap.xml') -Raw
    $urls = @($sitemap.urlset.url.loc)
    if ($urls.Count -ne 21 -or @($urls | Select-Object -Unique).Count -ne 21) {
        throw 'Expected exactly 21 unique sitemap entries after rebuilding either sub-site.'
    }
}
Write-Output 'PASS: repeated builds are stable; both sub-sites preserve all 21 sitemap entries.'
