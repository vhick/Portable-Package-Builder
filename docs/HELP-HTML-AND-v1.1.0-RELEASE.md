# Official Installer HTML prerequisite and v1.1.0 release guide

## Which ZIP do I use?

- `Universal-Portable-Package-Builder-Kit-r1(1).zip` is the original OLD custom/installer-download design. Do not overwrite the current working `main` with it.
- The r4 source-based repository contains the complete bundled official 3.9.24 toolchain and modern action inputs.
- Apply the small r5 overlay to your existing r4-based repository; if starting fresh, the r5 FULL kit includes the verified r4 files plus the r5 HTML guard.
- The `help.html` belongs in **each application package folder** (e.g. `RufusPortable/help.html`), not in `Portable-Package-Builder/help.html`.

## Responsibilities

1. Application-specific builder: builds `RufusPortable/`, creates meaningful `help.html`, prepares appinfo.ini, launcher, application files, ZIP, and chooses `engine: official` or `custom-nsis`.
2. Shared Package Builder: validates root HTML for the official engine, compiles official or custom installer, emits `.paf.exe`, checksums, provenance.
3. Universal Release Publisher: publishes validated artifacts. No engine-specific code is needed there.

The official engine requires a usable HTML page such as:

```html
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Rufus Portable Help</title></head>
<body><h1>Rufus Portable</h1>
<p>Start Rufus using RufusPortable.exe. Keep your Data folder when upgrading.</p>
<p>Project documentation: <a href="https://rufus.ie/">rufus.ie</a></p>
</body></html>
```

This is a documentary example, not a file to copy into the shared builder. The application-specific builder should supply accurate text and links for that particular application. Do not overwrite a customized existing help.html.

## Beginner-friendly GitHub Desktop + tag procedure

1. Open your existing `vhick/Portable-Package-Builder` local repository in GitHub Desktop. **Fetch origin** and **Pull origin** if offered.
2. Extract the **r5 OVERLAY** ZIP, and copy its contents over the local repository root, preserving `.git`, `third_party`, and every file not supplied by the overlay. Never extract the old `r1` ZIP here.
3. Review changed files (new `docs/...` and changes to `scripts/build-official.ps1`, `tests/test-official.ps1`, `tests/test-static.py`, `.github/workflows/official-smoke-test.yml`, `README.md`).
4. Commit: `Preflight official root help.html and document v1.1.0 release (r5)`. Then **Push origin**.
5. In the repository's **Actions**, run **Universal Packager Self-Test** and **Official PortableApps 3.9.24 - Real Headless Build Smoke Test** again. Confirm both are green *on the new commit*.
6. Before marking a stable production release, validate a real official `.paf.exe` install and upgrade over an existing portable Data directory (compile success alone does not prove data safety).
7. Go to `https://github.com/vhick/Portable-Package-Builder/releases/new` and choose **Choose a tag** > enter `v1.1.0` > **Create new tag: v1.1.0 on publish**; target the tested `main` commit. Release title: `Universal Portable Package Builder v1.1.0`. Describe bundled official source, no installer EXE downloads, source-based headless NSIS, root HTML preflight, and previous custom engine compatibility.
8. Set **Pre-release** if you have not completed install-and-upgrade acceptance testing. Mark it stable/latest only when validated. Click **Publish release**.
9. Confirm the new `v1.1.0` exists. Only then update dependent application workflows from the temporary commit SHA/old tag to `vhick/Portable-Package-Builder@v1.1.0`, and rerun one application build.
10. Keep `v1.0.0` intact for rollback; do not force-move a tag. `@v1.1.0` in a caller is a GitHub Action reference to the **tagged repository commit**; it is not a field in `action.yml` and no filenames need to be renamed.

## Packaging input reminder

The shared action supports `engine: custom-nsis` (default), `engine: official` and `engine: both`. Your Rufus workflow can continue presenting ONLY the first two choices as requested.

```yaml
- name: Build selected installer
  uses: vhick/Portable-Package-Builder@v1.1.0
  with:
    source-dir: work/RufusPortable
    output-dir: dist
    engine: official
    package-revision: b1r5
```

The paths are illustrative. Preserve the real ones from the working Rufus workflow. Do not change to `@v1.1.0` until you have actually published that tag.

## Verification expectations

- r5 Python/static tests: can be run locally.
- r5 PowerShell source and compiled NSIS smoke test: must pass on Windows GitHub Actions.
- Real-application GUI installation and upgrade preserving user Data: independent acceptance requirement; do not conflate with successful NSIS compilation.
