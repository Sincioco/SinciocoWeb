# SinciocoWeb

Source and published static files for the Sincioco.com personal website.
The GitHub repository is `Sincioco/SinciocoWeb`.


## Current hosting and publication

The personal site uses the existing Azure Static Web App **sincioco-free**, on
the **Free** plan, with its primary HTTPS address at <https://sincioco.com>.
The approved custom-domain pair is `sincioco.com` and `www.sincioco.com`; the
`www` alias and certificate are managed in Azure and the existing DNS account.
Azure should use the apex as its default domain. Do not add a shared path-only
catch-all redirect, which would also match the apex and cause redirect loops.
Earlier dated audit notes below describe the previous IIS/App Service setup.

`SinStar/BookOne/` and `SinStar_Storyboard/` are small iframe pages with direct-open links.
The preferred audiobook address is <https://sincioco.com/SinStar/BookOne/>.
The single source `BookOne/index.html` serves both addresses through an exact
Azure rewrite at `/SinStar/BookOne/index.html`. Azure also matches that rule
for the folder with or without a slash, preserving the visible new address.
This avoids conflicting `SinStar` and `sinstar` directories on Windows while
keeping the old worker files and apex bookmarks. Both addresses preserve chapter fragments. The
retired `sinstar.sincioco.com` host requires its Azure binding and cannot serve
redirects after that binding is removed.
Their content is hosted by the public GitHub Pages repositories
[SinStar_Audio_BookOne](https://github.com/Sincioco/SinStar_Audio_BookOne) and
[SinStar_Storyboard](https://github.com/Sincioco/SinStar_Storyboard), each using
`main` and `/docs`. Old novel URLs are preserved by the reviewed Azure routes.
Reader position and downloaded audio belong to their browser origin; they do
not automatically transfer from Azure to GitHub Pages or between an iframe and
the standalone reader.

The `Deploy sincioco-free` workflow publishes reviewed pushes to `main`, or a
manual run on `main`, only while this repository is public and the repository
variable `AZURE_SINCIOCO_FREE_DEPLOY_ENABLED` equals `true`. It requires the
already-configured app-scoped Actions secret
`AZURE_STATIC_WEB_APPS_API_TOKEN_SINCIOCO_FREE`; never put its value in a file,
commit, command, or chat. Clearing the enable variable disables future runs.

The workflow uses standard Ubuntu runners, read-only GitHub permissions and
full-commit action pins. It performs no PR or preview deployment. It builds
only `.github/static-site/publish-files.json`, checks the complete prepared
payload and SEO, then uploads `.github/static-site/website` to the existing app.
Post-upload checks verify the expected Azure hostname, apex content,
redirects and SEO. They target the apex so a custom-domain binding transition
does not break publication; verify the `www` alias and certificate separately. A failed post-upload check can mean the upload already
happened; inspect the run before retrying. The official Azure action's pinned
Dockerfile still uses Microsoft's mutable native-client `stable` image.

For an offline preparation check using installed Python 3.12+ and PowerShell 7:

```powershell
python -B .github/static-site/test-ci.py
python -B .github/static-site/prepare-site.py
python -B .github/static-site/prepare-site.py --check
python -B .github/static-site/verify-stage.py
pwsh -NoProfile -File tools/Check-SEO.ps1
```

The existing private `Deployment/Deploy-Free-Site.ps1` remains the local manual
fallback. `Deployment/`, credentials, backups, generated payloads and diagnostics
are excluded from Git. Keep the approved public-file list, migration contract,
route config and shared validators synchronized between CI and that local flow
when changing publication boundaries. Git may normalize text line endings;
each flow verifies the exact bytes it prepares and uploads.

The book and storyboard updaters operate separately from Git publication:
see [audiobook update instructions](tools/README-BookOne.md) and
[storyboard update instructions](tools/README-Storyboard.md). They preserve
authoring sources and back up the previous public copy before replacement.
Azure retirement workers preserve existing audio caches and saved state while
retiring only the old reader shell after old tabs close normally.

## Site structure

- `Index.html`, `Resume/`, and `Military/` contain the main personal-site pages.
- `CSS/site.css` owns the shared design, header, navigation, and footer.
- `Images/` and page-specific image folders hold local artwork and photographs.
- `AgenticAI/` contains the Agentic AI Projects sub-site, six repository README
  snapshots, their local pictures, and its generation/validation scripts.
- `smile2/` contains the SMILE 2.0 learning site, content, source examples, and
  its generation/validation scripts.
- `sitemap.xml` and `robots.txt` describe the site's published routes.
- `tools/Get-SeoHead.ps1` owns shared search/social metadata, page JSON-LD, and
  breadcrumbs for both generated sub-sites. Parent-page metadata stays in its HTML.
- `tools/Check-SEO.ps1` validates metadata and indexability across sitemap routes.
- `tools/Update-AssetVersions.ps1` owns content-derived local asset URLs in the
  21 sitemap HTML pages; both sub-site builders run it after generation.
- `Web.config` owns HTTP cache policy; `tools/Test-AssetCaching.ps1` covers the
  reported stale-asset bug and optional served-header/conditional-response checks.

Generated HTML and required images/downloads are included so the website can be
served directly without a build service, package installation, or external asset
download. Keep them in sync with their source when editing either sub-site.

## Open locally

Open `Index.html` directly, or serve this folder using IIS or IIS Express.
No .NET recompilation is required for these static pages.
Use the HTTP/HTTPS website preview for the inline YouTube trailer; direct file
opening keeps a link to YouTube instead.

The tracked root `Web.config` supplies the IIS settings and static-file MIME
mappings. It contains no database connection strings, and a fresh checkout can
be served through IIS without copying a configuration template. The static site
does not use a database. Keep deployment credentials outside source control.

## Rebuild and verify

Run from the website root using the installed PowerShell 7:

```powershell
pwsh -NoProfile -File .\smile2\tools\Build-Docs.ps1
pwsh -NoProfile -File .\AgenticAI\tools\Build-Projects.ps1
pwsh -NoProfile -File .\smile2\tools\Check-Docs.ps1
pwsh -NoProfile -File .\AgenticAI\tools\Check-Projects.ps1
pwsh -NoProfile -File .\tools\Check-SEO.ps1
pwsh -NoProfile -File .\tools\Update-AssetVersions.ps1 -Check
```

All three checkers accept `-PreviewUrl http://localhost:8877` when a local server
is running. The SEO checker also verifies permanent redirects.
`AgenticAI/tools/Test-ProjectBuild.ps1` is the focused regression check
for repeatable sitemap generation. See each sub-site's README for ownership,
source provenance and validation details.

The generators use local source snapshots and installed PowerShell/Windows
capabilities; they require no package downloads. Main-branch pushes deploy through
the guarded Azure workflow described above when its enable variable is set.

## Asset caching â€” 2026-10-05

Asset versions are generated from the first 16 lowercase hexadecimal characters
of each file's SHA-256 hash. The updater covers local CSS, JavaScript, images,
favicons, and full-size image links in sitemap HTML, preserving other query
parameters and fragments. Changed bytes produce a new `v` value; timestamps alone
do not. The current site has 134 referenced local assets across 21 HTML pages.

Both page builders update versions automatically. After a standalone asset edit,
run the updater and its read-only check before publishing; no manual version bump
is needed. The focused regression uses temporary fixtures, with optional IIS checks:

```powershell
pwsh -NoProfile -File .\tools\Update-AssetVersions.ps1
pwsh -NoProfile -File .\tools\Update-AssetVersions.ps1 -Check
pwsh -NoProfile -File .\tools\Test-AssetCaching.ps1 -PreviewUrl http://localhost:8877
```

`Web.config` sets `Cache-Control: no-cache` for HTML and unversioned static resources,
allowing validator-based HTTP 304 responses. Known asset types requested with a
16-character hexadecimal `v` value receive `public, max-age=31536000, immutable`
on HTTP 200 and 304 responses. Publish the updated HTML, assets, and configuration
together. After the browser receives this policy, an ordinary reload checks for
new HTML and follows changed asset URLs; no hard-refresh workflow is required.
Already-open pages and browser-history snapshots still need an ordinary reload.
New server headers cannot retroactively evict HTML cached under the old policy.

The SMILE search index now uses stable JSON ordering with unchanged data. A focused
Calendar-image selector change preserves its full-width card with the version query.
Sin approved committing and pushing the cache work and image updates on 2026-10-05.
Public deployment remains separate; the Azure plan is unchanged.
No .NET recompilation or application restart is required; local IIS picked up the
configuration automatically.
The version updater is 54 lines and the regression script is 107 lines; the IIS
configuration grew by 12 lines. Both existing builders and the stylesheet kept
their line counts. This adds no browser runtime, package dependency, shared
mutable state, or file-size exception.

The first two relevant cache regression runs passed: content changes update versions,
unchanged inputs stay stable, `-Check` detects stale references without writing,
and query parameters, fragments, and excluded URLs are preserved. Local IIS checks
confirmed HTML returns `no-cache` on 200/304, including HTML with a version query;
versioned CSS/JavaScript/images return the immutable policy on 200/304, unversioned
assets return `no-cache`, and missing assets return 404 without immutable caching.
All 134 asset versions are current. SEO/project checks passed their 21-page scopes;
the SMILE checker passed 14 pages and 537 local links/assets. Browser review confirmed
the Life 2.0 Calendar card spans the full 842px gallery with no horizontal overflow
at a 1250px viewport. Retire the cache regression after ten consecutive relevant
successful runs under the global policy.

## SEO audit â€” 2026-10-05

Local changes describe software engineering, software architecture, custom software
developed with AI, and Agentic AI work for United States and Philippines teams.
Home now connects three service capabilities to project evidence and explains
human direction, code review, and testing. Resume and Agentic AI pages have
matching, focused introductions. Unique titles/descriptions, social metadata,
Person/ProfilePage/WebSite/Service data, and generated page/breadcrumb data reflect
visible content; no physical office, LocalBusiness address, or unsupported claim
was added. This SEO work adds no third-party packages and changes no CSS, JavaScript,
or image assets.

The live audit found the following before deployment of these local changes:

| Public route | Observed result |
| --- | --- |
| `http://sincioco.com/` | HTTP 200. |
| `https://sincioco.com/` and `https://www.sincioco.com/` | TLS certificate-name mismatch: the server presents an Azure wildcard certificate instead of a certificate valid for these custom hostnames. |
| `http://www.sincioco.com/` | Azure HTTP 404. |
| `http://sincioco.com/Projects/` and `http://sincioco.com/AgenticAI/` | Both return HTTP 200, leaving the old route as a duplicate. |

All 21 published sitemap routes also returned HTTP 200 on the live HTTP origin.
This confirms reachability of the current deployment, not publication of the local SEO edits.

Local canonical URLs, social URL fields, site URLs/IDs in structured data,
`sitemap.xml`, and the sitemap declaration in `robots.txt` now consistently use
`http://sincioco.com`, the currently working origin. No HTTP-to-HTTPS redirect is
enabled while the certificate is invalid. Once a valid certificate is confirmed,
migrate those references and redirects together. Keep canonical and sitemap
signals consistent with [Google's canonical URL guidance](https://developers.google.com/search/docs/crawling-indexing/consolidate-duplicate-urls).
The two service markets share English content; there are no duplicated country
pages or invented regional offices. See [Google's multiregional guidance](https://developers.google.com/search/docs/specialty/international/managing-multi-regional-sites)
before introducing distinct regional content.

Local validation passed for all 21 sitemap routes, metadata, JSON-LD, robots rules,
and HTTP responses. Three redirect cases passed with HTTP 301: the old Projects
landing, an old project page with its query string preserved, and an explicit
AgenticAI directory index. The existing 21-page project and 14-page SMILE checkers
also passed. Home/services, Resume, and the Agentic AI landing page were reviewed
at 390px and 1280px with no horizontal overflow. `git diff --check` passed.
The shared metadata helper is 51 physical lines and the SEO checker is 252 lines;
both have focused ownership and use only installed PowerShell/.NET capabilities.
The project builder grew from 102 to 122 lines; the documentation builder changed
from 116 to 115. Home grew from 92 to 138 lines and Resume from 414 to 436, mainly
for visible service copy and structured data. No file-size exception, runtime
dependency, or shared mutable browser state was introduced.
The local IIS rules consolidate `/Projects/` into `/AgenticAI/` and
explicit directory `Index.html` URLs into directory routes; their live behavior
still needs checking after deployment. This was not a Search Console performance
or Core Web Vitals audit, and it makes no ranking or indexing guarantee.

Sin approved committing and pushing these SEO changes on 2026-10-05. Public
deployment remains a separate step. The Azure App Service plan remains **D1**;
no accounts, DNS records, hosting plans, or hosting resources were changed.
After deployment approval, deploy the
reviewed files/configuration and verify the live routes, redirects, metadata,
certificate, robots file, and sitemap. Then verify the property in Google Search
Console and Bing Webmaster Tools through approved accounts and submit the sitemap.

Azure Static Web Apps Free is a future hosting option to evaluate against its
[official plans](https://learn.microsoft.com/en-us/azure/static-web-apps/plans)
and [quotas](https://learn.microsoft.com/en-us/azure/static-web-apps/quotas), including
this site's storage, bandwidth, and custom-domain needs. It has not been provisioned;
any migration, new account, DNS change, or plan change requires separate approval.

## Working conventions

Keep changes focused in the existing owners. Do not add third-party dependencies.
All Codex-created commit subjects begin with `Sin and Codex: ` and include a
detailed explanation of the change and relevant validation.
Sin authorized automatic commits and pushes after completed tasks on 2026-10-05.
Follow this workflow unless Sin gives a task-specific instruction to hold changes.
