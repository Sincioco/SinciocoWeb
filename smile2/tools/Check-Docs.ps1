# Verify the delivered HTML and local navigation without third-party dependencies.
[CmdletBinding()]
param([string]$PreviewUrl = '')
$ErrorActionPreference = 'Stop'
$site = Split-Path $PSScriptRoot -Parent
$root = Split-Path $site -Parent
$failures = [System.Collections.Generic.List[string]]::new()
$files = @(Get-ChildItem -LiteralPath $site -Filter '*.html')
if ($files.Count -ne 11) { $failures.Add("Expected 11 documentation pages; found $($files.Count).") }
$files += Get-Item (Join-Path $root 'Index.html'),(Join-Path $root 'Resume\Index.html'),(Join-Path $root 'Military\Index.html')
$links = 0
$images = 0
foreach ($file in $files) {
    $html = Get-Content -LiteralPath $file.FullName -Raw
    $ids = [regex]::Matches($html,'\bid="([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
    foreach ($duplicate in ($ids | Group-Object | Where-Object Count -gt 1)) { $failures.Add("$($file.Name): duplicate id $($duplicate.Name)") }
    if ([regex]::Matches($html,'<h1\b').Count -ne 1) { $failures.Add("$($file.Name): expected one h1.") }
    $primaryNav = [regex]::Matches($html, '(?is)<nav\b[^>]*\bclass="primary-nav"[^>]*>(.*?)</nav>')
    $navContent = ($primaryNav | ForEach-Object { $_.Groups[1].Value }) -join ''
    if ($primaryNav.Count -ne 1 -or $navContent -notmatch 'Military\s*</a>\s*<span\b[^>]*\bclass="nav-separator"[^>]*>\s*</span>\s*<a\b[^>]*>\s*Agentic AI Projects\s*</a>') { $failures.Add("$($file.Name): Military, separator and Agentic AI Projects navigation sequence missing.") }
    foreach ($anchor in [regex]::Matches($navContent, '(?is)<a\b[^>]*>(.*?)</a>')) {
        $label = [Net.WebUtility]::HtmlDecode(([regex]::Replace($anchor.Groups[1].Value, '<[^>]*>', '') -replace '\s+', ' ')).Trim()
        if ($label -eq 'Smile 2.0') { $failures.Add("$($file.Name): Smile 2.0 must not appear in the primary navigation.") }
    }
    foreach ($img in [regex]::Matches($html,'<img\b[^>]*>')) {
        $images++
        if ($img.Value -notmatch '\balt="[^"]*"') { $failures.Add("$($file.Name): image missing alt text.") }
    }
    foreach ($link in [regex]::Matches($html,'\b(?:href|src)="([^"]+)"')) {
        $target = [System.Net.WebUtility]::HtmlDecode($link.Groups[1].Value)
        if ($target -match '^(https?:|mailto:|tel:|data:)') { continue }
        $links++
        $parts = $target -split '#',2
        $relative = [uri]::UnescapeDataString(($parts[0] -split '\?',2)[0])
        $path = if ($relative -eq '') { $file.FullName } else { [IO.Path]::GetFullPath((Join-Path $file.DirectoryName $relative)) }
        if (Test-Path -LiteralPath $path -PathType Container) { $path = Join-Path $path 'Index.html' }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $failures.Add("$($file.Name): missing target $target"); continue }
        if ($parts.Count -eq 2 -and $parts[1] -ne '' -and $path -match '\.html$') {
            $fragment = [uri]::UnescapeDataString($parts[1])
            $destination = Get-Content -LiteralPath $path -Raw
            if ($destination -notmatch ('\bid="'+[regex]::Escape($fragment)+'"')) { $failures.Add("$($file.Name): missing anchor $target") }
        }
    }
    if ($PreviewUrl) {
        $relative = [IO.Path]::GetRelativePath($root,$file.FullName).Replace('\','/')
        try {
            $response = Invoke-WebRequest -Uri ($PreviewUrl.TrimEnd('/')+'/'+$relative) -UseBasicParsing
            if ($response.StatusCode -ne 200) { $failures.Add("HTTP $relative returned $($response.StatusCode)") }
        } catch { $failures.Add("HTTP $relative : $($_.Exception.Message)") }
    }
}
if ($failures.Count) { $failures | ForEach-Object { Write-Output "FAIL: $_" }; throw "$($failures.Count) documentation validation failures." }
Write-Output "PASS: $($files.Count) pages; $links local links/assets; $images image references; unique anchors, titles, navigation order and image descriptions."
