# Build static project pages from reviewed, pinned local README snapshots.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$siteRoot = Split-Path $projectRoot -Parent
. (Join-Path $PSScriptRoot 'Convert-ProjectReadme.ps1')
. (Join-Path $PSScriptRoot 'Format-SinStarReadme.ps1')
. (Join-Path $siteRoot 'tools/Get-SeoHead.ps1')
$order = @('sinaiprompt', 'pmt', 'sinstar', 'life2', 'smile2', 'smile1')
$projects = foreach ($slug in $order) {
    $source = Get-Content -LiteralPath (Join-Path $projectRoot "content/$slug/source.json") -Raw | ConvertFrom-Json
    if ($slug -eq 'sinaiprompt') {
        $source.heroImage = 'images/sinaiprompt/sin-ai-prompt-editor.png'
        $source.heroAlt = 'Sin AI Prompt editor with its ribbon, document list, and Help About splash screen'
    }
    $source
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
    $canonical = if ($file -eq 'Index.html') { '' } else { [IO.Path]::GetFileNameWithoutExtension($file) }
    $tabs = ProjectTabs $current
    $videoScript = if ($current -eq 'sinstar') { '<script src="project-video.js" defer></script>' } else { '' }
    $url = "https://sincioco.com/AgenticAI/$canonical"
    $breadcrumbs = @(@{ name = 'Home'; url = 'https://sincioco.com/' }, @{ name = 'Agentic AI Projects'; url = 'https://sincioco.com/AgenticAI/' })
    $imageUrl = 'https://sincioco.com/Resume/Sin_San_Francisco_Cropped.png'
    $imageAlt = 'Louiery Sincioco, software engineer and architect'
    $pageType = 'CollectionPage'
    if ($current) {
        $project = $projects | Where-Object slug -EQ $current
        $breadcrumbs += @{ name = $project.name; url = $url }
        $cover = if ($project.heroImage) { $project.heroImage } else { $project.images[0].localPath }
        if ($cover -notmatch '\.svg$') { $imageUrl = 'https://sincioco.com/AgenticAI/' + $cover; $imageAlt = $project.name + ' project preview' }
        $pageType = 'WebPage'
    }
    $seoHead = Get-SeoHead -Title $title -Description $description -Url $url -Image $imageUrl -ImageAlt $imageAlt -PageType $pageType -Breadcrumbs $breadcrumbs
    $html = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
$seoHead
  <meta name="theme-color" content="#ffffff">
  <link rel="icon" href="../favicon.ico" sizes="16x16 32x32 48x48 64x64 128x128 256x256" type="image/x-icon">
  <link rel="icon" href="../Images/favicon-32x32.png" sizes="32x32" type="image/png">
  <link rel="icon" href="../Images/favicon-16x16.png" sizes="16x16" type="image/png">
  <link rel="apple-touch-icon" href="../apple-touch-icon.png" sizes="180x180">
  <link rel="stylesheet" href="../CSS/site.css">
  <link rel="stylesheet" href="projects.css">
  <script src="projects.js" defer></script>
$videoScript
</head>
<body class="projects-page">
  <a class="skip-link" href="#main">Skip to content</a>
  <header class="site-header"><div class="container nav-shell">
    <a class="brand" href="../">Louiery Sincioco<span>Software Architect</span></a>
    <nav class="primary-nav" aria-label="Main"><a href="../">Home</a><a href="../Resume/">Resume</a><a href="../Military/">Military</a><span class="nav-separator" aria-hidden="true"></span><a href="./" aria-current="page">Agentic AI Projects</a><a class="nav-contact" href="mailto:louiery@sincioco.com">Let’s Talk</a></nav>
  </div></header>
  <div class="projects-bar"><div class="container">$tabs</div></div>
  $content
  <footer class="site-footer"><div class="container footer-inner"><p>© 2026 Louiery Sincioco</p><div class="footer-links"><a href="../">Sincioco.com</a><a href="mailto:louiery@sincioco.com">louiery@sincioco.com</a></div></div></footer>
</body>
</html>
"@
    Set-Content -LiteralPath (Join-Path $projectRoot $file) -Value $html -Encoding utf8
}
$cardOrder = $order
function Get-ResponsiveCardImages {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (!$python) { $python = Get-Command python3 -ErrorAction Stop }
    $checker = Join-Path $projectRoot 'tools/check-card-thumbnails.py'
    $output = & $python.Source -B $checker --site-root $siteRoot --render-json
    if ($LASTEXITCODE -ne 0) { throw 'Responsive card source validation failed.' }
    ($output -join "`n") | ConvertFrom-Json
}
$responsiveCardImages = Get-ResponsiveCardImages
$cards = foreach ($slug in $cardOrder) {
    $project = $projects | Where-Object slug -EQ $slug
    $cover = if ($project.cardImage) { $project.cardImage } elseif ($project.heroImage) { $project.heroImage } else { $project.images[0].localPath }
    $coverClass = if ($project.slug -eq 'life2') { 'project-card-image' } elseif ($project.slug -eq 'smile2') { 'project-card-image project-card-image-logo' } else { 'project-card-image project-card-image-cover' }
    if ($project.slug -eq 'sinaiprompt') { $cover = 'images/sinaiprompt/sin-ai-prompt-thumbnail.png' }
    $coverHtml = if ($project.slug -in @('sinaiprompt', 'pmt')) { $responsiveCardImages.($project.slug) } elseif ($cover) { '<img src="{0}" alt="{1}" loading="lazy" decoding="async">' -f (Encode $cover), (Encode ($project.name + ' project preview')) } else { '' }
    if ($project.slug -eq 'sinstar') {
    @"
<article class="project-card"><div class="$coverClass">$coverHtml</div><div class="project-card-copy"><h2>$(Encode $project.name)</h2><p>$(Encode $project.description)</p><div class="project-card-actions" style="display:flex;flex-wrap:wrap;gap:.75rem 1rem"><a class="text-link" href="$(Encode $project.repository)">Github Repo <span aria-hidden="true">→</span></a><a class="text-link" href="../SinStar_Storyboard/">Storyboard <span aria-hidden="true">→</span></a><a class="text-link" href="https://sinstar.sincioco.com/BookOne">Audio Book <span aria-hidden="true">→</span></a></div></div></article>
"@
    } else {
    @"
<a class="project-card" href="$(Encode $project.repository)"><div class="$coverClass">$coverHtml</div><div class="project-card-copy"><h2>$(Encode $project.name)</h2><p>$(Encode $project.description)</p><span class="text-link">Github Repo <span aria-hidden="true">→</span></span></div></a>
"@
    }
}
$landing = @"
<main id="main" class="container projects-landing"><header class="page-hero"><p class="eyebrow">Ideas into working software</p><h1>Agentic AI Projects</h1><p class="lead">Explore my work in AI-assisted software development: business tools, iPhone and iPad apps, programming languages, and games.</p><p>I help teams in the United States and the Philippines build custom software using AI, with hands-on software engineering, human review, and testing. These six projects show the kinds of products and tools I build.</p><a class="text-link" href="../#custom-software-services">Software engineering and AI development services →</a></header><div class="project-grid">$($cards -join "`n")</div><section class="section-heading"><h2>Need a Custom Solution?</h2><p>Discuss a business application, an AI integration, or a workflow you want to automate. I bring C#/.NET, Azure, web and mobile experience to contract and part-time engagements in the U.S. and the Philippines.</p><p><a class="text-link" href="mailto:louiery@sincioco.com">Discuss your software project →</a> · <a href="../Resume/">Review my software engineering experience</a></p></section></main>
"@
WriteProjectPage 'Index.html' 'Agentic AI & Custom Software Projects | Louiery Sincioco' 'Explore AI-assisted projects by Louiery Sincioco: business tools, mobile apps and developer tools. Custom software for U.S. and Philippine teams.' $landing ''
$projectTitles = @{
    pmt = 'PMT Project Management Software'
    life2 = 'Life 2.0 Activity Tracker for iPhone & iPad'
    sinstar = 'Sin Star I Game Development'
    smile2 = 'SMILE 2.0 Programming Language & Game Engine'
    sinaiprompt = 'Sin AI Prompt Editor for Windows'
    smile1 = 'SMILE 1.0 Programming Language & IDE'
}
$sectionCount = 0
foreach ($project in $projects) {
    $markdown = Get-Content -LiteralPath (Join-Path $projectRoot "content/$($project.slug)/README.md") -Raw
    if ($project.slug -eq 'sinstar') { $markdown = Format-SinStarReadme -Markdown $markdown }
    if ($project.slug -eq 'sinaiprompt') { $markdown = $markdown -replace '(?ms)^## Run\r?\n.*?(?=^## |\z)', '' }
    if ($project.slug -eq 'life2') {
        $markdown = $markdown -replace '(?ms)^## (?:Run the project|Project structure)\r?\n.*?(?=^## |\z)', ''
        $markdown = $markdown -replace '(?m)^## Major features(?=\r?$)', '## Major Features'
        $markdown = $markdown -replace '(?m)^## On-device AI technology(?=\r?$)', '## On-Device AI Technology'
        $policy = Get-Content -LiteralPath (Join-Path $projectRoot 'content/life2/PRIVACY.md') -Raw
        if ([regex]::Matches($markdown, '(?m)^## License(?=\r?$)').Count -ne 1) { throw 'Life 2.0 License insertion point changed.' }
        $markdown = [regex]::Replace($markdown, '(?m)^## License(?=\r?$)', [Text.RegularExpressions.MatchEvaluator]{ param($match) $policy.TrimEnd() + "`n`n" + $match.Value })
    }
    $document = Convert-ProjectReadme $project $markdown $projectRoot
    $document.Html = $document.Html.Replace('louiery@gmail.com', 'louiery@sincioco.com')
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
    if ($project.slug -eq 'sinaiprompt') {
        $artwork = '<a href="{0}"><img class="project-screenshot" src="{0}" alt="{1}" width="1920" height="1032" decoding="async"></a>' -f (Encode $project.heroImage), (Encode $project.heroAlt)
    }
    $imageCredit = if ($project.slug -eq 'sinaiprompt') { '<p>Application screenshot supplied by Louiery Sincioco.</p>' } else { '' }
    $retrievedDate = if ($project.retrievedDate) { $project.retrievedDate } else { 'October 5, 2026' }
    $policyCredit = if ($project.slug -eq 'life2') { '<p>Privacy policy provided by Louiery Sincioco.</p>' } else { '' }
    $sourceUrl = "$($project.repository)/blob/$($project.commit)/$($project.readmePath)"
    $extra = if ($project.slug -eq 'smile2') { '<a class="text-link" href="../smile2/">Learn SMILE 2.0 →</a>' } elseif ($project.slug -eq 'sinstar') { '<a class="text-link" href="https://sinstar.sincioco.com/BookOne/">Read and listen to Sin Star: Book One</a>' } else { '' }
    $lead = $project.description
    if ($project.slug -eq 'life2') { $lead += ' Use the power of on-device AI to get encouragement and insights into your workouts!' }
    $content = @"
<div class="container project-layout">
  <aside class="project-sidebar"><details class="section-menu" open><summary>On this page</summary><nav class="section-nav" aria-label="$(Encode $project.name) sections"><a href="#project-overview" aria-current="location">Overview</a>$($navigation -join "`n")</nav></details><a class="project-repository" href="$($project.repository)">View repository ↗</a></aside>
  <main id="main" class="project-main"><header class="project-heading"><p class="eyebrow">Agentic AI Projects / $(Encode $project.name)</p><h1 id="project-overview">$(Encode $document.Title)</h1><p class="lead">$(Encode $lead)</p><div class="project-links"><a class="text-link" href="$($project.repository)">View on GitHub ↗</a>$extra</div>$artwork</header>
  <article class="project-content">$($document.Html)</article>
  <div class="project-source"><p>Content and repository images from the public <a href="$sourceUrl">$([Net.WebUtility]::HtmlEncode($project.name)) README</a>, retrieved $(Encode $retrievedDate). Repository snapshot <a href="$($project.repository)/commit/$($project.commit)">$($project.commit.Substring(0,7))</a>.</p>$imageCredit$policyCredit<a href="#project-overview">Back to top ↑</a></div></main>
</div>
"@
    WriteProjectPage "$($project.slug).html" ($projectTitles[$project.slug] + ' | Louiery Sincioco') $project.description $content $project.slug
}
$mapPath = Join-Path $siteRoot 'sitemap.xml'
$sitemap = Get-Content -LiteralPath $mapPath -Raw
$sitemap = $sitemap -replace '(?s)\s*<url><loc>https://sincioco.com/AgenticAI/.*?</url>', ''
$urls = @('<url><loc>https://sincioco.com/AgenticAI/</loc><lastmod>2026-10-05</lastmod></url>')
$urls += $order | ForEach-Object { "<url><loc>https://sincioco.com/AgenticAI/$_</loc><lastmod>2026-10-05</lastmod></url>" }
$sitemap = $sitemap.Replace('</urlset>', ($urls -join "`n  ") + "`n</urlset>")
Set-Content -LiteralPath $mapPath -Value $sitemap.TrimEnd() -Encoding utf8
& (Join-Path $siteRoot 'tools/Update-AssetVersions.ps1') -SiteRoot $siteRoot
Write-Output "Built 7 project pages with $sectionCount section links from local source snapshots."
