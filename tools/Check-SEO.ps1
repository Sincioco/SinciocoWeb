#requires -Version 7.0
<#
Checks the published sitemap routes and their static search metadata.
Optional -PreviewUrl repeats the HTML checks over HTTP and checks response robots headers.
This is a structural check; title/description quality still needs editorial review.
#>
[CmdletBinding()]
param([string]$PreviewUrl)

$ErrorActionPreference = 'Stop'
$siteRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$siteOrigin = 'https://sincioco.com'
$failures = [Collections.Generic.List[string]]::new()
$records = [Collections.Generic.List[object]]::new()
$pageTypes = @('WebPage', 'ProfilePage', 'CollectionPage', 'TechArticle', 'Article', 'AboutPage')
$urlFields = @('@id', 'url', 'image', 'logo', 'sameAs', 'contentUrl', 'embedUrl', 'thumbnailUrl',
    'license', 'codeRepository', 'downloadUrl', 'installUrl', 'mainEntityOfPage', 'isPartOf', 'item')

function Get-Attribute([string]$Tag, [string]$Name) {
    $pattern = '(?is)(?:^|\s)' + [regex]::Escape($Name) + '\s*=\s*(?:"(?<v>[^"]*)"|''(?<v>[^'']*)''|(?<v>[^\s"''=<>`]+))'
    $match = [regex]::Match($Tag, $pattern)
    if ($match.Success) { return [Net.WebUtility]::HtmlDecode($match.Groups['v'].Value) }
    return $null
}

function Normalize-Text([string]$Text) {
    return ([Net.WebUtility]::HtmlDecode($Text) -replace '\s+', ' ').Trim()
}

function Test-WebUrl([string]$Value, [bool]$HttpsOnly = $false) {
    $parsed = $null
    if (![Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$parsed) -or
        $parsed.Scheme -notin 'http', 'https' -or !$parsed.Host -or $parsed.UserInfo) { return $false }
    if ($HttpsOnly) { return $parsed.Scheme -eq 'https' }
    if ($parsed.Host -in 'sincioco.com', 'www.sincioco.com') {
        return $parsed.GetLeftPart([UriPartial]::Authority) -ceq $siteOrigin
    }
    return $true
}

function Test-MetadataText([string]$Value, [string]$Field, [string]$Label) {
    if (!$Value -or $Value -notmatch '[\p{L}\p{N}]') {
        $failures.Add("${Label}: $Field is empty or has no readable text.")
    } elseif ($Value -match '^(?:home|index|untitled|page|title|description|todo|tbd|placeholder|lorem ipsum)[.!…]*$') {
        $failures.Add("${Label}: $Field is an obvious placeholder ('$Value').")
    }
}

function Get-SchemaTypes($Node, [string]$Label, [string]$Path = '$', [bool]$UrlValue = $false) {
    if ($Node -is [Collections.IDictionary]) {
        foreach ($key in $Node.Keys) {
            $value = $Node[$key]
            if ($key -eq '@type') {
                foreach ($type in @($value)) { ([string]$type -replace '^https://schema\.org/', '') }
            }
            Get-SchemaTypes $value $Label ($Path + '.' + $key) ($urlFields -contains $key)
        }
    } elseif ($Node -is [Collections.IList]) {
        for ($index = 0; $index -lt $Node.Count; $index++) {
            Get-SchemaTypes $Node[$index] $Label ($Path + '[' + $index + ']') $UrlValue
        }
    } elseif ($UrlValue -and $Node -is [string] -and !(Test-WebUrl $Node)) {
        $failures.Add("${Label}: JSON-LD $Path must be an absolute HTTP/HTTPS URL, using $siteOrigin for this site ('$Node').")
    }
}

function Test-Html([string]$Html, [string]$Canonical, [string]$Label, [string]$Scope) {
    $clean = [regex]::Replace($Html, '(?s)<!--.*?-->', '')
    $heads = [regex]::Matches($clean, '(?is)<head\b[^>]*>(.*?)</head\s*>')
    if ($heads.Count -ne 1) { $failures.Add("${Label}: expected one head element.") }
    $head = if ($heads.Count) { $heads[0].Groups[1].Value } else { '' }
    $titles = [regex]::Matches($head, '(?is)<title\b[^>]*>(.*?)</title\s*>')
    if ($titles.Count -ne 1) { $failures.Add("${Label}: expected one title; found $($titles.Count).") }
    $title = if ($titles.Count) { Normalize-Text $titles[0].Groups[1].Value } else { '' }
    Test-MetadataText $title 'title' $Label
    $descriptions = @()
    foreach ($meta in [regex]::Matches($head, '(?is)<meta\b[^>]*>')) {
        $name = Get-Attribute $meta.Value 'name'
        $content = Get-Attribute $meta.Value 'content'
        if ($name -eq 'description') { $descriptions += Normalize-Text $content }
        if ($name -match '^(?:robots|googlebot(?:-news)?|bingbot)$' -and $content -match '(?i)\b(?:noindex|none)\b') {
            $failures.Add("${Label}: $name meta blocks indexing ('$content').")
        }
        $property = Get-Attribute $meta.Value 'property'
        if ($property -eq 'og:url' -and $content -cne $Canonical) {
            $failures.Add("${Label}: og:url differs from sitemap URL ('$content').")
        }
        if (($property -in 'og:image', 'og:image:secure_url' -or $name -eq 'twitter:image') -and !(Test-WebUrl $content)) {
            $failures.Add("${Label}: image metadata must be an absolute HTTP/HTTPS URL, using $siteOrigin for this site ('$content').")
        }
    }
    if ($descriptions.Count -ne 1) { $failures.Add("${Label}: expected one meta description; found $($descriptions.Count).") }
    $description = if ($descriptions.Count) { $descriptions[0] } else { '' }
    Test-MetadataText $description 'description' $Label
    $canonicals = @(foreach ($link in [regex]::Matches($head, '(?is)<link\b[^>]*>')) {
        if ((Get-Attribute $link.Value 'rel') -split '\s+' -contains 'canonical') { Get-Attribute $link.Value 'href' }
    })
    if ($canonicals.Count -ne 1 -or $canonicals[0] -cne $Canonical) {
        $failures.Add("${Label}: expected one canonical equal to '$Canonical'; found '$($canonicals -join ', ')'.")
    }

    $schemaCount = 0
    $types = @()
    foreach ($script in [regex]::Matches($clean, '(?is)<script\b(?<attrs>[^>]*)>(?<body>.*?)</script\s*>')) {
        if ((Get-Attribute $script.Groups['attrs'].Value 'type') -ne 'application/ld+json') { continue }
        $schemaCount++
        $json = $script.Groups['body'].Value
        try {
            # JsonDocument rejects JavaScript comments and trailing commas, which JSON-LD cannot contain.
            $document = [System.Text.Json.JsonDocument]::Parse($json)
            $document.Dispose()
            $schema = ConvertFrom-Json -InputObject $json -AsHashtable -NoEnumerate -Depth 100
            $roots = if ($schema -is [Collections.IList]) { $schema } else { ,$schema }
            if (!$roots.Count) { $failures.Add("${Label}: JSON-LD block $schemaCount is empty.") }
            foreach ($node in $roots) {
                if ($node -isnot [Collections.IDictionary] -or !$node.Contains('@context') -or !$node['@context']) {
                    $failures.Add("${Label}: each JSON-LD root must be an object with @context.")
                } elseif ($node['@context'] -is [string] -and !(Test-WebUrl $node['@context'] $true)) {
                    $failures.Add("${Label}: JSON-LD @context must use an absolute HTTPS URL.")
                }
            }
            $types += @(Get-SchemaTypes $schema $Label)
        } catch { $failures.Add("${Label}: invalid JSON-LD block ${schemaCount}: $($_.Exception.Message)") }
    }
    if (!$schemaCount) { $failures.Add("${Label}: JSON-LD is missing.") }
    elseif (!@($types | Where-Object { $pageTypes -contains $_ }).Count) {
        $failures.Add("${Label}: JSON-LD has no page/article type (found '$($types -join ', ')').")
    }
    $records.Add([pscustomobject]@{ Scope = $Scope; Page = $Label; Title = $title; Description = $description })
}

[xml]$sitemap = [IO.File]::ReadAllText((Join-Path $siteRoot 'sitemap.xml'))
$locations = @($sitemap.SelectNodes('/*[local-name()="urlset"]/*[local-name()="url"]/*[local-name()="loc"]') | ForEach-Object { $_.InnerText.Trim() })
if (!$locations.Count) { $failures.Add('sitemap.xml has no page URLs.') }
foreach ($duplicate in @($locations | Group-Object -CaseSensitive | Where-Object Count -GT 1)) {
    $failures.Add("sitemap.xml repeats '$($duplicate.Name)'.")
}
$mappedFiles = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$previewBase = if ($PreviewUrl) { [Uri]($PreviewUrl.TrimEnd('/') + '/') } else { $null }
if ($previewBase -and (!$previewBase.IsAbsoluteUri -or $previewBase.Scheme -notin 'http', 'https')) {
    throw '-PreviewUrl must be an absolute HTTP or HTTPS address.'
}
foreach ($location in $locations) {
    if (!(Test-WebUrl $location)) { $failures.Add("sitemap.xml must use absolute $siteOrigin URLs ('$location')."); continue }
    $uri = [Uri]$location
    if ($uri.GetLeftPart([UriPartial]::Authority) -cne $siteOrigin -or $uri.Query -or $uri.Fragment) {
        $failures.Add("sitemap.xml must use clean $siteOrigin page URLs ('$location')."); continue
    }
    $relative = [Uri]::UnescapeDataString($uri.AbsolutePath).TrimStart('/')
    $path = [IO.Path]::GetFullPath((Join-Path $siteRoot $relative))
    if ($uri.AbsolutePath.EndsWith('/')) { $path = Join-Path $path 'Index.html' }
    if (!$path.StartsWith($siteRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        $failures.Add("sitemap.xml path escapes the website ('$location')."); continue
    }
    if (!(Test-Path -LiteralPath $path -PathType Leaf) -or [IO.Path]::GetExtension($path) -ne '.html') {
        $failures.Add("sitemap.xml has no corresponding HTML file ('$location')."); continue
    }
    if (!$mappedFiles.Add($path)) { $failures.Add("Multiple sitemap URLs map to '$path'.") }
    $label = [IO.Path]::GetRelativePath($siteRoot, $path).Replace('\', '/')
    Test-Html ([IO.File]::ReadAllText($path)) $location $label 'local'
    if ($previewBase) {
        $previewUri = [Uri]::new($previewBase, $uri.AbsolutePath.TrimStart('/'))
        try {
            $response = Invoke-WebRequest -Uri $previewUri -TimeoutSec 15
            if ($response.StatusCode -ne 200) { $failures.Add("Preview HTTP $($response.StatusCode): $previewUri") }
            if ($response.Headers['X-Robots-Tag'] -match '(?i)\b(?:noindex|none)\b') { $failures.Add("Preview blocks indexing through X-Robots-Tag: $previewUri") }
            Test-Html $response.Content $location ("Preview " + $label) 'preview'
        } catch { $failures.Add("Preview request failed for ${previewUri}: $($_.Exception.Message)") }
    }
}

# Compare only the published page directories; source snapshots and tooling are not public routes.
foreach ($folder in @('', 'Resume', 'Military', 'smile2', 'AgenticAI')) {
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $siteRoot $folder) -Filter '*.html' -File) {
        if (!$mappedFiles.Contains($file.FullName)) {
            $failures.Add("Published page is absent from sitemap.xml: $([IO.Path]::GetRelativePath($siteRoot, $file.FullName))")
        }
    }
}
foreach ($scope in @('local', 'preview')) {
    foreach ($field in @('Title', 'Description')) {
        $present = @($records | Where-Object { $_.Scope -eq $scope -and $_.$field })
        foreach ($duplicate in @($present | Group-Object { $_.$field.ToLowerInvariant() } | Where-Object Count -GT 1)) {
            $failures.Add("Duplicate ${field}: $($duplicate.Group.Page -join ', ')")
        }
    }
}

if ($previewBase) {
    # Read the first response: following redirects would hide an accidental 302 or lost query.
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $client = [Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(15)
    try {
        foreach ($redirect in @(
            @{ From = 'Projects/'; To = 'AgenticAI/' },
            @{ From = 'Projects/sinstar.html?source=legacy'; To = 'AgenticAI/sinstar.html?source=legacy' },
            @{ From = 'AgenticAI/Index.html'; To = 'AgenticAI/' }
        )) {
            $from = [Uri]::new($previewBase, $redirect.From)
            $expected = [Uri]::new($previewBase, $redirect.To)
            try {
                $response = $client.GetAsync($from).GetAwaiter().GetResult()
                try {
                    $destination = if ($response.Headers.Location) { [Uri]::new($from, $response.Headers.Location) } else { $null }
                    if ([int]$response.StatusCode -ne 301 -or !$destination -or $destination.AbsoluteUri -cne $expected.AbsoluteUri) {
                        $failures.Add("Preview redirect '$from' must return 301 to '$expected'; got $([int]$response.StatusCode) to '$destination'.")
                    }
                } finally { $response.Dispose() }
            } catch { $failures.Add("Preview redirect request failed for ${from}: $($_.Exception.Message)") }
        }
    } finally { $client.Dispose() }
}

$robotsPath = Join-Path $siteRoot 'robots.txt'
if (!(Test-Path -LiteralPath $robotsPath -PathType Leaf)) { $failures.Add('robots.txt is missing.') }
else {
    $robots = [IO.File]::ReadAllText($robotsPath)
    $robotSitemaps = @([regex]::Matches($robots, '(?im)^\s*Sitemap:\s*(\S+)') | ForEach-Object { $_.Groups[1].Value })
    if ($robotSitemaps -cnotcontains ($siteOrigin + '/sitemap.xml')) { $failures.Add("robots.txt must declare $siteOrigin/sitemap.xml.") }
    if ($robotSitemaps -ccontains 'https://sinstar.sincioco.com/sitemap-sinstar.xml') { $failures.Add('robots.txt still declares the retired Azure reader sitemap.') }
    $activeAgents = @()
    $hasRules = $false
    $allowsAll = $false
    foreach ($line in ($robots -split '\r?\n')) {
        $line = ($line -split '#', 2)[0].Trim()
        if ($line -match '^User-agent:\s*(.+)$') {
            if ($hasRules) { $activeAgents = @(); $hasRules = $false }
            $activeAgents += $Matches[1].Trim()
        } elseif ($line -match '^(Allow|Disallow):\s*(.*)$') {
            $hasRules = $true
            $directive = $Matches[1]
            $rule = $Matches[2].Trim()
            if ($activeAgents -contains '*' -and $directive -eq 'Allow' -and $rule -eq '/') { $allowsAll = $true }
            if ($directive -eq 'Disallow' -and $rule -and @($activeAgents | Where-Object { $_ -match '^(?:\*|Googlebot|Bingbot)$' }).Count) {
                $pattern = '^' + ([regex]::Escape($rule) -replace '\\\*', '.*' -replace '\\\$$', '$')
                foreach ($location in $locations) {
                    if (([Uri]$location).AbsolutePath -match $pattern) { $failures.Add("robots.txt disallows a published route for $($activeAgents -join ', '): $location") }
                }
            }
        }
    }
    if (!$allowsAll) { $failures.Add('robots.txt must include User-agent: * with Allow: /.') }
}

if ($failures.Count) {
    $failures | ForEach-Object { Write-Output "FAIL: $_" }
    throw "$($failures.Count) SEO validation failures across $($locations.Count) sitemap routes."
}
Write-Output "PASS: $($locations.Count) published sitemap routes; unique readable titles/descriptions, matching canonicals, indexability, JSON-LD and robots.txt."
if ($previewBase) { Write-Output "PASS: $($locations.Count) preview routes returned HTTP 200 with valid metadata, indexable response headers, and three permanent legacy/canonical redirects preserving the query." }
Write-Output 'Metadata length is not capped. Editorial relevance and search-engine indexing are not asserted by this structural check.'
