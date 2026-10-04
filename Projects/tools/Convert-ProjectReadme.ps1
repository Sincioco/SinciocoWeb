# Convert reviewed repository snapshots to site-owned semantic HTML.
# This is a build-time helper; visitors need no Markdown library or network fetch.
function Convert-ProjectReadme($Source, [string]$Markdown, [string]$ProjectRoot) {
    $html = (ConvertFrom-Markdown -InputObject $Markdown).Html
    $imageMap = @{}
    foreach ($image in $Source.images) { $imageMap[$image.source] = $image.localPath }
    $base = [uri]("$($Source.repository)/blob/$($Source.commit)/$($Source.readmePath)")
    $html = [regex]::Replace($html, '(?is)<(script|style|iframe|object|embed)\b[^>]*>.*?</\1>', '')
    $html = [regex]::Replace($html, '(?is)<!--.*?-->', '')
    # Discard repository presentation attributes; the site's CSS owns all formatting.
    $html = [regex]::Replace($html, '(?i)\s+(?:style|class|align|width|height|border|cellpadding|cellspacing|on\w+)\s*=\s*(?:"[^"]*"|''[^'']*''|[^\s>]+)', '')
    $html = [regex]::Replace($html, '(?i)\b(href|src)="([^"]+)"', {
        param($match)
        $attribute = $match.Groups[1].Value.ToLowerInvariant()
        $url = [Net.WebUtility]::HtmlDecode($match.Groups[2].Value)
        if ($imageMap.ContainsKey($url)) { $url = $imageMap[$url] }
        elseif ($attribute -eq 'src') { throw "Unmapped image in $($Source.slug): $url" }
        elseif ($url -match '^(javascript:|data:|vbscript:)') { throw "Unsupported link in $($Source.slug): $url" }
        elseif ($url -notmatch '^(#|https?://|mailto:|tel:)') {
            if ($url -match '^\.?/?README\.md(?:#(.*))?$') {
                $url = if ($Matches[1]) { '#' + $Matches[1] } else { '#project-overview' }
            } else { $url = [uri]::new($base, $url).AbsoluteUri }
        }
        '{0}="{1}"' -f $attribute, [Net.WebUtility]::HtmlEncode($url)
    })
    # Use GitHub-compatible heading anchors so the README's existing jump links work.
    $sections = [Collections.Generic.List[object]]::new()
    $slugs = @{}
    $state = @{ Title = $Source.name; FirstHeading = $true }
    $html = [regex]::Replace($html, '(?is)<h([1-6])\b[^>]*>(.*?)</h\1>', {
        param($match)
        $level = [int]$match.Groups[1].Value
        $label = [Net.WebUtility]::HtmlDecode(($match.Groups[2].Value -replace '<[^>]+>', '')).Trim()
        $slug = ($label.ToLowerInvariant() -replace '[^\p{L}\p{N}\s_-]', '') -replace '\s', '-'
        if (-not $slug) { $slug = 'section' }
        if ($slugs.ContainsKey($slug)) { $slugs[$slug]++; $slug += '-' + $slugs[$slug] } else { $slugs[$slug] = 0 }
        if ($level -eq 1 -and $state.FirstHeading) {
            $state.Title = $label
            $state.FirstHeading = $false
            return '<span id="' + $slug + '"></span>'
        }
        if ($level -eq 1) { $level = 2 }
        if ($level -le 3) { $sections.Add(@{ id = $slug; label = $label; level = $level }) }
        '<h{0} id="{1}">{2}</h{0}>' -f $level, $slug, $match.Groups[2].Value
    })
    # Give local images intrinsic dimensions to reserve space as lazy images load.
    Add-Type -AssemblyName System.Drawing
    $html = [regex]::Replace($html, '(?is)<img\b[^>]*>', {
        param($match)
        $tag = $match.Value.TrimEnd('>', '/', ' ')
        $src = [Net.WebUtility]::HtmlDecode([regex]::Match($tag, 'src="([^"]+)"').Groups[1].Value)
        $file = Join-Path $ProjectRoot $src
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing image: $file" }
        if ($tag -notmatch '\balt=') { $tag += ' alt="' + [Net.WebUtility]::HtmlEncode($Source.name + ' project image') + '"' }
        if ([IO.Path]::GetExtension($file) -ne '.svg') {
            $bitmap = [Drawing.Image]::FromFile($file)
            try { $tag += ' width="' + $bitmap.Width + '" height="' + $bitmap.Height + '"' } finally { $bitmap.Dispose() }
        }
        $tag + ' loading="lazy" decoding="async">'
    })
    # Screenshot tables become a responsive gallery, keeping labels and captions.
    $html = [regex]::Replace($html, '(?is)<table\b[^>]*>(.*?)</table>', {
        param($match)
        $table = $match.Groups[1].Value
        if ($table -match '<img\b') {
            $rows = [regex]::Matches($table, '(?is)<tr\b[^>]*>(.*?)</tr>')
            $cards = [Collections.Generic.List[string]]::new()
            $pendingLabels = @()
            for ($rowIndex = 0; $rowIndex -lt $rows.Count; $rowIndex++) {
                $cells = @([regex]::Matches($rows[$rowIndex].Groups[1].Value, '(?is)<t[hd]\b[^>]*>(.*?)</t[hd]>') | ForEach-Object { $_.Groups[1].Value.Trim() })
                if (($cells -join '') -notmatch '<img\b') { $pendingLabels = $cells; continue }
                $captions = @()
                if ($rowIndex + 1 -lt $rows.Count) {
                    $next = $rows[$rowIndex + 1].Groups[1].Value
                    if ($next -notmatch '<img\b|<th\b' -and $next -match '<td') {
                        $candidate = @([regex]::Matches($next, '(?is)<td\b[^>]*>(.*?)</td>') | ForEach-Object { $_.Groups[1].Value.Trim() })
                        # A row made only of short bold titles labels the following images.
                        if (($candidate -join '') -notmatch '^(?:\s*<strong>.*?</strong>\s*)+$') { $captions = $candidate; $rowIndex++ }
                    }
                }
                for ($i = 0; $i -lt $cells.Count; $i++) {
                    $label = if ($i -lt $pendingLabels.Count) { '<div class="gallery-label">' + $pendingLabels[$i] + '</div>' } else { '' }
                    $caption = if ($i -lt $captions.Count) { '<figcaption>' + $captions[$i] + '</figcaption>' } else { '' }
                    $cards.Add('<figure>' + $label + $cells[$i] + $caption + '</figure>')
                }
                $pendingLabels = @()
            }
            if ($pendingLabels.Count) { $cards.Add('<p>' + ($pendingLabels -join ' ') + '</p>') }
            '<div class="project-gallery">' + ($cards -join "`n") + '</div>'
        } else {
            '<div class="project-table" role="region" aria-label="Scrollable project table" tabindex="0"><table>' + $table + '</table></div>'
        }
    })
    return @{ Html = $html; Title = $state.Title; Sections = $sections }
}
