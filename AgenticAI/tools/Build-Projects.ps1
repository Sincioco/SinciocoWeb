# Build static project pages from reviewed, pinned local README snapshots.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$siteRoot = Split-Path $projectRoot -Parent
. (Join-Path $PSScriptRoot 'Convert-ProjectReadme.ps1')
. (Join-Path $PSScriptRoot 'Format-SinStarReadme.ps1')
$version = '20261005-projects-6'
$order = @('pmt', 'life2', 'sinstar', 'smile2', 'sinaiprompt', 'smile1')
$projects = foreach ($slug in $order) {
    Get-Content -LiteralPath (Join-Path $projectRoot "content/$slug/source.json") -Raw | ConvertFrom-Json
}
function Encode([string]$text) { [Net.WebUtility]::HtmlEncode($text) }
function ProjectTabs([string]$current) {
    $items = foreach ($project in $projects) {
        $active = if ($project.slug -eq $current) { ' aria-current="page"' } else { '' }
        '<a href="{0}.html"{1}>{2}</a>' -f $project.slug, $active, (Encode $project.name)
    }
    '<nav class="project-tabs" aria-label="Projects">' + ($items -join '') + '</nav>'
}
function WriteProjectPage([string]$file, [string]$title, [string]$description, [string]$content, [string]$current) {
    $canonical = if ($file -eq 'Index.html') { '' } else { $file }
    $tabs = ProjectTabs $current
    $videoScript = if ($current -eq 'sinstar') { '<script src="project-video.js?v=' + $version + '" defer></script>' } else { '' }
    $html = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$(Encode $title) | Agentic AI Projects · Sincioco</title>
  <meta name="description" content="$(Encode $description)">
  <meta name="theme-color" content="#ffffff">
  <link rel="canonical" href="https://sincioco.com/AgenticAI/$canonical">
  <link rel="icon" href="../Images/favicon.svg?v=20260923" type="image/svg+xml">
  <link rel="stylesheet" href="../CSS/site.css?v=$version">
  <link rel="stylesheet" href="projects.css?v=$version">
  <script src="projects.js?v=$version" defer></script>
$videoScript
</head>
<body class="projects-page">
  <a class="skip-link" href="#main">Skip to content</a>
  <header class="site-header"><div class="container nav-shell">
    <a class="brand" href="../">Louiery Sincioco<span>Software Architect</span></a>
    <nav class="primary-nav" aria-label="Main"><a href="../">Home</a><a href="../Resume/">Resume</a><a href="../Military/">Military</a><span class="nav-separator" aria-hidden="true"></span><a href="./" aria-current="page">Agentic AI Projects</a><a class="nav-contact" href="mailto:louiery@gmail.com">Let’s Talk</a></nav>
  </div></header>
  <div class="projects-bar"><div class="container">$tabs</div></div>
  $content
  <footer class="site-footer"><div class="container footer-inner"><p>© 2026 Louiery Sincioco</p><div class="footer-links"><a href="../">Sincioco.com</a><a href="mailto:louiery@gmail.com">louiery@gmail.com</a></div></div></footer>
</body>
</html>
"@
    Set-Content -LiteralPath (Join-Path $projectRoot $file) -Value $html -Encoding utf8
}
$cards = foreach ($project in $projects) {
    $cover = if ($project.heroImage) { $project.heroImage } else { $project.images[0].localPath }
    $coverHtml = if ($cover) { '<img src="{0}" alt="{1}" loading="lazy" decoding="async">' -f (Encode $cover), (Encode ($project.name + ' project preview')) } else { '' }
    @"
<a class="project-card" href="$($project.slug).html"><div class="project-card-image">$coverHtml</div><div class="project-card-copy"><h2>$(Encode $project.name)</h2><p>$(Encode $project.description)</p><span class="text-link">Explore project <span aria-hidden="true">→</span></span></div></a>
"@
}
$landing = @"
<main id="main" class="container projects-landing"><header class="page-hero"><p class="eyebrow">Ideas into working software</p><h1>Agentic AI Projects</h1><p class="lead">Explore six projects by Louiery Sincioco: tools for work and everyday life, programming languages, and the world of Sin Star I.</p></header><div class="project-grid">$($cards -join "`n")</div></main>
"@
WriteProjectPage 'Index.html' 'Agentic AI Projects' 'Explore PMT, Life 2.0, Sin Star I, SMILE 2.0, Sin AI Prompt and SMILE 1.0 by Louiery Sincioco.' $landing ''
$sectionCount = 0
foreach ($project in $projects) {
    $markdown = Get-Content -LiteralPath (Join-Path $projectRoot "content/$($project.slug)/README.md") -Raw
    if ($project.slug -eq 'sinstar') { $markdown = Format-SinStarReadme -Markdown $markdown }
    $document = Convert-ProjectReadme $project $markdown $projectRoot
    if ($project.slug -eq 'sinstar') {
        $trailer = [regex]::Match($document.Html, '(?s)^<p>\s*(<a href="https://www.youtube.com/watch\?v=IuDbnSnKEPo">.*?</a>)<br>\s*(.*?)</p>')
        if (!$trailer.Success) { throw 'The Sin Star I trailer markup changed; review its inline player.' }
        $player = '<div class="project-video" data-video-id="IuDbnSnKEPo"><div class="project-video-frame">' + $trailer.Groups[1].Value + '</div><p class="project-video-status" role="status">Hover to play with sound, or select the video.</p></div><p>' + $trailer.Groups[2].Value + '</p>'
        $document.Html = $player + $document.Html.Substring($trailer.Length)
    }
    $navigation = foreach ($section in $document.Sections) {
        '<a href="#{0}" class="section-level-{1}">{2}</a>' -f $section.id, $section.level, (Encode $section.label)
    }
    $sectionCount += $document.Sections.Count
    $artwork = if ($project.heroImage) { '<img class="project-artwork" src="{0}" alt="{1}" width="240" height="240" decoding="async">' -f (Encode $project.heroImage), (Encode $project.heroAlt) } else { '' }
    $sourceUrl = "$($project.repository)/blob/$($project.commit)/$($project.readmePath)"
    $extra = if ($project.slug -eq 'smile2') { '<a class="text-link" href="../smile2/">Learn SMILE 2.0 →</a>' } else { '' }
    $content = @"
<div class="container project-layout">
  <aside class="project-sidebar"><details class="section-menu" open><summary>On this page</summary><nav class="section-nav" aria-label="$(Encode $project.name) sections"><a href="#project-overview" aria-current="location">Overview</a>$($navigation -join "`n")</nav></details><a class="project-repository" href="$($project.repository)">View repository ↗</a></aside>
  <main id="main" class="project-main"><header class="project-heading"><p class="eyebrow">Agentic AI Projects / $(Encode $project.name)</p><h1 id="project-overview">$(Encode $document.Title)</h1><p class="lead">$(Encode $project.description)</p><div class="project-links"><a class="text-link" href="$($project.repository)">View on GitHub ↗</a>$extra</div>$artwork</header>
  <article class="project-content">$($document.Html)</article>
  <div class="project-source"><p>Content and images from the public <a href="$sourceUrl">$([Net.WebUtility]::HtmlEncode($project.name)) README</a>, retrieved October 5, 2026. Repository snapshot <a href="$($project.repository)/commit/$($project.commit)">$($project.commit.Substring(0,7))</a>.</p><a href="#project-overview">Back to top ↑</a></div></main>
</div>
"@
    WriteProjectPage "$($project.slug).html" $project.name $project.description $content $project.slug
}
$mapPath = Join-Path $siteRoot 'sitemap.xml'
$sitemap = Get-Content -LiteralPath $mapPath -Raw
$sitemap = $sitemap -replace '(?s)\s*<url><loc>https://sincioco.com/AgenticAI/.*?</url>', ''
$urls = @('<url><loc>https://sincioco.com/AgenticAI/</loc><lastmod>2026-10-05</lastmod></url>')
$urls += $order | ForEach-Object { "<url><loc>https://sincioco.com/AgenticAI/$_.html</loc><lastmod>2026-10-05</lastmod></url>" }
$sitemap = $sitemap.Replace('</urlset>', ($urls -join "`n  ") + "`n</urlset>")
Set-Content -LiteralPath $mapPath -Value $sitemap.TrimEnd() -Encoding utf8
Write-Output "Built 7 project pages with $sectionCount section links from local source snapshots."
