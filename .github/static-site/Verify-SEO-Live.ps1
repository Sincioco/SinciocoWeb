param([string]$ReportName = 'seo-live-validation.json')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Verification-Http.ps1')
Assert-VerificationReportName $ReportName
$siteRoot = Join-Path $PSScriptRoot 'website'
$diagnostics = Join-Path $PSScriptRoot 'diagnostics'
New-Item -ItemType Directory -Path $diagnostics -Force | Out-Null
$results = [Collections.Generic.List[object]]::new()
$client = $null; $firstClient = $null
$bookPages = 'https://sincioco.github.io/SinStar_Audio_BookOne/'
$storyPages = 'https://sincioco.github.io/SinStar_Storyboard/'

function Add-SeoCheck {
    param([string]$Kind, [string]$Url, [scriptblock]$Action)
    try {
        $evidence = & $Action
        $results.Add([pscustomobject]@{kind=$Kind;url=$Url;passed=[bool]$evidence.passed;evidence=$evidence})
    } catch { $results.Add([pscustomobject]@{kind=$Kind;url=$Url;passed=$false;error=$_.Exception.Message}) }
}

function Test-PagesFraming {
    param($Response)
    if (-not [string]::IsNullOrWhiteSpace($Response.XFrameOptions)) { return $false }
    # Multiple CSP policies all apply. Each frame-ancestors directive must permit both wrappers.
    foreach ($match in [regex]::Matches($Response.ContentSecurityPolicy, '(?i)(?:^|[;,])\s*frame-ancestors\s+([^;,]+)')) {
        $sources = @($match.Groups[1].Value.Trim() -split '\s+')
        foreach ($origin in @('https://sincioco.com','https://sinstar.sincioco.com')) {
            if ($sources -notcontains '*' -and $sources -notcontains 'https:' -and $sources -notcontains $origin) { return $false }
        }
    }
    return $true
}

try {
    $contract = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'pages-migration-contract.json')) | ConvertFrom-Json
    if ($contract.book_pages_url -cne $bookPages -or $contract.storyboard_pages_url -cne $storyPages) { throw 'Unexpected Pages destinations in migration contract.' }
    $sitemap = Read-VerificationXml ([IO.File]::ReadAllBytes((Join-Path $siteRoot 'sitemap.xml')))
    $locations = @($sitemap.SelectNodes('/*[local-name()="urlset"]/*[local-name()="url"]/*[local-name()="loc"]') | ForEach-Object { $_.InnerText })
    if ($locations.Count -ne 21 -or @($locations | Select-Object -Unique).Count -ne 21) { throw 'Main sitemap must contain exactly 21 unique canonical pages.' }
    $checks = @()
    foreach ($location in $locations) {
        $uri = [Uri]$location
        if (-not $uri.IsAbsoluteUri -or $uri.Scheme -cne 'https' -or $uri.Host -cne 'sincioco.com' -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) { throw 'Unexpected canonical URL in main sitemap.' }
        $relative = $uri.AbsolutePath.TrimStart('/')
        if (-not $relative -or $relative.EndsWith('/')) { $relative += 'index.html' }
        if ($relative.Contains('..') -or $relative.Contains('%') -or $relative.Contains('\')) { throw 'Unsafe canonical path in main sitemap.' }
        $checks += [pscustomobject]@{url=$location;local=(Join-Path $siteRoot $relative);html=$true}
    }
    $checks += [pscustomobject]@{url='https://sincioco.com/robots.txt';local=(Join-Path $siteRoot 'robots.txt');html=$false}
    $checks += [pscustomobject]@{url='https://sincioco.com/sitemap.xml';local=(Join-Path $siteRoot 'sitemap.xml');html=$false}
    $client = New-VerificationClient
    $firstClient = New-VerificationClient -AllowAutoRedirect $false
    foreach ($check in $checks) {
        Add-SeoCheck 'main-canonical-bytes' $check.url {
            $r = Get-VerificationResponse -Client $client -Uri $check.url
            $bytes = Get-VerificationByteEvidence $r $check.local
            $metadata = $null; $metadataOkay = $true
            if ($check.html) {
                $metadata = Get-VerificationHtmlMetadata $r.Bytes
                $metadataOkay = ($metadata.canonicals.Count -eq 1 -and $metadata.canonicals[0] -ceq $check.url -and
                    (($metadata.robots -join ',') + ',' + $r.XRobotsTag) -notmatch '(?i)\b(?:noindex|none)\b')
            }
            [pscustomobject]@{passed=($r.Status -eq 200 -and $r.FinalUrl -ceq $check.url -and $bytes.matches_staged -and $metadataOkay);status=$r.Status;final_url=$r.FinalUrl;bytes=$bytes;metadata=$metadata;x_robots_tag=$r.XRobotsTag}
        }
    }
    $wrappers = @(@{path='/BookOne/';local='BookOne/index.html';canonical=$bookPages},@{path='/SinStar_Storyboard/';local='SinStar_Storyboard/index.html';canonical=$storyPages})
    foreach ($origin in @('https://sincioco.com','https://sinstar.sincioco.com')) {
        foreach ($wrapper in $wrappers) {
            $url = $origin + $wrapper.path
            Add-SeoCheck 'wrapper-noindex-canonical' $url {
                $r = Get-VerificationResponse -Client $client -Uri $url
                $bytes = Get-VerificationByteEvidence $r (Join-Path $siteRoot $wrapper.local)
                $metadata = Get-VerificationHtmlMetadata $r.Bytes
                $metaOkay = $metadata.canonicals.Count -eq 1 -and $metadata.canonicals[0] -ceq $wrapper.canonical -and
                    ($metadata.robots -join ',') -match '(?i)\bnoindex\b' -and $metadata.iframes.Count -eq 1 -and $metadata.iframes[0] -ceq $wrapper.canonical -and
                    $metadata.iframe_attributes[0].referrerpolicy -ceq 'strict-origin-when-cross-origin'
                if ($wrapper.canonical -ceq $storyPages) { $metaOkay = $metaOkay -and $metadata.iframe_attributes[0].allow -match '(?i)(?:^|;)\s*encrypted-media(?:\s*;|\s*$)' }
                [pscustomobject]@{passed=($r.Status -eq 200 -and $r.FinalUrl -ceq $url -and $bytes.matches_staged -and $metaOkay);status=$r.Status;final_url=$r.FinalUrl;bytes=$bytes;metadata=$metadata;expected_canonical=$wrapper.canonical}
            }
        }
        $url = $origin + '/sitemap-sinstar.xml'
        Add-SeoCheck 'cross-site-sitemap-first-redirect' $url {
            $r = Get-VerificationResponse -Client $firstClient -Uri $url
            [pscustomobject]@{passed=($r.Status -eq 301 -and $r.FinalUrl -ceq $url -and $r.Location -ceq ($bookPages + 'sitemap.xml'));status=$r.Status;final_url=$r.FinalUrl;location=$r.Location;expected_location=($bookPages + 'sitemap.xml')}
        }
    }
    # Root IDs are an explicit content contract; HTML or a hosting error page cannot pass on canonical tags alone.
    foreach ($page in @(@{url=$bookPages;ids=@($contract.book_identity.required_ids);book=$true},@{url=$storyPages;ids=@($contract.storyboard_identity.required_ids);book=$false})) {
        if ($page.ids.Count -eq 0 -or @($page.ids | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count) { throw 'Pages root IDs are missing from the migration contract.' }
        Add-SeoCheck 'direct-pages-indexable' $page.url {
            $r = Get-VerificationResponse -Client $client -Uri $page.url
            $metadata = Get-VerificationHtmlMetadata $r.Bytes
            $missingIds = @($page.ids | Where-Object { $metadata.ids -cnotcontains $_ })
            $frameOkay = Test-PagesFraming $r
            $follow = $null; $followOkay = $true
            if ($page.book) {
                $follow = @($metadata.inputs | Where-Object { $_.id -ceq $contract.book_identity.follow_input_id })
                $followOkay = ($follow.Count -eq 1 -and $follow[0].autocomplete -ceq $contract.book_identity.follow_autocomplete -and $follow[0].checked -eq $contract.book_identity.follow_checked)
            }
            $metaOkay = $metadata.canonicals.Count -eq 1 -and $metadata.canonicals[0] -ceq $page.url -and
                (($metadata.robots -join ',') + ',' + $r.XRobotsTag) -notmatch '(?i)\b(?:noindex|none)\b' -and
                -not [string]::IsNullOrWhiteSpace($metadata.title) -and $metadata.descriptions.Count -eq 1 -and
                -not [string]::IsNullOrWhiteSpace($metadata.descriptions[0]) -and $missingIds.Count -eq 0 -and $followOkay
            [pscustomobject]@{passed=($r.Status -eq 200 -and $r.FinalUrl -ceq $page.url -and $r.ContentType -match '^(?i:text/html)(?:;|$)' -and $metaOkay -and $frameOkay);status=$r.Status;final_url=$r.FinalUrl;bytes=$r.Bytes.Length;sha256=(Get-VerificationSha256 $r.Bytes);metadata=$metadata;expected_root_ids=$page.ids;missing_root_ids=$missingIds;follow_input=$follow;follow_input_matches=$followOkay;x_robots_tag=$r.XRobotsTag;x_frame_options=$r.XFrameOptions;content_security_policy=$r.ContentSecurityPolicy;allows_wrapper_framing=$frameOkay}
        }
    }
    $url = $bookPages + 'sitemap.xml'
    Add-SeoCheck 'pages-book-sitemap' $url {
        $r = Get-VerificationResponse -Client $client -Uri $url
        $xml = Read-VerificationXml $r.Bytes
        $urls = @($xml.SelectNodes('/*[local-name()="urlset"]/*[local-name()="url"]/*[local-name()="loc"]') | ForEach-Object { $_.InnerText })
        $scopeOkay = $urls.Count -gt 0 -and @($urls | Select-Object -Unique).Count -eq $urls.Count -and $urls -ccontains $bookPages
        foreach ($entry in $urls) {
            $parsed = [Uri]$entry
            if (-not $parsed.IsAbsoluteUri -or $parsed.Scheme -cne 'https' -or $parsed.Host -cne 'sincioco.github.io' -or
                -not $parsed.AbsolutePath.StartsWith('/SinStar_Audio_BookOne/', [StringComparison]::Ordinal) -or $parsed.UserInfo -or $parsed.Query -or $parsed.Fragment) { $scopeOkay = $false }
        }
        [pscustomobject]@{passed=($r.Status -eq 200 -and $r.FinalUrl -ceq $url -and $scopeOkay);status=$r.Status;final_url=$r.FinalUrl;bytes=$r.Bytes.Length;sha256=(Get-VerificationSha256 $r.Bytes);locations=$urls;required_canonical=$bookPages;scoped_to_book=$scopeOkay}
    }
} catch { $results.Add([pscustomobject]@{kind='setup';passed=$false;error=$_.Exception.Message}) }
finally {
    if ($null -ne $client) { $client.Dispose() }
    if ($null -ne $firstClient) { $firstClient.Dispose() }
}
$failures = @($results | Where-Object { -not $_.passed })
$report = [pscustomobject]@{checked_utc=[DateTime]::UtcNow.ToString('o');powershell_version=$PSVersionTable.PSVersion.ToString();comparison='Raw response SHA-256 and byte length for staged content; canonical, framing and sitemap contract for Pages';checks=$results.Count;results=$results.ToArray();failures=$failures}
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $diagnostics $ReportName) -Encoding utf8
[pscustomobject]@{checks=$results.Count;failure_count=$failures.Count;failures=$failures} | ConvertTo-Json -Depth 10
if ($failures.Count -gt 0) { exit 1 }
