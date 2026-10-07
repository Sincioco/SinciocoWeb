# Version local browser assets by content so changed files get new cache keys.
# Run after editing assets and before publishing; both page builders also run it.
#requires -Version 7.0
[CmdletBinding()]
param([string]$SiteRoot = (Join-Path $PSScriptRoot '..'), [switch]$Check)
$ErrorActionPreference = 'Stop'
$sitePath = [IO.Path]::GetFullPath($SiteRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
$hashes = @{}
$changedPages = [Collections.Generic.List[string]]::new()
[xml]$sitemap = Get-Content -LiteralPath (Join-Path $sitePath 'sitemap.xml') -Raw

foreach ($location in $sitemap.urlset.url.loc) {
    $relative = [Uri]::UnescapeDataString(([Uri]$location).AbsolutePath).TrimStart('/')
    if (!$relative -or $relative.EndsWith('/')) { $relative += 'Index.html' }
    elseif ([IO.Path]::GetExtension($relative) -eq '') { $relative += '.html' }
    $pagePath = [IO.Path]::GetFullPath((Join-Path $sitePath $relative))
    if (!$pagePath.StartsWith($sitePath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Page path escapes the website: $relative"
    }
    $original = [IO.File]::ReadAllText($pagePath)
    $updated = [regex]::Replace($original, '(?is)<(?:a|img|script|link|source)\b[^>]*>', {
        param($tag)
        [regex]::Replace($tag.Value, '(?is)(?<prefix>(?<![\w-])(?:href|src)\s*=\s*)(?<quote>["''])(?<url>.*?)\k<quote>', {
            param($attribute)
            $url = [Net.WebUtility]::HtmlDecode($attribute.Groups['url'].Value)
            if (!$url -or $url -match '^(?:[a-z][a-z0-9+.-]*:|//|#)') { return $attribute.Value }
            $fragmentParts = $url -split '#', 2
            $queryParts = $fragmentParts[0] -split '\?', 2
            $assetUrl = $queryParts[0]
            if ($assetUrl -notmatch '(?i)\.(?:css|js|png|jpe?g|gif|webp|svg|ico|avif)$') { return $attribute.Value }
            $decodedPath = [Uri]::UnescapeDataString($assetUrl)
            $assetPath = if ($decodedPath.StartsWith('/')) {
                Join-Path $sitePath $decodedPath.TrimStart('/')
            } else { Join-Path ([IO.Path]::GetDirectoryName($pagePath)) $decodedPath }
            $assetPath = [IO.Path]::GetFullPath($assetPath)
            if (!$assetPath.StartsWith($sitePath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Asset path escapes the website: $url"
            }
            if (!$hashes.ContainsKey($assetPath)) {
                $hashes[$assetPath] = (Get-FileHash -LiteralPath $assetPath -Algorithm SHA256).Hash.Substring(0, 16).ToLowerInvariant()
            }
            $parameters = if ($queryParts.Count -eq 2) { @($queryParts[1] -split '&' | Where-Object { $_ -and $_ -notmatch '^v=' }) } else { @() }
            $parameters = @($parameters) + ('v=' + $hashes[$assetPath])
            $versioned = $assetUrl + '?' + ($parameters -join '&')
            if ($fragmentParts.Count -eq 2) { $versioned += '#' + $fragmentParts[1] }
            $attribute.Groups['prefix'].Value + $attribute.Groups['quote'].Value + [Net.WebUtility]::HtmlEncode($versioned) + $attribute.Groups['quote'].Value
        })
    })
    if ($updated -cne $original) {
        $changedPages.Add($relative)
        if (!$Check) { [IO.File]::WriteAllText($pagePath, $updated, [Text.UTF8Encoding]::new($false)) }
    }
}
if ($Check -and $changedPages.Count) { throw "Asset versions need updating: $($changedPages -join ', '). Run tools/Update-AssetVersions.ps1 before publishing." }
Write-Output "Asset versions: $($hashes.Count) local files checked; $($changedPages.Count) HTML pages $(if ($Check) { 'need updates' } else { 'updated' })."
