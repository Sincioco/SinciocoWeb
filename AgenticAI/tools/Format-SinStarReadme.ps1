# Apply the site's selected town views without editing the pinned README snapshot.
function Format-SinStarReadme([string]$Markdown) {
    $sectionPattern = '(?ms)^## Towns, day and night\s*\r?\n.*?(?=^## |\z)'
    $sections = [regex]::Matches($Markdown, $sectionPattern)
    if ($sections.Count -ne 1) { throw 'Expected one Sin Star I town section in the source README.' }

    $rowPattern = '(?m)^\|\s*\*\*(?<name>[^\r\n]+?)\*\*\s*\|\s*!\[(?<dayAlt>[^\]]+)\]\((?<day>[^)]+)\)\s*\|\s*!\[(?<nightAlt>[^\]]+)\]\((?<night>[^)]+)\)\s*\|\s*$'
    $towns = [regex]::Matches($sections[0].Value, $rowPattern)
    if ($towns.Count -ne 17) { throw "Expected 17 paired town rows; found $($towns.Count). Review the source before updating the gallery." }
    $cards = foreach ($town in $towns) {
        $name = $town.Groups['name'].Value
        $view = if ($name -eq 'Neris Metropolis') { 'night' } else { 'day' }
        $src = [Net.WebUtility]::HtmlEncode($town.Groups[$view].Value)
        $alt = [Net.WebUtility]::HtmlEncode($town.Groups[$view + 'Alt'].Value)
        # One image and its name share a single cell, which becomes one gallery figure.
        '<tr><td><img src="{0}" alt="{1}"><br><strong>{2}</strong></td></tr>' -f $src, $alt, [Net.WebUtility]::HtmlEncode($name)
    }
    $replacement = @"
## Towns

All 17 permanent maps are accessible from **Maps & Towns**. Neris Metropolis is shown at night; the other towns use their authored day views in the shared Studio renderer.

<table>
$($cards -join "`n")
</table>

"@
    $section = $sections[0]
    return $Markdown.Substring(0, $section.Index) + $replacement + "`n" + $Markdown.Substring($section.Index + $section.Length)
}
