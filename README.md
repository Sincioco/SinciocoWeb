# SinciocoWeb

Source and published static files for the Sincioco.com personal website.
The private GitHub repository is `Sincioco/SinciocoWeb`.

## Site structure

- `Index.html`, `Resume/`, and `Military/` contain the main personal-site pages.
- `CSS/site.css` owns the shared design, header, navigation, and footer.
- `Images/` and page-specific image folders hold local artwork and photographs.
- `Projects/` contains the Agentic AI Projects sub-site, six repository README
  snapshots, their local pictures, and its generation/validation scripts.
- `smile2/` contains the SMILE 2.0 learning site, content, source examples, and
  its generation/validation scripts.
- `sitemap.xml` and `robots.txt` describe the site's published routes.

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
pwsh -NoProfile -File .\Projects\tools\Build-Projects.ps1
pwsh -NoProfile -File .\smile2\tools\Check-Docs.ps1
pwsh -NoProfile -File .\Projects\tools\Check-Projects.ps1
```

Both checkers accept `-PreviewUrl http://localhost:8877` when a local server is
running. `Projects/tools/Test-ProjectBuild.ps1` is the focused regression check
for repeatable sitemap generation. See each sub-site's README for ownership,
source provenance, validation details, and cache-version updates.

Use Ctrl+F5 after changes during browser testing. The generators use local source
snapshots and installed PowerShell/Windows capabilities; they require no package
downloads. Publishing this repository does not deploy changes to the website.

## Working conventions

Keep changes focused in the existing owners. Do not add third-party dependencies.
All Codex-created commit subjects begin with `Sin and Codex: ` and include a
detailed explanation of the change and relevant validation.
