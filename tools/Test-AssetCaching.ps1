# Regression: published asset changes must not require a browser hard refresh.
# Added 2026-10-05. Retire after 10 consecutive relevant successful test runs.
#requires -Version 7.0
[CmdletBinding()]
param([string]$PreviewUrl)
$ErrorActionPreference = 'Stop'
$siteRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$updater = Join-Path $PSScriptRoot 'Update-AssetVersions.ps1'
function Assert([bool]$Condition, [string]$Message) { if (!$Condition) { throw $Message } }
function Get-Version([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.Substring(0, 16).ToLowerInvariant() }
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)
$fixture = Join-Path $tempRoot ('Sincioco-AssetCache-' + [Guid]::NewGuid().ToString('N'))
try {
    [IO.Directory]::CreateDirectory($fixture) | Out-Null
    [IO.File]::WriteAllText((Join-Path $fixture 'sitemap.xml'), '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>https://fixture.invalid/</loc></url></urlset>')
    $assets = [ordered]@{ 'style.css' = 'body{color:red}'; 'app.js' = 'window.fixture=1;'; 'picture.svg' = '<svg xmlns="http://www.w3.org/2000/svg"/>' }
    foreach ($asset in $assets.Keys) { [IO.File]::WriteAllText((Join-Path $fixture $asset), $assets[$asset]) }
    $page = Join-Path $fixture 'Index.html'
    [IO.File]::WriteAllText($page, @'
<!doctype html><html><head>
<link rel="stylesheet" href="/style.css?theme=light&amp;v=old#section">
<script src='app.js'></script></head><body>
<img src="picture.svg?x=1&amp;y=two#mark" alt="Fixture">
<a href="picture.svg">Full image</a>
<script src="https://example.invalid/remote.js?v=keep"></script>
<img src="//example.invalid/remote.png?v=keep" alt="External">
<a href="guide.pdf?edition=1#page=2">Download</a></body></html>
'@)
    & $updater -SiteRoot $fixture | Out-Null
    $first = [IO.File]::ReadAllText($page)
    $css = Get-Version (Join-Path $fixture 'style.css')
    $js = Get-Version (Join-Path $fixture 'app.js')
    $image = Get-Version (Join-Path $fixture 'picture.svg')
    Assert ($first.Contains("/style.css?theme=light&amp;v=$css#section")) 'CSS version must preserve the other parameter and fragment.'
    Assert ($first.Contains("src='app.js?v=$js'")) 'JavaScript must use its content hash and retain attribute quoting.'
    Assert ($first.Contains("picture.svg?x=1&amp;y=two&amp;v=$image#mark")) 'Image version must preserve encoded parameters and fragment.'
    Assert ($first.Contains("href=`"picture.svg?v=$image`"")) 'Full-size image links must also be versioned.'
    foreach ($unchanged in @('https://example.invalid/remote.js?v=keep', '//example.invalid/remote.png?v=keep', 'guide.pdf?edition=1#page=2')) {
        Assert ($first.Contains($unchanged)) "External URLs and document downloads must remain unchanged: $unchanged"
    }
    [IO.File]::SetLastWriteTimeUtc((Join-Path $fixture 'style.css'), [DateTime]::UtcNow.AddDays(-1))
    & $updater -SiteRoot $fixture | Out-Null
    Assert ([IO.File]::ReadAllText($page) -ceq $first) 'Repeated runs and timestamp-only changes must be byte-for-byte stable.'
    & $updater -SiteRoot $fixture -Check | Out-Null
    foreach ($asset in $assets.Keys) {
        $before = [IO.File]::ReadAllText($page)
        $assetPath = Join-Path $fixture $asset
        $oldVersion = Get-Version $assetPath
        [IO.File]::AppendAllText($assetPath, "`nchanged bytes")
        $newVersion = Get-Version $assetPath
        Assert ($newVersion -cne $oldVersion) "Fixture content change must alter the $asset hash."
        $staleDetected = $false
        try { & $updater -SiteRoot $fixture -Check | Out-Null }
        catch { if ($_.Exception.Message -like 'Asset versions need updating:*') { $staleDetected = $true } else { throw } }
        Assert $staleDetected "-Check must detect a changed $asset."
        Assert ([IO.File]::ReadAllText($page) -ceq $before) '-Check must never modify HTML.'
        & $updater -SiteRoot $fixture | Out-Null
        $after = [IO.File]::ReadAllText($page)
        Assert ($after -ceq $before.Replace($oldVersion, $newVersion)) "Changing $asset must change only its own version references."
        & $updater -SiteRoot $fixture | Out-Null
        Assert ([IO.File]::ReadAllText($page) -ceq $after) "Second pass after changing $asset must be stable."
    }
    & $updater -SiteRoot $fixture -Check | Out-Null
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    if (!$resolvedFixture.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Refusing to remove a fixture outside TEMP.' }
    if (Test-Path -LiteralPath $resolvedFixture) { Remove-Item -LiteralPath $resolvedFixture -Recurse -Force }
}
Write-Output 'PASS: CSS/JS/image content changes get new versions; unchanged assets stay stable; queries, fragments, exclusions and read-only stale detection work.'
if (!$PreviewUrl) { Write-Output 'IIS header checks skipped; supply -PreviewUrl to verify HTTP caching and conditional responses.'; return }
$baseUri = [Uri]($PreviewUrl.TrimEnd('/') + '/')
Assert ($baseUri.IsAbsoluteUri -and $baseUri.Scheme -in 'http', 'https') '-PreviewUrl must be an absolute HTTP/HTTPS address.'
$handler = [Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect = $false
$client = [Net.Http.HttpClient]::new($handler)
$client.Timeout = [TimeSpan]::FromSeconds(15)
function Get-Response([string]$Relative, [string]$ETag = '') {
    $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get, [Uri]::new($baseUri, $Relative))
    try {
        if ($ETag) { $request.Headers.TryAddWithoutValidation('If-None-Match', $ETag) | Out-Null }
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        try { return [pscustomobject]@{ Status = [int]$response.StatusCode; Cache = [string]$response.Headers.CacheControl; ETag = [string]$response.Headers.ETag } }
        finally { $response.Dispose() }
    } finally { $request.Dispose() }
}
try {
    foreach ($route in @('', '?v=0123456789abcdef')) {
        $html = Get-Response $route
        Assert ($html.Status -eq 200 -and $html.Cache -match '\bno-cache\b' -and $html.Cache -notmatch '\bimmutable\b') "HTML '$route' must return 200 with revalidation, even with a version query."
        Assert (![string]::IsNullOrWhiteSpace($html.ETag)) "HTML '$route' must retain its native ETag."
        $conditional = Get-Response $route $html.ETag
        Assert ($conditional.Status -eq 304 -and $conditional.Cache -match '\bno-cache\b') "Unchanged HTML '$route' must revalidate with 304 and no-cache."
    }
    foreach ($asset in @('CSS/site.css', 'AgenticAI/projects.js', 'Images/favicon-32x32.png')) {
        $versioned = $asset + '?v=' + (Get-Version (Join-Path $siteRoot $asset))
        $response = Get-Response $versioned
        Assert ($response.Status -eq 200 -and $response.Cache -match '\bpublic\b' -and $response.Cache -match '\bmax-age=31536000\b' -and $response.Cache -match '\bimmutable\b' -and $response.Cache -notmatch '\bno-cache\b') "Versioned $asset must be immutable for one year."
        Assert (![string]::IsNullOrWhiteSpace($response.ETag)) "Versioned $asset must retain its native ETag."
        $conditional = Get-Response $versioned $response.ETag
        Assert ($conditional.Status -eq 304 -and $conditional.Cache -match '\bimmutable\b') "Unchanged versioned $asset must support 304 with its immutable policy."
        $plain = Get-Response $asset
        Assert ($plain.Status -eq 200 -and $plain.Cache -match '\bno-cache\b' -and $plain.Cache -notmatch '\bimmutable\b') "Unversioned $asset must revalidate."
    }
    $missing = Get-Response ('Images/cache-missing-' + [Guid]::NewGuid().ToString('N') + '.png?v=0123456789abcdef')
    Assert ($missing.Status -eq 404 -and $missing.Cache -notmatch '\bimmutable\b|max-age=31536000') 'A missing versioned asset must return 404 without a year-long cache policy.'
} finally { $client.Dispose() }
Write-Output 'PASS: IIS HTML revalidation/304, versioned CSS/JS/image immutable caching/304, unversioned revalidation and safe missing-asset response.'
