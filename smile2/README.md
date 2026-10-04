# SMILE 2.0 documentation site

This static learning site lives at `/smile2/` inside Sincioco.com. Open `Index.html`
or serve the parent project in IIS/IIS Express. No .NET recompilation, application
restart, package installation, or production build step is required to serve it.

## Ownership and editing

- `content/*.json` owns lesson titles, descriptions, HTML bodies, and source links.
- `tools/Build-Docs.ps1` owns the shared documentation layout, lesson order,
  generated HTML pages, search index, and documentation sitemap entries.
- `../tools/Get-SeoHead.ps1` owns shared search/social metadata, page JSON-LD, and
  breadcrumbs; the documentation builder supplies each lesson's values.
- `docs.css` owns documentation layout and components. `../CSS/site.css` owns
  the existing Sincioco.com design tokens, header, navigation, and footer.
- `docs.js` owns only progressive enhancements: search, copy buttons, simple
  syntax coloring, the phone menu, tables, and the coordinate illustration.
- `examples/` owns downloadable teaching source and project files. Build outputs
  belong in a temporary validation folder, never in the published site.
- `data/api.json` records the 55 runtime function entries checked against the
  SMILE language catalog. The rendered reference is in `content/reference.json`.
- `images/` contains local screenshots and the official logo derivative. The
  landing coordinate diagram and lesson diagrams are native HTML/SVG.

Rebuild after changing lesson content or the shared layout, using PowerShell 7:

```powershell
pwsh -NoProfile -File .\smile2\tools\Build-Docs.ps1
pwsh -NoProfile -File .\smile2\tools\Check-Docs.ps1
pwsh -NoProfile -File .\tools\Check-SEO.ps1
```

Optional HTTP verification of every page against a running local site:

```powershell
pwsh -NoProfile -File .\smile2\tools\Check-Docs.ps1 -PreviewUrl http://localhost:8877
pwsh -NoProfile -File .\tools\Check-SEO.ps1 -PreviewUrl http://localhost:8877
```

The root SEO checker covers all 21 sitemap routes, metadata, JSON-LD, robots rules,
and permanent legacy/canonical redirects. See the [root SEO audit](../README.md#seo-audit--2026-10-05) for
the current HTTP-origin policy, live hosting findings, and approval/deployment steps.

The generator's version value controls cache-busting URLs. Update that value and
the three parent-page stylesheet URLs for a later CSS/JS release. Use Ctrl+F5 in
the browser after editing. Search works without a fetch request, including from
local files. Core lesson text, links, diagrams, and downloads remain usable when
JavaScript is disabled; interactive controls and search need JavaScript.

## Scope and provenance

The documentation was checked against `D:\SMILE 2.0` on September 25, 2026.
The source checkout's HEAD was `e97afe296f6866d97ad035c9a9b0c9596b919fe0`;
current working source was consulted as well. Each page lists its relevant
source files. Native Windows is the target for downloadable game/VFX samples.
No SMILE compiler, runtime, library, VSIX, or character asset was changed.

`images/star-collector.jpg` is a fresh capture of the native downloadable teaching
game. `images/snake.png` comes from the existing Snake tutorial. The Fire, Water,
and Earth screenshots come from `docs/images/readme/2026-09-24` in SMILE 2.0;
they show the complete native labs, which include character art and animation
beyond the standalone teaching examples. The logo uses the authorized
`assets/branding/smile-2.0-logo-web.png` derivative.

Advanced samples use assets from a local SMILE source checkout. The website does
not bundle large character models or licensed character art. The lesson explains
the project location, source library reference, and required effect assets.

## Integration

The shared top navigation places a decorative vertical separator after Military,
followed by Agentic AI Projects. The direct Smile 2.0 top-navigation link is hidden;
the language guide remains available from the SMILE 2.0 project page.
The local `Web.config` adds `.smile`, `.smileproj`, and `.ps1` download MIME types for IIS.
The existing parent application configuration is unchanged. Deploy the generated
site files along with the modified parent pages, shared stylesheet, and sitemap
when publishing Sincioco.com. This task prepares the local project; it does not
publish it to the public server.

The website is versioned in the private `Sincioco/SinciocoWeb` repository.
There are no third-party frontend libraries, remote fonts, analytics,
external build dependencies, or new runtime packages.

## Validation performed

- Generated all 11 documentation pages and 148 search entries. Checked all 14
  site pages (including Home, Resume, Military) for local targets, fragments,
  duplicate IDs, one main heading, image descriptions, and navigation order.
- Served the site with the installed IIS Express. Verified successful HTTP
  responses for every page and the source/project/helper download MIME types.
- Reviewed desktop and phone layouts in Chrome. Checked navigation, lesson
  menu, coordinate sliders, copy confirmation, API filtering, and search.
- Compiled 14 runnable teaching programs against the existing native compiler;
  five language examples and two console library examples produced their
  expected output. Checked 40 additional documentation code blocks with the
  real semantic analyzer and checked the overview drawing excerpt by compiling.
- Fire, Water, and Earth examples each completed 180 native smoke-test frames:
  initialization and final-frame status true, renderer error zero, and no live
  meshes, objects, textures, materials, or models after cleanup. The asset helper
  was exercised for all three effects in a temporary repository-shaped folder.
- Star Collector was opened and captured natively. Its complete keyboard/gameplay
  loop and advanced visual appearance are available for user testing; automated
  smoke checks are not a substitute for playing through every interaction.

The implementation adds focused documentation owners rather than changing the
language architecture. Parent-page changes are confined to navigation and cache
URLs, plus a small shared navigation stylesheet addition and sitemap entries.
No repository architecture guardrail exists in this website folder, and no
exception, baseline change, or dependency was introduced.


Final size: 59 files, approximately 1.82 MiB. The documentation styling is 186
lines, browser enhancements 149 lines, generator 116 lines, and link checker 47
lines. Shared site CSS ends at 236 lines (11 added navigation lines). No feature
algorithms were added to an application entry point. Final validation resolved
530 local links/assets and all 148 search destinations. All 11 documentation
pages passed Chrome desktop and narrow-phone horizontal-overflow checks.
