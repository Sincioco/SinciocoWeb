# Updating the public storyboard

The authoritative authoring site remains in `D:\SMILE 2.0 - Sin Star I\Visual Script and Storyboard`.
The separate `SinStar_Storyboard` repository contains its public Pages copy in
`docs`. Configure GitHub Pages with branch `main`, folder `/docs`.

```powershell
.\Update-Storyboard.ps1 -DryRun
.\Update-Storyboard.ps1
.\Update-Storyboard.ps1 -Check
```

The fixed `storyboard-public-inputs.json` list includes the authored story/script,
their referenced web artwork and runtime assets. The generator never writes to
the source. It copies no local videos, production directories, raw render files,
credentials or authoring launchers. Review this allowlist explicitly when adding
new artwork or runtime files.

The public copy uses verified `uploaded` entries from the authoritative
`production/youtube-uploads.json` registry. Only IDs and public clip titles enter
the generated site. The full private registry is never copied. Pending takes are
marked unpublished and retain their illustration; their identities are never
replaced with a guessed YouTube video. After an upload is verified and recorded
through the source project's normal workflow, run this updater again.

Host-specific changes are limited to canonical metadata, hashed asset versions,
YouTube-first previews, YouTube film embeds, and a public searchable clip page.
The local editing/review player and video/audio masters remain unchanged. The
public clip page loads one YouTube player at a time and keeps a direct YouTube
link when browser autoplay or embedding is unavailable.

Publishing is a separate operation after reviewing the diff:

```powershell
git -C 'D:\My Documents - 2026\SinStar_Storyboard' status --short
git -C 'D:\My Documents - 2026\SinStar_Storyboard' add -- docs
git -C 'D:\My Documents - 2026\SinStar_Storyboard' diff --cached --stat
git -C 'D:\My Documents - 2026\SinStar_Storyboard' commit -m 'Sin and Codex: Update public storyboard site'
git -C 'D:\My Documents - 2026\SinStar_Storyboard' push origin main
```

Updates preserve the previous complete `docs` copy in the main site's private
`Deployment\storyboard-publication\<backup-id>\previous` folder. Restore with
`Update-Storyboard.ps1 -Restore <backup-id>`, review, then publish separately.
The updater shares the book publisher's bounded copy and process-held lock
implementation; keep `update_bookone.py` alongside `update_storyboard.py`.
It validates exact filenames, internal links/anchors and Pages size limits before
swapping only `docs`, while preserving `.git` and all other repository files.
