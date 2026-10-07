# Updating the public audiobook

The authoritative reader remains in the novel project's `web` folder. The separate
`SinStar_Audio_BookOne` repository contains its public deployment copy in `docs`.
GitHub Pages must use branch `main`, folder `/docs`. No deployment secret, Azure
credential, action workflow or paid runner is needed.

Run from PowerShell using this directory's `Update-BookOne.ps1`:

```powershell
.\Update-BookOne.ps1 -DryRun
.\Update-BookOne.ps1
.\Update-BookOne.ps1 -Check
```

The script copies only `bookone-public-files.json`, validates all 43 audio hashes,
chapter anchors and 3,048 cue targets, then swaps only the publication `docs`
directory. It never writes to the source, invokes Git, or contacts a server.
Host-specific canonical/OG/JSON-LD URLs and the derived service worker shell
version change for GitHub Pages. Runtime, text, illustrations and audio remain
the source's bytes. `.nojekyll` and a single-URL sitemap are added.

Review the reported diff. Publishing is a separate, explicit operation:

```powershell
git -C 'D:\My Documents - 2026\SinStar_Audio_BookOne' status --short
git -C 'D:\My Documents - 2026\SinStar_Audio_BookOne' add -- docs
git -C 'D:\My Documents - 2026\SinStar_Audio_BookOne' diff --cached --stat
git -C 'D:\My Documents - 2026\SinStar_Audio_BookOne' commit -m 'Sin and Codex: Update public audiobook reader'
git -C 'D:\My Documents - 2026\SinStar_Audio_BookOne' push origin main
```

Do not add private tooling, `.env`, production directories, original audio masters
or video files. A new source file requires an explicit allowlist review.

Every update retains the previous complete docs folder under the main site's
private `Deployment\book-publication\<backup-id>\previous`. Restore a previous
copy with `Update-BookOne.ps1 -Restore <backup-id>`; restoring also preserves the
current copy. Review and publish separately if that recovery should go live.
An interrupted operation leaves its prepared/recovery files for inspection. The
process-held lock releases automatically when the process ends; its small lock
file remains harmless. If a crash leaves `docs` absent, the next update identifies
the previous copy to restore. Every swap has a receipt written before it begins.

The reader remains online-capable if a browser denies offline storage. Saved
audio and reading position stay with their browser origin. Existing Azure data
does not move automatically to GitHub Pages, and mobile browsers may partition
the iframe separately from the direct reader. The Azure wrapper provides an
Open full reader link for standalone use.
