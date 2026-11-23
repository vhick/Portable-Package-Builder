# Universal Portable Package Builder — r4 (bundled genuine PortableApps.com Installer 3.9.24)

This candidate adds **direct, unattended compilation of the original PortableApps.com Installer 3.9.24 template** alongside the previously working independent NSIS package engine. Both can run within a Windows GitHub Actions job. The custom engine is still the default. Source archive supplied by repository author; no PortableApps.com Installer PAF is downloaded or executed in CI.

| `engine` | Produced output | Toolchain |
|---|---|---|
| `custom-nsis` (default) | Existing custom `.paf.exe` | NSIS provided on runner |
| `official` | Genuine vendor-template `.paf.exe` | Vendored PortableApps.com 3.9.24 source + bundled NSIS |
| `both` | Two separately named `.paf.exe` files and SHA-256 files | Both toolchains independently |

## New flow

1. Validate prepared `AppNamePortable` package and `appinfo.ini` (no source modification).
2. Copy it to a clean, private staging folder **without Data**.
3. Copy vendor `App/installer/*` and default wizard header bitmaps into the staged `Other/Source`.
4. Generate `PortableApps.comInstallerConfig.nsh` from the app's actual metadata and supported `installer.ini` keys.
5. Run `third_party/portableapps-installer-3.9.24/App/nsis/makensis.exe` **directly** on the unchanged official `.nsi` template. No wizard, GUI, user clicks, or installer download.
6. Verify output PE and 7-Zip archive, produce a unique output name, SHA-256 and provenance JSON.

## New GitHub Actions smoke test

Under **Actions → Official PortableApps 3.9.24 - Real Headless Build Smoke Test** click **Run workflow**. This test builds a synthetic fixture with *both* engines and checks the official payload and exclusion of private Data. It is a real compilation test, NOT an empty-source/guard-only green test. Existing **Universal Packager Self-Test** continues validating the custom engine's upgrade, rollback, and Data preservation.

### In another repository

```yaml
- uses: vhick/Portable-Package-Builder@YOUR_NEW_TESTED_TAG
  with:
    source-dir: work/MyAppPortable
    output-dir: dist
    engine: both
    package-revision: r4
```

The official build uses the bundled 3.9.24 source. Do not claim a new PortableApps installer version is included when only the *application* gets a new release; these two version numbers are independent.

## Version strategy

**Application upgrades** are automatic: `appinfo.ini` defines PackageVersion and DisplayVersion; the config is regenerated every time.

**PortableApps.com Installer upgrades** are deliberately reviewed: replace the vendored source/toolchain with verified files, update `UPSTREAM-MANIFEST.json` hashes and version gate after inspecting changes in the wizard/template, and rerun the full Windows smoke test. This avoids reliance on SourceForge's mirror redirects and prevents silent breakage from future changes. r4 does not pretend that upstream 3.9.25+ is automatically compatible.

## Supported official-package options

Basic single-application PortableApps.com Format installer, English or Multilingual, normal version metadata, EULA (`App/AppInfo/EULA.txt`), custom NSIS installer code in `Other/Source/PortableApps.comInstallerCustom.nsh`, source-inclusion flag, main directory replacement, running-app check and up to 10 preserved/removed paths via `installer.ini`. Unsupported advanced sections (online downloads, optional components, local file copies, legacy modes) **fail explicitly** rather than being silently omitted. For those use `custom-nsis` until a matching source generator is audited. An app's `Data` is never included in the new installer stage; the generated vendor installer creates Data at installation.

**Note:** The vendor installer uses its own interactive GUI when an end user opens the finished `.paf.exe` normally; only its *compilation* is fully unattended. The vendor's runtime silent-install conventions are separate from the build process and are NOT claimed to have been acceptance-tested in r4. The build does not trigger graphical UI.

## Security / attribution

The original official NSIS template, support files, bitmaps and bundled compiler come from the user's extracted PortableApps.com Installer 3.9.24. The original GPL headers are retained. Vendor licensing and trademark requirements apply; review distribution rights for every packaged app, particularly commercial applications. The official project states additional rules about commercial software. See `third_party/portableapps-installer-3.9.24/UPSTREAM-MANIFEST.json` for source archive provenance and reviewed critical file hashes.

## Status

This ZIP has local source and Python-generator/static checks, but **Windows NSIS compiler execution must be confirmed by the workflow** before tagging a production version. Do not assume a successful compile/runtime installation just from static checks.
