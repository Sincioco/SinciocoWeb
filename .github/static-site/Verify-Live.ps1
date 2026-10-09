param(
    [string]$Base = 'https://sincioco.com',
    [string]$MainBase = 'https://sincioco.com',
    [string]$ReportName = 'live-validation.json'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Verification-Http.ps1')
Assert-VerificationReportName $ReportName
$diagnostics = Join-Path $PSScriptRoot 'diagnostics'
New-Item -ItemType Directory -Path $diagnostics -Force | Out-Null
$stageRoot = Join-Path $PSScriptRoot 'website'
$results = [Collections.Generic.List[object]]::new()
$client = $null; $firstClient = $null
$bookPages = 'https://sincioco.github.io/SinStar_Audio_BookOne/'
$storyPages = 'https://sincioco.github.io/SinStar_Storyboard/'

function Add-LiveCheck {
    param([string]$Kind, [string]$Url, [scriptblock]$Action)
    try {
        $evidence = & $Action
        $results.Add([pscustomobject]@{kind=$Kind;url=$Url;passed=[bool]$evidence.passed;evidence=$evidence})
    } catch {
        $results.Add([pscustomobject]@{kind=$Kind;url=$Url;passed=$false;error=$_.Exception.Message})
    }
}

try {
    foreach ($candidate in @($Base,$MainBase)) {
        $parsed = [Uri]$candidate
        if (-not $parsed.IsAbsoluteUri -or $parsed.Scheme -cne 'https' -or $parsed.UserInfo -or
            $parsed.AbsolutePath -ne '/' -or $parsed.Query -or $parsed.Fragment) { throw 'Base URLs must be HTTPS origins without credentials, paths, queries or fragments.' }
    }
    $Base = $Base.TrimEnd('/'); $MainBase = $MainBase.TrimEnd('/')
    $origins = @($Base,$MainBase) | Select-Object -Unique
    $config = [IO.File]::ReadAllText((Join-Path $stageRoot 'staticwebapp.config.json')) | ConvertFrom-Json
    $contract = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'pages-migration-contract.json')) | ConvertFrom-Json
    if ($contract.book_pages_url -cne $bookPages -or $contract.storyboard_pages_url -cne $storyPages) { throw 'Unexpected Pages destinations in migration contract.' }
    $bookWrapper = [string]$contract.book_wrapper_url
    if ($bookWrapper -cne 'https://sincioco.com/SinStar/BookOne/') { throw 'Unexpected public audiobook wrapper URL.' }
    $wrappers = @($contract.wrappers | ForEach-Object {
        if ($_.path -cnotmatch '^(?:SinStar/BookOne|BookOne|SinStar_Storyboard)/index\.html$') { throw 'Unexpected wrapper publication path.' }
        $virtual = $_.path -ceq 'SinStar/BookOne/index.html'
        if ($virtual -and $_.source -cne 'BookOne/index.html') { throw 'The new audiobook route must use the existing book wrapper file.' }
        if (-not $virtual -and $_.source -and $_.source -cne $_.path) { throw 'Unexpected physical wrapper source.' }
        $local = if ($virtual) { $_.source } else { $_.path }
        [pscustomobject]@{path=('/' + $_.path.Substring(0, $_.path.Length - 'index.html'.Length));local=$local;virtual=$virtual}
    })
    if ($wrappers.Count -ne 3 -or @($wrappers.path | Select-Object -Unique).Count -ne 3) { throw 'Expected the new and legacy book wrappers plus storyboard.' }
    $assets = @($contract.retired_reader_assets)
    if ($assets.Count -ne 62 -or @($assets | Select-Object -Unique).Count -ne 62 -or @($assets | Where-Object { $_ -cmatch '^audio/[^/]+\.mp3$' }).Count -ne 43) { throw 'Expected 62 unique historical reader assets, including 43 audio files.' }
    foreach ($asset in $assets) {
        if ($asset -notmatch '^[A-Za-z0-9_./-]+$' -or $asset.Contains('..') -or $asset.StartsWith('/')) { throw 'Unsafe historical asset path.' }
    }
    $targetMapping = $contract.reader_asset_targets
    if ($null -eq $targetMapping -or $targetMapping -isnot [pscustomobject]) { throw 'Reader asset targets must be a JSON object.' }
    $mappingProperties = @($targetMapping.PSObject.Properties)
    if ($mappingProperties.Count -ne 42) { throw 'Expected exactly 42 renamed chapter audio targets.' }
    $mappedTargets = @{}
    foreach ($property in $mappingProperties) {
        if ($property.Name -cnotmatch '^audio/(?:[0-3][0-9]|4[01])\.mp3$' -or $property.Value -isnot [string]) { throw 'Unexpected historical audio mapping key or target type.' }
        $expectedTarget = $property.Name.Substring(0, $property.Name.Length - 4) + '-headings-v1.mp3'
        if ($property.Value -cne $expectedTarget -or $property.Value -cnotmatch '^[A-Za-z0-9_./-]+$' -or $property.Value.Contains('..') -or $property.Value.StartsWith('/')) { throw 'Unsafe or unexpected current chapter audio target.' }
        $mappedTargets[$property.Name] = $property.Value
    }
    $assetTargets = @{}
    foreach ($asset in $assets) {
        $assetTargets[$asset] = if ($mappedTargets.ContainsKey($asset)) { $mappedTargets[$asset] } else { $asset }
    }
    if (@($mappedTargets.Keys | Where-Object { $assets -cnotcontains $_ }).Count) { throw 'An audio mapping key is absent from the historical asset contract.' }
    $currentAssets = @($assets | ForEach-Object { $assetTargets[$_] })
    if ($currentAssets.Count -ne 62 -or @($currentAssets | Select-Object -Unique).Count -ne 62) { throw 'Expected 62 unique current reader targets.' }
    $assetRoutes = @($config.routes | Where-Object { $_.route -cmatch '^/(?:BookOne|sinstar/novel)/' -and $_.redirect -clike ($bookPages + '*') })
    if ($assetRoutes.Count -ne 124) { throw 'Expected exactly 124 historical asset redirect rules in staged routing.' }
    foreach ($prefix in @('/BookOne/','/sinstar/novel/')) {
        foreach ($asset in $assets) {
            $route = @($config.routes | Where-Object { $_.route -ceq ($prefix + $asset) })
            if ($route.Count -ne 1 -or $route[0].statusCode -ne 301 -or $route[0].redirect -cne ($bookPages + $assetTargets[$asset])) { throw ('Missing or incorrect asset redirect: ' + $prefix + $asset) }
        }
    }
    $client = New-VerificationClient
    $firstClient = New-VerificationClient -AllowAutoRedirect $false
    $paths = @('/', '/Index.html', '/Projects', '/Projects/', '/Projects/Index.html', '/AgenticAI/Index.html', '/Military/Index.html', '/Resume/Index.html', '/smile2/Index.html')
    $paths += @(Get-ChildItem -LiteralPath $stageRoot -Recurse -File | Where-Object { $_.Extension -eq '.html' } | ForEach-Object { '/' + $_.FullName.Substring($stageRoot.Length + 1).Replace('\','/') })
    foreach ($path in @($paths | Select-Object -Unique)) {
        $url = $MainBase + $path
        Add-LiveCheck 'main-route' $url {
            $r = Get-VerificationResponse -Client $client -Uri $url -Method HEAD
            [pscustomobject]@{passed=($r.Status -eq 200 -and ([Uri]$r.FinalUrl).Scheme -ceq 'https' -and ([Uri]$r.FinalUrl).Authority -ceq ([Uri]$MainBase).Authority);status=$r.Status;final_url=$r.FinalUrl;content_type=$r.ContentType}
        }
    }
    foreach ($origin in $origins) {
        foreach ($folder in @('/AgenticAI','/Military','/Resume','/smile2')) {
            $url = $origin + $folder
            Add-LiveCheck 'canonical-folder-slash' $url {
                $first = Get-VerificationResponse -Client $firstClient -Uri $url -Method HEAD
                $final = Get-VerificationResponse -Client $client -Uri $url -Method HEAD
                [pscustomobject]@{passed=($first.Status -eq 301 -and @(($folder + '/'), ($origin + $folder + '/')) -ccontains $first.Location -and $final.Status -eq 200 -and $final.FinalUrl -ceq ($origin + $folder + '/'));status=$first.Status;location=$first.Location;final_status=$final.Status;final_url=$final.FinalUrl}
            }
        }
        foreach ($wrapper in $wrappers) {
            foreach ($url in @(($origin + $wrapper.path.TrimEnd('/')), ($origin + $wrapper.path), ($origin + $wrapper.path + 'index.html'))) {
                Add-LiveCheck 'wrapper-bytes' $url {
                    $first = Get-VerificationResponse -Client $firstClient -Uri $url -Method HEAD
                    $r = Get-VerificationResponse -Client $client -Uri $url
                    $bytes = Get-VerificationByteEvidence $r (Join-Path $stageRoot $wrapper.local)
                    $expectedFinal = $origin + $wrapper.path
                    $isIndexAlias = $url -ceq ($expectedFinal + 'index.html')
                    $redirectOkay = $first.Status -eq 301 -and @($wrapper.path,$expectedFinal) -ccontains $first.Location
                    $directOkay = $first.Status -eq 200 -and -not $first.Location
                    $routeOkay = if ($wrapper.virtual) { $directOkay -or $redirectOkay } elseif ($url -ceq $expectedFinal) { $directOkay } elseif ($isIndexAlias) { $directOkay -or $redirectOkay } else { $redirectOkay }
                    $finalOkay = $r.FinalUrl -ceq $expectedFinal -or (($isIndexAlias -or $wrapper.virtual) -and $r.FinalUrl -ceq $url)
                    [pscustomobject]@{passed=($routeOkay -and $r.Status -eq 200 -and $finalOkay -and $bytes.matches_staged);first_status=$first.Status;location=$first.Location;status=$r.Status;final_url=$r.FinalUrl;expected_final_url=$expectedFinal;bytes=$bytes}
                }
            }
        }
        foreach ($path in @('/BookOne/sw.js','/sinstar/novel/sw.js','/BookOne/retire-legacy-workers.js','/wrapper-nav.js')) {
            $url = $origin + $path
            Add-LiveCheck 'worker-or-bootstrap-bytes' $url {
                $r = Get-VerificationResponse -Client $firstClient -Uri $url
                $bytes = Get-VerificationByteEvidence $r (Join-Path $stageRoot $path.TrimStart('/'))
                $isWorker = $path.EndsWith('/sw.js')
                $cacheOkay = (-not $isWorker -or ($r.CacheControl -match '(?i)(^|[,\s])no-cache([,\s]|$)' -and $r.CacheControl -match '(?i)(^|[,\s])no-store([,\s]|$)'))
                [pscustomobject]@{passed=($r.Status -eq 200 -and $r.FinalUrl -ceq $url -and -not $r.Location -and $r.ContentType -match '^(?i:(?:text|application)/(?:javascript|x-javascript))(?:;|$)' -and $bytes.matches_staged -and $cacheOkay);status=$r.Status;final_url=$r.FinalUrl;location=$r.Location;content_type=$r.ContentType;cache_control=$r.CacheControl;bytes=$bytes}
            }
        }
        foreach ($path in @('/sinstar/novel','/sinstar/novel/','/sinstar/novel/index.html')) {
            $url = $origin + $path
            Add-LiveCheck 'legacy-landing' $url {
                $r = Get-VerificationResponse -Client $client -Uri $url
                $bytes = Get-VerificationByteEvidence $r (Join-Path $stageRoot 'BookOne/index.html')
                [pscustomobject]@{passed=($r.Status -eq 200 -and $r.FinalUrl -ceq $bookWrapper -and $bytes.matches_staged);status=$r.Status;final_url=$r.FinalUrl;bytes=$bytes}
            }
        }
    }
    foreach ($route in $assetRoutes) {
        $url = $Base + $route.route
        Add-LiveCheck 'asset-first-redirect' $url {
            $r = Get-VerificationResponse -Client $firstClient -Uri $url -Method HEAD
            [pscustomobject]@{passed=($r.Status -eq 301 -and $r.FinalUrl -ceq $url -and $r.Location -ceq $route.redirect);status=$r.Status;final_url=$r.FinalUrl;location=$r.Location;expected_location=$route.redirect}
        }
    }
    foreach ($asset in $currentAssets) {
        $url = $bookPages + $asset
        Add-LiveCheck 'pages-asset' $url {
            $r = Get-VerificationResponse -Client $client -Uri $url -Method HEAD
            [pscustomobject]@{passed=($r.Status -eq 200 -and $r.FinalUrl -ceq $url);status=$r.Status;final_url=$r.FinalUrl;content_type=$r.ContentType;content_length=$r.ContentLength}
        }
    }
    foreach ($origin in $origins) {
        $url = $origin + '/sitemap-sinstar.xml'
        Add-LiveCheck 'sitemap-first-redirect' $url {
            $r = Get-VerificationResponse -Client $firstClient -Uri $url -Method HEAD
            [pscustomobject]@{passed=($r.Status -eq 301 -and $r.FinalUrl -ceq $url -and $r.Location -ceq ($bookPages + 'sitemap.xml'));status=$r.Status;final_url=$r.FinalUrl;location=$r.Location;expected_location=($bookPages + 'sitemap.xml')}
        }
    }
    $expectedRangeUrl = $bookPages + $assetTargets['audio/00.mp3']
    foreach ($prefix in @('/BookOne/','/sinstar/novel/')) {
        foreach ($start in @(0,100000)) {
            $url = $Base + $prefix + 'audio/00.mp3'
            Add-LiveCheck 'audio-range' $url {
                $r = Get-VerificationResponse -Client $client -Uri $url -RangeStart $start -RangeEnd ($start + 1023)
                $pattern = '^bytes ' + $start + '-' + ($start + 1023) + '/([0-9]+)$'
                $rangeOkay = $r.ContentRange -cmatch $pattern
                if ($rangeOkay) { $rangeOkay = [long]$Matches[1] -gt ($start + 1023) }
                [pscustomobject]@{passed=($r.Status -eq 206 -and $r.Bytes.Length -eq 1024 -and $rangeOkay -and $r.FinalUrl -ceq $expectedRangeUrl);start=$start;status=$r.Status;bytes=$r.Bytes.Length;content_range=$r.ContentRange;final_url=$r.FinalUrl;expected_final_url=$expectedRangeUrl}
            }
        }
    }
} catch {
    $results.Add([pscustomobject]@{kind='setup';passed=$false;error=$_.Exception.Message})
} finally {
    if ($null -ne $client) { $client.Dispose() }
    if ($null -ne $firstClient) { $firstClient.Dispose() }
}
$failures = @($results | Where-Object { -not $_.passed })
$report = [pscustomobject]@{base=$Base;main_base=$MainBase;tested_utc=[DateTime]::UtcNow.ToString('o');powershell_version=$PSVersionTable.PSVersion.ToString();checks=$results.Count;results=$results.ToArray();failures=$failures}
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $diagnostics $ReportName) -Encoding utf8
[pscustomobject]@{checks=$results.Count;failure_count=$failures.Count;failures=$failures} | ConvertTo-Json -Depth 10
if ($failures.Count -gt 0) { exit 1 }
