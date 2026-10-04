# Agentic AI Projects

This static sub-site is available at `/AgenticAI/`. The landing page presents six
projects in the requested order: PMT, Life 2.0, Sin Star I, SMILE 2.0, Sin AI Prompt,
and SMILE 1.0. Each project presents its public README on one HTML page with
the website-specific edits described below.
Its left navigation links to headings on that same page.

The shared top navigation uses Military, a vertical separator, then Agentic AI
Projects. The standalone Smile 2.0 top-navigation link is hidden; the SMILE 2.0
project tab and its language-guide link remain available.

## Ownership

- `content/<project>/README.md` is the unchanged public repository snapshot.
- `content/<project>/source.json` records its commit, image mapping, and description.
- `images/<project>/` holds original source pictures as separate local files.
- `tools/Convert-ProjectReadme.ps1` converts the snapshots into semantic HTML,
  replaces image paths, resolves source links, and extracts heading anchors.
- `tools/Build-Projects.ps1` owns the page shell, project order, and sitemap entries.
  It omits Sin AI Prompt's Run section and its navigation item, and uses the
  owner-supplied `images/sinaiprompt/sin-ai-prompt-editor.png` screenshot for the
  full-width introduction and social preview. Only the landing-page project card
  uses the supplied `images/sinaiprompt/sin-ai-prompt-thumbnail.png` artwork. The original
  `SinAIPrompt.png` logo and pinned README/source metadata remain unchanged.
- `../tools/Get-SeoHead.ps1` owns shared search/social metadata, page JSON-LD, and
  breadcrumbs; the builder supplies each page's content and identity.
- `../tools/Update-AssetVersions.ps1` runs at the end of generation and versions
  local assets by content hash across all sitemap pages. Root `Web.config` owns
  response caching; `../tools/Test-AssetCaching.ps1` covers the stale-asset regression.
- `projects.css` owns only this sub-site's layout. `../CSS/site.css` owns shared
  typography, colors, header, footer, and global navigation. Documentation details
  follow the existing `../smile2/docs.css` conventions.
- `projects.js` owns the responsive section menu and current-section indicator.
- `project-video.js` owns the Sin Star I trailer's inline YouTube player and hover
  playback. It requests audio on, pauses on mouse departure, and preserves normal
  player controls when the browser requires a click before audible playback.
- `tools/Format-SinStarReadme.ps1` curates the website's Towns gallery while keeping
  the upstream snapshot unchanged: one named image per town, daytime except for
  Neris Metropolis at night.
- `tools/Check-Projects.ps1` validates the generated pages and shared navigation.

No new package, frontend library, server runtime, or external build download is
required. Generation uses the existing PowerShell 7 `ConvertFrom-Markdown` cmdlet
and Windows image APIs. Published pages use local CSS, JavaScript, and images.
The Sin Star I trailer loads YouTube's embedded player and official IFrame API.
Inline playback needs HTTP/HTTPS (including the local IIS preview); direct file
opening retains a full-width thumbnail linking to YouTube. Browsers can require
a click before allowing playback with sound; the site never falls back to mute.

## Build and validate

From the website root, using the installed PowerShell 7:

```powershell
pwsh -NoProfile -File .\AgenticAI\tools\Build-Projects.ps1
pwsh -NoProfile -File .\AgenticAI\tools\Check-Projects.ps1
pwsh -NoProfile -File .\smile2\tools\Check-Docs.ps1
pwsh -NoProfile -File .\tools\Check-SEO.ps1
pwsh -NoProfile -File .\tools\Update-AssetVersions.ps1 -Check
pwsh -NoProfile -File .\AgenticAI\tools\Test-ProjectBuild.ps1
pwsh -NoProfile -File .\AgenticAI\tools\Test-SinStarTowns.ps1
```

With an IIS/IIS Express preview running, add `-PreviewUrl http://localhost:8877`
to the checkers to verify the served pages too. The root SEO checker covers all
21 sitemap routes and permanent redirects; see the [root SEO audit](../README.md#seo-audit--2026-10-05) for
the live hosting findings and current HTTP-origin policy. The site needs no .NET build.
The existing SMILE documentation generator also includes the new global link;
rebuilding it will retain the navigation. Each generator preserves the other
sub-site's sitemap entries.

The checked-in HTML is generated output. Edit the corresponding source or builder
and rebuild. Image-gallery tables are restyled as responsive figures; source
styles, widths, and alignment are discarded. Image dimensions are read locally
to reserve space before lazy loading. Existing source links to other repository
documents remain links to their pinned GitHub versions.

When refreshing source content, replace snapshots deliberately, update the exact
commit and image mappings, and rerun validation. The builder works offline and
does not silently refresh from GitHub. Asset versions are automatic; after editing
an asset without rebuilding, run `tools/Update-AssetVersions.ps1` from the website
root, then use `-Check` before publishing. See [asset caching](../README.md#asset-caching--2026-10-05)
for the HTTP policy and regression command. Use an ordinary reload after the new
policy is received; already-open pages and history snapshots still need reloading.
The Calendar gallery selector retains its full-width layout with versioned image URLs.
The first two cache regression runs and local IIS cache-header checks passed; all 134
site asset versions are current. Browser review confirmed the Calendar card and
gallery both measure 842px, with no horizontal overflow at a 1250px viewport.

## Imported sources — October 5, 2026

| Project | Repository | Commit | Local images |
| --- | --- | --- | --- |
| PMT | Sincioco/PMT | ec73ff3ad9a371deedcdc23ca32d5988c2336b6c | 13 |
| Life 2.0 | Sincioco/life2 | 4cee5ac2ff15432086f42ec506581e93096cd7d6 | 7 |
| Sin Star I | Sincioco/SinStarI | 097f52ff30f032c1b30dd13812d9215cc760532b | 58 |
| SMILE 2.0 | Sincioco/SMILE-2.0 | 61cc9253d29a17ed264eb416e912c648b0a5d845 | 17 |
| Sin AI Prompt | Sincioco/SinAIPrompt | 5c706172621dddd69dc2a6e2f5a271753a7ba19f | 1 |
| SMILE 1.0 | Sincioco/SMILE | 32dc0fef51e42c75722b10c6b6cbe43b64f7df83 | 5 |

The 100 README image references remain in the source snapshots; the Sin Star I
website gallery displays only the 17 selected town images. Sin AI Prompt has no inline README
images; its one supplemental image is the application artwork referenced by the
README. All 101 image files were decoded or parsed successfully. No videos were
downloaded. The original README snapshots retain their source license notices.

## Validation and limits

The site checker verifies 21 HTML pages, the six project tabs, same-page sidebar
destinations, local links and images, unique IDs, image descriptions, and main
navigation order. The existing SMILE checker verifies its 14-page scope.
Both also passed HTTP checks against the local IIS Express preview. Repository
review found all 79 rewritten pinned GitHub link targets in their commit trees,
and confirmed preservation of source text and image references.

The browser review covered all six project pages at 390px and 1440px widths,
with no horizontal page overflow or broken loaded images. Mobile menu behavior
and same-page section positioning were exercised. Source images are lazy-loaded;
the image checker also verifies their local existence independently of scrolling.

Handwritten PowerShell, CSS, and JavaScript files receive physical-line review
warnings above 500 lines and failures above 800. Source snapshots, images, and
generated HTML are explicitly excluded from that code measurement. Coupling,
state ownership, and semantic correctness were reviewed manually; the checker
does not claim to enforce them. No size exception or legacy baseline was added.

New handwritten files range from 22 to 138 lines. Shared CSS grew from 236 to 247
lines for wrapping navigation; the existing documentation generator and checker
retain their previous line counts. The build regression checks sitemap stability
and retention of all 21 entries after repeated builds of either sub-site. It
covers a newline-growth bug found during this task. Its first five relevant runs passed;
retire it after ten consecutive relevant successful runs under the global policy.

The Towns regression covers the original table's separated name-only cards. It
checks all 17 named cards and each selected day/night image; its first two relevant
runs passed. Retire it after ten consecutive relevant successful runs. The trailer
was checked at 842px desktop and 335px mobile content widths. In the browser, the
first audible hover request was blocked; after selecting Play, leaving paused
playback and hovering resumed it with `muted=false`. No silent fallback is used.

The Sin AI Prompt presentation update removes Run before section navigation is
generated and uses the owner-supplied editor screenshot without changing the
imported README, source metadata, or original logo. The existing builder owns
these presentation choices; it grew from 122 to 133 physical lines and project
CSS from 108 to 109. No new dependencies or size exceptions were introduced.
The project, SEO, and asset-version checks passed. Desktop and 390px browser
checks confirmed the screenshot loads responsively and Run is absent from both
the content and navigation.

The work is prepared locally and has not been deployed to the public server.
The website is versioned in the private `Sincioco/SinciocoWeb` repository.
