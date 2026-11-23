# Universal Portable Package Builder — r2 dual-engine integration candidate

**Two independent installer engines, one reusable Windows GitHub Action.** This is an additive update of the user-provided `Portable-Package-Builder` kit, not a replacement for the existing custom NSIS installer.

- **`custom-nsis` (DEFAULT):** the existing independent NSIS build with its own preservation/rollback design. Behavior and script are retained.
- **`official`:** downloads the **unaltered PortableApps.com Installer 3.9.24** from its official SourceForge distribution, checks SourceForge's published SHA-256, extracts its bundled compiler and invokes its *documented folder-argument auto-build mode* on a private copy of the application. The official tool generates the installer; this repo does **not** rename a custom NSIS output and call it official.
- **`both`:** builds both `.paf.exe` packages, with separate file names, checksums and provenance JSON. No naming conflicts.

**Status:** Static review/checks are available without Windows; the vendor's real compilation and silent-install behavior MUST be verified by running **Official PortableApps Installer - Windows CI Smoke Test** in GitHub Actions. No claims of a successful vendor build in this session. Also, “automatic, no-click compilation” is not the same as guaranteeing zero GUI windows. The original wizard source can display a progress page and errors. Do not pass `/S` to the **packaging wizard**: its input selection is initialized by page callbacks that `/S` may bypass. The **generated installer** is a different EXE and can use the normal NSIS `/S` switch for installation.

## 1. Upgrade your existing GitHub repository

1. Download the supplied r2 ZIP and extract it.
2. Open your **existing** `vhick/Portable-Package-Builder` checkout with GitHub Desktop. **Do not create a new repository.**
3. Copy r2 files into that checkout, including the hidden `.github` directory. Replace matching scripts while preserving your original history.
4. Commit using the included `GITHUB-DESKTOP-COMMIT.txt` and push to `main`.
5. On GitHub select **Actions → Universal Packager Self-Test → Run workflow** to verify the existing NSIS path.
6. Then select **Actions → Official PortableApps Installer - Windows CI Smoke Test → Run workflow** to test both engines from a tiny synthetic portable app and silently install the vendor-generated result. This is the decisive acceptance test.
7. **Only after both workflows pass**, create an immutable release/tag `v1.1.0`. Keep your tested `v1.0.0` tag untouched. In existing application builders switch to `@v1.1.0` only when you want to adopt the new mode.

## 2. Use both engines from an existing Windows build job

After your application's **existing** build, launcher compilation, icon creation, metadata checks and PortableApps staging:

```yaml
- name: Package both NSIS engines
  id: packaging
  uses: vhick/Portable-Package-Builder@v1.1.0
  with:
    source-dir: work/MyAppPortable
    output-dir: dist
    engine: both
    running-exe: 'App\MyApp\MyApp.exe'
    package-revision: r2
    timeout-seconds: '900'

- name: Show result paths
  shell: pwsh
  env:
    CUSTOM: ${{ steps.packaging.outputs.custom-installer-file }}
    OFFICIAL: ${{ steps.packaging.outputs.official-installer-file }}
  run: |
    Write-Host "Independent installer: $env:CUSTOM"
    Write-Host "Official-tool installer: $env:OFFICIAL"
```

Your existing `vhick/portable-release-publisher@v1.1.1` can publish `dist/*.zip;dist/*.paf.exe` to a **NEW release tag**, with a dry-run before live publishing. Both files are independently named: `MyAppPortable_1.2.3.4_custom-nsis-r2.paf.exe` and `MyAppPortable_1.2.3.4_official-r2.paf.exe`. ZIP outputs are left to the application-specific builder, as before.

Keep `engine: custom-nsis` to retain exactly one independent installer, or use `engine: official` to request only the vendor-generated installer. The legacy `installer-file` output points to the custom installer when `engine: both`, preserving compatibility; new `custom-installer-file` / `official-installer-file` outputs expose each separately.

## 3. Or package a verified ZIP from a previous release

The unchanged application builder can call the shared reusable workflow:

```
vhick/Portable-Package-Builder/.github/workflows/portable-paf-from-release.yml@v1.1.0
```

Pass the known release tag and exact ZIP filename, a **new** output release tag, `engine: both`, `running-exe` and `publish: false` initially. See `examples/caller-workflow.yml`. The existing release downloader verifies its SHA256SUMS manifest. With `publish: true`, it checks the destination release, produces both PAF files, runs your existing release publisher in dry-run and then actual mode. It does not replace an existing release.

## 4. Pinned, verified genuine official tool

Default upstream version: **3.9.24** (uploaded InstallerWizard.nsi also defines `FRIENDLYVER` 3.9.24).

Official distribution: https://sourceforge.net/projects/portableapps/files/PortableApps.com%20Installer/PortableApps.comInstaller_3.9.24.paf.exe/download

SourceForge's displayed SHA-256 (copied from the official file's download page):

```
7ef6e2758cb578843d767fb5fafdbde8bf872b84f0acd6e64f18afbb05c04f00
```

Both values appear in `action.yml`, the reusable workflow and smoke test. This intentionally **pins a known release** instead of following “latest” and silently changing your builds. Update *both* values from the official publisher when a new vendor version is released, then rerun Windows smoke tests. If SourceForge returns an HTML error/download page, the size/PE/SHA checks will stop the build instead of executing it.

The application data and official tool are kept separate: `build-official.ps1` checks the original input, excludes all `Data` from the temporary packaging copy, and cleans/changes files only in its work area. Source zip files are **not** needed at runtime; the verified official distribution contains its full NSIS engine/template. The uploaded source files were used for auditing, not added to an MIT-licensed repository.

## 5. AppInfo requirements for the official engine

Your application must have its own compiled `MyAppPortable.exe`, a valid `App/AppInfo/appinfo.ini`, a proper `appicon.ico`, an `App` folder and an `Other` folder. The official automatic generator requires these fields (not fabricated by the builder):

```ini
[Format]
Type=PortableApps.comFormat
Version=3.9
[Details]
Name=My App Portable
AppID=MyAppPortable
Publisher=Your Publisher
Homepage=example.org
Category=Utilities
Description=Portable application
Language=English
[Version]
DisplayVersion=1.2.3
PackageVersion=1.2.3.0
[License]
Shareable=true
OpenSource=true
Freeware=true
CommercialUse=true
[Control]
Start=MyAppPortable.exe
```

**Do not copy the sample license answers blindly.** Fill in truthful values based on the actual app's licensing. The example is illustrative, not a guarantee of rights to redistribute proprietary apps or use the PortableApps name/trademark. Use the latest official Format specification for more fields and `installer.ini` custom behavior.

## 6. Safety differences

The independent NSIS engine has custom staging/backup/rollback and explicit preservation of the installed `Data` folder. The official installer has **its own** install and upgrade behavior configured by official `installer.ini`; it does not inherit the custom NSIS rollback implementation. Never assume identical upgrade semantics. Both use the same validated portable source but independent installers. For real apps, test installation, upgrading with existing `Data`, old App cleanup and TraceGuard retention before production distribution.

The builder itself does not build the app executable, generate a launcher, sign installers, grant vendor publishing permission or certify your release as an official PortableApps.com release. “Official installer” here means **generated by the genuine, unmodified official PortableApps.com Installer tool**.

## 7. Sources and licensing

- Official packaging tool: https://portableapps.com/apps/development/portableapps.com_installer
- Official distribution: https://sourceforge.net/projects/portableapps/files/PortableApps.com%20Installer/
- Format specification 3.9: https://portableapps.com/development/portableapps.com_format
- Official source/launcher: https://github.com/PortableApps/Launcher
- Real installer configuration samples: https://github.com/PortableApps/AppConfigs
- Existing shared release publisher: https://github.com/vhick/portable-release-publisher

The MIT license of **this automation wrapper** does not apply to the downloaded PortableApps.com tools, original app binaries, or any bundled third-party code. Respect the vendor's GPL, their installer license/branding restrictions and each application's own distribution conditions.

See `docs/VALIDATION.md`, `docs/SECURITY-AND-UPGRADES.md`, and `docs/OFFICIAL-SOURCE-AUDIT.md`.
