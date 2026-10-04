# Rebuild the static site using only PowerShell. No server build step is needed.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$site = Split-Path $PSScriptRoot -Parent
$root = Split-Path $site -Parent
. (Join-Path $root 'tools/Get-SeoHead.ps1')
$version = '20261005-projects-1'
$order = @('index','start','basics','flow','structure','media','game','libraries','reference','advanced','next')
$labels = @('Overview','Your first program','Values & variables','Decisions & loops','Organize your code','Graphics, input & sound','Build Star Collector','Library guide','Built-in reference','Arena & elemental VFX','Debug & keep building')
$pages = @{}
Get-ChildItem (Join-Path $site 'content') -Filter '*.json' | ForEach-Object {
    $page = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
    $pages[$page.id] = $page
}
function Encode([string]$value) { [System.Net.WebUtility]::HtmlEncode($value) }
function Plain([string]$value) { [System.Net.WebUtility]::HtmlDecode(($value -replace '<[^>]+>',' ')) -replace '\s+',' ' }
function PageHref([string]$id) { if ($id -eq 'index') { 'Index.html' } else { "$id.html" } }
$search = [System.Collections.Generic.List[object]]::new()
foreach ($id in $order) {
    if (-not $pages.ContainsKey($id)) { throw "Missing content page: $id" }
    $page = $pages[$id]
    $position = [array]::IndexOf($order,$id)
    $href = PageHref $id
    $title = Encode $page.title
    $description = Encode $page.description
    $navigation = for ($i=0; $i -lt $order.Count; $i++) {
        if ($i -eq 0) { '<p class="nav-group">Start here</p>' }
        if ($i -eq 2) { '<p class="nav-group">Learn the language</p>' }
        if ($i -eq 7) { '<p class="nav-group">Explore & build</p>' }
        $current = if ($order[$i] -eq $id) { ' aria-current="page"' } else { '' }
        '<a href="{0}"{1}><span class="lesson-number">{2:00}</span>{3}</a>' -f (PageHref $order[$i]),$current,$i,(Encode $labels[$i])
    }
    $sections = [regex]::Matches($page.body,'<h2\s+id="([^"]+)"[^>]*>(.*?)</h2>','Singleline')
    $toc = foreach ($heading in $sections) {
        '<a href="#{0}">{1}</a>' -f $heading.Groups[1].Value,(Encode (Plain $heading.Groups[2].Value))
    }
    $search.Add(@{title=$page.title;href=$href;text=(Plain ($page.lead+' '+$page.body)).Trim()})
    foreach ($heading in $sections) {
        $start = $heading.Index
        $next = $page.body.IndexOf('<h2 ', $start + $heading.Length)
        if ($next -lt 0) { $next = $page.body.Length }
        $search.Add(@{title=(Plain $heading.Groups[2].Value);section=$page.title;href="$href#$($heading.Groups[1].Value)";text=(Plain $page.body.Substring($start,$next-$start))})
    }
    $sourceLinks = foreach ($source in $page.sources) {
        $sourcePath = (($source.path -split '/') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
        '<li><a href="https://github.com/Sincioco/SMILE-2.0/blob/main/{0}">{1} ↗</a></li>' -f $sourcePath,(Encode $source.label)
    }
    $previous = if ($position -gt 0) { '<a href="{0}"><small>← Previous</small>{1}</a>' -f (PageHref $order[$position-1]),(Encode $labels[$position-1]) }
    $nextLink = if ($position -lt $order.Count-1) { '<a href="{0}"><small>Up next →</small>{1}</a>' -f (PageHref $order[$position+1]),(Encode $labels[$position+1]) }
    $tocHtml = if ($sections.Count -gt 0) { '<aside class="page-toc" aria-label="On this page"><p>On this page</p>'+($toc -join "`n")+'</aside>' }
    $heroClass = if ($id -eq 'index') { ' doc-home' } else { '' }
    $pageUrl = 'http://sincioco.com/smile2/' + $(if ($id -ne 'index') { $href })
    $breadcrumbs = @(@{ name = 'Home'; url = 'http://sincioco.com/' }, @{ name = 'SMILE 2.0 Guide'; url = 'http://sincioco.com/smile2/' })
    if ($id -ne 'index') { $breadcrumbs += @{ name = $page.title; url = $pageUrl } }
    $seoHead = Get-SeoHead -Title ($page.title + ' | SMILE 2.0 · Sincioco') -Description $page.description -Url $pageUrl -Image 'http://sincioco.com/smile2/images/smile-2.0-logo.png' -ImageAlt 'SMILE 2.0 programming language logo' -PageType TechArticle -Breadcrumbs $breadcrumbs
    $html = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
$seoHead
  <meta name="theme-color" content="#ffffff">
  <link rel="icon" href="../Images/favicon.svg?v=20260923" type="image/svg+xml">
  <link rel="stylesheet" href="../CSS/site.css?v=$version">
  <link rel="stylesheet" href="docs.css?v=$version">
  <script src="search-index.js?v=$version" defer></script>
  <script src="docs.js?v=$version" defer></script>
</head>
<body class="smile-docs$heroClass">
  <a class="skip-link" href="#main">Skip to content</a>
  <header class="site-header"><div class="container nav-shell">
    <a class="brand" href="../">Louiery Sincioco<span>Software Architect</span></a>
    <nav class="primary-nav" aria-label="Main"><a href="../">Home</a><a href="../Resume/">Resume</a><a href="../Military/">Military</a><span class="nav-separator" aria-hidden="true"></span><a href="../AgenticAI/">Agentic AI Projects</a><a class="nav-contact" href="mailto:louiery@gmail.com">Let’s Talk</a></nav>
  </div></header>
  <div class="docs-bar"><div class="docs-bar-inner">
    <a class="docs-brand" href="Index.html"><span class="code-mark" aria-hidden="true">S<span>:</span></span><strong>SMILE 2.0</strong><span class="docs-label">Learn &amp; build</span></a>
    <div class="docs-bar-actions"><span class="edition">Language guide</span><button class="menu-toggle" type="button" aria-expanded="false" aria-controls="lesson-nav" hidden>Lessons <span aria-hidden="true">☰</span></button></div>
  </div></div>
  <div class="docs-layout">
    <aside class="docs-sidebar" id="lesson-nav">
      <div class="search-box" hidden><label for="doc-search">Search the docs</label><input id="doc-search" type="search" placeholder="Try “arrays” or “fire”…" autocomplete="off" aria-controls="search-results"><p id="search-status" class="sr-only" aria-live="polite"></p><div id="search-results" hidden></div></div>
      <nav class="lesson-nav" aria-label="Documentation">$($navigation -join "`n")</nav>
      <a class="source-link" href="https://github.com/Sincioco/SMILE-2.0">Explore the source <span aria-hidden="true">↗</span></a>
      <p class="sidebar-note">Simple Modern and Intuitive<br>Language for Everyone.</p>
    </aside>
    <main id="main" class="doc-main">
      <header class="doc-heading"><p class="eyebrow">$(Encode $page.eyebrow)</p><h1>$title</h1><p class="lead">$(Encode $page.lead)</p></header>
      <article class="doc-content">$($page.body)</article>
      <details class="source-notes"><summary>Sources &amp; version notes</summary><p>Checked against the local SMILE 2.0 source on September 25, 2026. Examples target the native Windows toolchain unless stated otherwise. The linked repository may continue to evolve.</p><ul>$($sourceLinks -join "`n")</ul></details>
      <nav class="lesson-pager" aria-label="Lesson navigation">$previous$nextLink</nav>
    </main>
    $tocHtml
  </div>
  <footer class="site-footer"><div class="container footer-inner"><p>© 2026 Louiery Sincioco · SMILE 2.0</p><div class="footer-links"><a href="../">Sincioco.com</a><a href="start.html">Start learning</a><a href="https://github.com/Sincioco/SMILE-2.0">GitHub ↗</a></div></div></footer>
</body>
</html>
"@
    Set-Content -LiteralPath (Join-Path $site $href) -Value $html -Encoding utf8
}
$api = Get-Content -LiteralPath (Join-Path $site 'data/api.json') -Raw | ConvertFrom-Json
foreach ($entry in $api.functions) {
    $anchor = $entry.name.ToLowerInvariant().Replace('_','-')
    $search.Add(@{title=$entry.name;section='Built-in reference';href="reference.html#$anchor";text="$($entry.signature) $($entry.description)"})
}
$searchJson = ConvertTo-Json -InputObject @($search.ToArray()) -Depth 8 -Compress
Set-Content -LiteralPath (Join-Path $site 'search-index.js') -Value "window.SMILE_SEARCH = $searchJson;" -Encoding utf8
$urls = foreach ($id in $order) { '<url><loc>http://sincioco.com/smile2/{0}</loc><lastmod>2026-10-05</lastmod></url>' -f $(if ($id -ne 'index') { PageHref $id }) }
$mapPath = Join-Path $root 'sitemap.xml'
$sitemap = Get-Content -LiteralPath $mapPath -Raw
$sitemap = $sitemap -replace '(?s)\s*<url><loc>http://sincioco.com/smile2/.*?</url>',''
$sitemap = $sitemap -replace '</urlset>',(($urls -join "`n  ")+"`n</urlset>")
Set-Content -LiteralPath $mapPath -Value $sitemap.TrimEnd() -Encoding utf8
Write-Output "Built $($pages.Count) documentation pages and $($search.Count) search entries."
