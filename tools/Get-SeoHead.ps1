# Shared build-time search/social metadata for generated static pages.
function Get-SeoHead {
    param(
        [string]$Title,
        [string]$Description,
        [string]$Url,
        [string]$Image,
        [string]$ImageAlt,
        [ValidateSet('WebPage', 'CollectionPage', 'TechArticle')][string]$PageType = 'WebPage',
        [array]$Breadcrumbs = @()
    )
    $page = [ordered]@{
        '@type' = $PageType
        '@id' = $Url + '#webpage'
        url = $Url
        name = $Title
        description = $Description
        inLanguage = 'en'
        isPartOf = @{ '@id' = 'https://sincioco.com/#website' }
        author = @{ '@type' = 'Person'; '@id' = 'https://sincioco.com/#louiery-sincioco'; name = 'Louiery Sincioco' }
        image = $Image
    }
    $graph = @($page)
    if ($Breadcrumbs.Count -gt 1) {
        $items = for ($i = 0; $i -lt $Breadcrumbs.Count; $i++) {
            [ordered]@{ '@type' = 'ListItem'; position = $i + 1; name = $Breadcrumbs[$i].name; item = $Breadcrumbs[$i].url }
        }
        if ($PageType -ne 'TechArticle') { $page.breadcrumb = @{ '@id' = $Url + '#breadcrumbs' } }
        $graph += [ordered]@{ '@type' = 'BreadcrumbList'; '@id' = $Url + '#breadcrumbs'; itemListElement = @($items) }
    }
    $json = [ordered]@{ '@context' = 'https://schema.org'; '@graph' = $graph } | ConvertTo-Json -Depth 12 -Compress -EscapeHandling EscapeHtml
    $safeTitle = [Net.WebUtility]::HtmlEncode($Title)
    $safeDescription = [Net.WebUtility]::HtmlEncode($Description)
    $safeUrl = [Net.WebUtility]::HtmlEncode($Url)
    $safeImage = [Net.WebUtility]::HtmlEncode($Image)
    $safeAlt = [Net.WebUtility]::HtmlEncode($ImageAlt)
    @"
  <title>$safeTitle</title>
  <meta name="description" content="$safeDescription">
  <link rel="canonical" href="$safeUrl">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Louiery Sincioco">
  <meta property="og:title" content="$safeTitle">
  <meta property="og:description" content="$safeDescription">
  <meta property="og:url" content="$safeUrl">
  <meta property="og:image" content="$safeImage">
  <meta property="og:image:alt" content="$safeAlt">
  <meta name="twitter:card" content="summary_large_image">
  <script type="application/ld+json">$json</script>
"@
}
