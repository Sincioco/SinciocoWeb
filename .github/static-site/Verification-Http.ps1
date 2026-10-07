# Shared read-only HTTP primitives, compatible with Windows PowerShell 5.1 and 7.
Add-Type -AssemblyName System.Net.Http

function Assert-VerificationReportName {
    param([AllowEmptyString()][string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*\.json$' -or
        $Name.Contains('..') -or [IO.Path]::GetFileName($Name) -cne $Name) {
        throw 'ReportName must be a nonempty plain .json filename without parent-directory segments.'
    }
}

function New-VerificationClient {
    param([bool]$AllowAutoRedirect = $true)
    $handler = [System.Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $AllowAutoRedirect
    $handler.MaxAutomaticRedirections = 10
    $handler.UseCookies = $false
    $handler.UseDefaultCredentials = $false
    $handler.AutomaticDecompression = [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(20)
    return $client
}

function Get-VerificationResponse {
    param(
        [Parameter(Mandatory)]$Client,
        [Parameter(Mandatory)][string]$Uri,
        [ValidateSet('GET','HEAD')][string]$Method = 'GET',
        [long]$RangeStart = -1,
        [long]$RangeEnd = -1
    )
    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method), $Uri)
    $response = $null
    try {
        if ($RangeStart -ge 0 -or $RangeEnd -ge 0) {
            if ($RangeStart -lt 0 -or $RangeEnd -lt $RangeStart) { throw 'Invalid byte range.' }
            $request.Headers.Range = [System.Net.Http.Headers.RangeHeaderValue]::new($RangeStart, $RangeEnd)
        }
        $response = $Client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseContentRead).GetAwaiter().GetResult()
        [byte[]]$body = $response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        $headers = @{}
        foreach ($headerName in @('Location','Cache-Control','Content-Security-Policy','X-Frame-Options','X-Robots-Tag')) {
            if ($response.Headers.Contains($headerName)) { $headers[$headerName] = [string]::Join(', ', $response.Headers.GetValues($headerName)) }
            else { $headers[$headerName] = '' }
        }
        return [pscustomobject]@{
            Status = [int]$response.StatusCode
            FinalUrl = $response.RequestMessage.RequestUri.AbsoluteUri
            ContentType = [string]$response.Content.Headers.ContentType
            ContentLength = [string]$response.Content.Headers.ContentLength
            ContentRange = [string]$response.Content.Headers.ContentRange
            Location = $headers['Location']
            CacheControl = $headers['Cache-Control']
            ContentSecurityPolicy = $headers['Content-Security-Policy']
            XFrameOptions = $headers['X-Frame-Options']
            XRobotsTag = $headers['X-Robots-Tag']
            Bytes = $body
        }
    } finally {
        if ($null -ne $response) { $response.Dispose() }
        $request.Dispose()
    }
}

function Get-VerificationSha256 {
    param([Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-VerificationByteEvidence {
    param($Response, [Parameter(Mandatory)][string]$LocalPath)
    [byte[]]$expected = [IO.File]::ReadAllBytes($LocalPath)
    $actualHash = Get-VerificationSha256 -Bytes $Response.Bytes
    $expectedHash = Get-VerificationSha256 -Bytes $expected
    return [pscustomobject]@{
        bytes = $Response.Bytes.Length; expected_bytes = $expected.Length
        sha256 = $actualHash; expected_sha256 = $expectedHash
        matches_staged = ($Response.Bytes.Length -eq $expected.Length -and $actualHash -ceq $expectedHash)
    }
}

function Get-VerificationHtmlAttributes {
    param([string]$Tag)
    $attributes = @{}
    foreach ($match in [regex]::Matches($Tag, '([\w:-]+)\s*=\s*(?:"([^"]*)"|''([^'']*)''|([^\s>]+))')) {
        $value = $match.Groups[2].Value
        if ($match.Groups[3].Success) { $value = $match.Groups[3].Value }
        if ($match.Groups[4].Success) { $value = $match.Groups[4].Value }
        $attributes[$match.Groups[1].Value.ToLowerInvariant()] = [Net.WebUtility]::HtmlDecode($value)
    }
    return $attributes
}

function Get-VerificationHtmlMetadata {
    param([AllowEmptyCollection()][byte[]]$Bytes)
    $html = [Text.Encoding]::UTF8.GetString($Bytes)
    $html = [regex]::Replace($html, '(?is)<!--.*?-->|<script\b[^>]*>.*?</script\s*>|<style\b[^>]*>.*?</style\s*>', '')
    $canonicals = @(); $robots = @(); $ids = @(); $iframes = @(); $iframeAttributes = @(); $descriptions = @(); $inputs = @()
    foreach ($match in [regex]::Matches($html, '<(?:link|meta|iframe|[a-z][\w:-]*)\b[^>]*>', 'IgnoreCase')) {
        $tag = $match.Value
        $attrs = Get-VerificationHtmlAttributes -Tag $tag
        if ($attrs.ContainsKey('id')) { $ids += $attrs['id'] }
        if ($tag -match '^<link\b' -and $attrs['rel'] -match '(?i)(^|\s)canonical(\s|$)') { $canonicals += $attrs['href'] }
        if ($tag -match '^<meta\b' -and $attrs['name'] -match '^(?i:robots|googlebot|bingbot)$') { $robots += $attrs['content'] }
        if ($tag -match '^<meta\b' -and $attrs['name'] -eq 'description') { $descriptions += $attrs['content'] }
        if ($tag -match '^<iframe\b') { $iframes += $attrs['src']; $iframeAttributes += [pscustomobject]@{src=$attrs['src'];referrerpolicy=$attrs['referrerpolicy'];allow=$attrs['allow']} }
        if ($tag -match '^<input\b') { $inputs += [pscustomobject]@{id=$attrs['id'];autocomplete=$attrs['autocomplete'];checked=($tag -match '(?i)\schecked(?:\s|=|/?>)')} }
    }
    $title = [regex]::Match($html, '(?is)<title\b[^>]*>(.*?)</title>').Groups[1].Value.Trim()
    return [pscustomobject]@{canonicals=$canonicals;robots=$robots;ids=$ids;iframes=$iframes;iframe_attributes=$iframeAttributes;title=$title;descriptions=$descriptions;inputs=$inputs}
}

function Read-VerificationXml {
    param([AllowEmptyCollection()][byte[]]$Bytes)
    $settings = [Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $stream = [IO.MemoryStream]::new($Bytes, $false)
    $reader = $null
    try {
        $reader = [Xml.XmlReader]::Create($stream, $settings)
        $document = [Xml.XmlDocument]::new()
        $document.XmlResolver = $null
        $document.Load($reader)
        return ,$document
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
        $stream.Dispose()
    }
}
