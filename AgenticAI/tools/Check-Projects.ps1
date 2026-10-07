#requires -Version 7.0
[CmdletBinding()]
param([string]$PreviewUrl)

$ErrorActionPreference = 'Stop'
$siteRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$projectsRoot = Join-Path $siteRoot 'AgenticAI'
$failures = [Collections.Generic.List[string]]::new()
$expectedPages = @('Index.html', 'sinaiprompt.html', 'pmt.html', 'sinstar.html', 'life2.html', 'smile2.html', 'smile1.html')
$expectedLabels = @('Sin AI Prompt', 'PMT', 'Sin Star I', 'Life 2.0', 'SMILE 2.0', 'SMILE 1.0')

function Get-Attribute([string]$Tag, [string]$Name) {
    $pattern = '(?is)(?:^|\s)' + [regex]::Escape($Name) + '\s*=\s*(?:"(?<v>[^"]*)"|''(?<v>[^'']*)''|(?<v>[^\s"''=<>`]+))'
    $match = [regex]::Match($Tag, $pattern)
    if ($match.Success) { return [Net.WebUtility]::HtmlDecode($match.Groups['v'].Value) }
    return $null
}

function Get-ClassBlocks([string]$Html, [string]$Class) {
    $pattern = '(?is)<(?<tag>[a-z][a-z0-9]*)\b(?<attrs>[^>]*)>'
    foreach ($match in [regex]::Matches($Html, $pattern)) {
        if ((Get-Attribute $match.Groups['attrs'].Value 'class') -split '\s+' -contains $Class) {
            $rest = $Html.Substring($match.Index + $match.Length)
            [regex]::Match($rest, '(?is)^(.*?)</' + $match.Groups['tag'].Value + '\s*>').Groups[1].Value
        }
    }
}

function Get-Ids([string]$Html) {
    foreach ($tag in [regex]::Matches($Html, '(?s)<[a-zA-Z][^>]*>')) {
        $id = Get-Attribute $tag.Value 'id'
        if ($null -ne $id) { $id }
    }
}

function Resolve-LocalTarget([string]$Page, [string]$Value) {
    $pathPart = [Uri]::UnescapeDataString((($Value -split '#', 2)[0] -replace '\?.*$', ''))
    $target = if (!$pathPart) { $Page } elseif ($pathPart.StartsWith('/')) {
        Join-Path $siteRoot $pathPart.TrimStart('/')
    } else { Join-Path ([IO.Path]::GetDirectoryName($Page)) $pathPart }
    $target = [IO.Path]::GetFullPath($target)
    if (Test-Path -LiteralPath $target -PathType Container) { $target = Join-Path $target 'Index.html' }
    return $target
}

$pages = @(foreach ($folder in @('', 'Resume', 'Military', 'smile2', 'AgenticAI')) {
    Get-ChildItem -LiteralPath (Join-Path $siteRoot $folder) -Filter '*.html' -File
})
$projectPages = @($pages | Where-Object DirectoryName -EQ $projectsRoot)
foreach ($name in $expectedPages) {
    if ($projectPages.Name -notcontains $name) { $failures.Add("AgenticAI/$name is missing.") }
}
if ($projectPages.Count -ne 7) { $failures.Add("Expected seven immediate AgenticAI HTML pages; found $($projectPages.Count).") }
$htmlCache = @{}
foreach ($page in $pages) { $htmlCache[$page.FullName] = [regex]::Replace([IO.File]::ReadAllText($page.FullName), '(?s)<!--.*?-->', '') }

foreach ($page in $pages) {
    $relative = [IO.Path]::GetRelativePath($siteRoot, $page.FullName)
    $html = $htmlCache[$page.FullName]
    $isProject = $page.DirectoryName -eq $projectsRoot
    foreach ($duplicate in @(Get-Ids $html | Group-Object -CaseSensitive | Where-Object Count -GT 1)) {
        $failures.Add("${relative}: duplicate id '$($duplicate.Name)'.")
    }
    $mainNav = @(Get-ClassBlocks $html 'primary-nav')
    $labels = @(foreach ($anchor in [regex]::Matches(($mainNav -join ''), '(?is)<a\b[^>]*>(.*?)</a>')) {
        [Net.WebUtility]::HtmlDecode(([regex]::Replace($anchor.Groups[1].Value, '<[^>]*>', '') -replace '\s+', ' ')).Trim()
    })
    if ($mainNav.Count -ne 1 -or ($mainNav -join '') -notmatch 'Military\s*</a>\s*<span\b[^>]*\bclass="nav-separator"[^>]*>\s*</span>\s*<a\b[^>]*>\s*Agentic AI Projects\s*</a>') {
        $failures.Add("${relative}: main navigation must place the separator directly between Military and Agentic AI Projects.")
    }
    if ($labels -contains 'Smile 2.0') { $failures.Add("${relative}: Smile 2.0 must not appear in the primary navigation.") }
    foreach ($tag in [regex]::Matches($html, '(?s)<[a-zA-Z][^>]*>')) {
        $isImage = $tag.Value -match '^<img\b'
        if ($isImage -and $null -eq (Get-Attribute $tag.Value 'alt')) { $failures.Add("${relative}: image lacks alt text: $($tag.Value)") }
        # Existing Military lightbox assigns its placeholder source at runtime; new project images require static sources.
        if ($isProject -and $isImage -and [string]::IsNullOrWhiteSpace((Get-Attribute $tag.Value 'src'))) { $failures.Add("${relative}: image lacks a source.") }
        foreach ($attribute in @('href', 'src')) {
            $value = Get-Attribute $tag.Value $attribute
            if ([string]::IsNullOrWhiteSpace($value)) { continue }
            $remote = $value -match '^(?:[a-z][a-z0-9+.-]*:|//)'
            if ($isImage -and $attribute -eq 'src' -and $remote) { $failures.Add("${relative}: image must use a local file: $value") }
            if ($remote) { continue }
            $target = Resolve-LocalTarget $page.FullName $value
            if (!$target.StartsWith($siteRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { $failures.Add("${relative}: link escapes the site: $value"); continue }
            if (!(Test-Path -LiteralPath $target -PathType Leaf)) { $failures.Add("${relative}: missing local $attribute '$value'."); continue }
            if ($isProject -and $isImage -and $attribute -eq 'src' -and !$target.StartsWith((Join-Path $projectsRoot 'images') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
                $failures.Add("${relative}: project image must be stored in AgenticAI/images: $value")
            }
            if ($value.Contains('#') -and [IO.Path]::GetExtension($target) -eq '.html') {
                $fragment = [Uri]::UnescapeDataString(($value -split '#', 2)[1])
                if (!$htmlCache.ContainsKey($target)) { $htmlCache[$target] = [IO.File]::ReadAllText($target) }
                if ($fragment -and @(Get-Ids $htmlCache[$target]) -cnotcontains $fragment) { $failures.Add("${relative}: missing fragment in '$value'.") }
            }
        }
    }
    if (!$isProject) { continue }
    if ([regex]::Matches($html, '(?i)<h1\b').Count -ne 1) { $failures.Add("${relative}: expected exactly one h1.") }
    $tabs = @(Get-ClassBlocks $html 'project-tabs')
    $tabLinks = @([regex]::Matches(($tabs -join ''), '(?is)<a\b(?<attrs>[^>]*)>(?<label>.*?)</a>'))
    if ($tabs.Count -ne 1 -or $tabLinks.Count -ne 6) { $failures.Add("${relative}: expected one project-tabs navigation with six links.") }
    for ($index = 0; $index -lt [Math]::Min(6, $tabLinks.Count); $index++) {
        $label = [Net.WebUtility]::HtmlDecode(([regex]::Replace($tabLinks[$index].Groups['label'].Value, '<[^>]*>', '') -replace '\s+', ' ')).Trim()
        $href = Get-Attribute $tabLinks[$index].Groups['attrs'].Value 'href'
        if ($label -cne $expectedLabels[$index] -or !$href -or (Resolve-LocalTarget $page.FullName $href) -ne (Join-Path $projectsRoot $expectedPages[$index + 1])) {
            $failures.Add("${relative}: project tab $($index + 1) must link to $($expectedPages[$index + 1]) and read '$($expectedLabels[$index])'.")
        }
    }
    $sidebars = @(Get-ClassBlocks $html 'section-nav')
    if ($page.Name -eq 'Index.html') {
        if ($sidebars.Count) { $failures.Add("${relative}: the landing page must not have a section sidebar.") }
        continue
    }
    $sectionLinks = @([regex]::Matches(($sidebars -join ''), '(?is)<a\b[^>]*>'))
    if ($sidebars.Count -ne 1 -or !$sectionLinks.Count) { $failures.Add("${relative}: expected a section-nav sidebar with heading links.") }
    $headingIds = @(foreach ($heading in [regex]::Matches($html, '(?is)<h[1-6]\b[^>]*>')) { Get-Attribute $heading.Value 'id' })
    foreach ($link in $sectionLinks) {
        $href = Get-Attribute $link.Value 'href'
        if (!$href -or !$href.StartsWith('#') -or $headingIds -cnotcontains [Uri]::UnescapeDataString($href.Substring(1))) { $failures.Add("${relative}: sidebar link must target a heading in this page: '$href'.") }
    }
}

foreach ($file in Get-ChildItem -LiteralPath $projectsRoot -Recurse -File | Where-Object { $_.Extension -in '.ps1', '.css', '.js' -and $_.FullName -notlike "$projectsRoot\content\*" }) {
    $lineCount = [IO.File]::ReadAllLines($file.FullName).Count
    $name = [IO.Path]::GetRelativePath($siteRoot, $file.FullName)
    Write-Host "$name : $lineCount physical lines"
    if ($lineCount -gt 800) { $failures.Add("${name}: exceeds the 800-line code review limit ($lineCount).") }
    elseif ($lineCount -gt 500) { Write-Warning "$name exceeds the 500-line review trigger ($lineCount)." }
}
if ($PreviewUrl) {
    $previewBase = [Uri]($PreviewUrl.TrimEnd('/') + '/')
    foreach ($page in $pages) {
        $url = [Uri]::new($previewBase, [IO.Path]::GetRelativePath($siteRoot, $page.FullName).Replace('\', '/'))
        try { $response = Invoke-WebRequest -Uri $url -TimeoutSec 15; if ($response.StatusCode -ne 200) { $failures.Add("HTTP $($response.StatusCode): $url") } }
        catch { $failures.Add("Preview request failed for ${url}: $($_.Exception.Message)") }
    }
}
if ($failures.Count) { throw ("Project validation failed ($($failures.Count)):`n - " + ($failures -join "`n - ")) }
Write-Host "PASS: $($pages.Count) site pages; seven project pages, navigation, local links/fragments and images. Physical line counts are review signals, not semantic architecture checks."
