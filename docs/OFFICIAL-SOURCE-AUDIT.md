# Official source audit and non-interactive packaging design (r2)

## Uploaded sources inspected

- `PortableApps_Installer_Source.zip`: `Source/InstallerWizard.nsi` (UTF-16LE), version 3.9.24.0, and `.nsh` helper files. This is the packaging **wizard**, NOT the complete ready-to-run vendor tool and not the finished application's installer.
- `PortableApps_Launcher_Source.zip`: separate launcher source and manuals. The launcher handles application runtime portability and is **not** required just to package an existing compiled portable app.
- `PortableApps_NSIS_Source.zip`: NSIS-related app source/readme/custom-install template material, not the complete vendor `App/nsis` and `App/installer` binary/toolchain distribution.
- `Universal-Portable-Package-Builder-Kit-r1(1).zip`: existing independent NSIS action, experimental official script, reusable workflow and Windows self-tests. The r2 update preserves `nsis/community-installer.nsi` and default `custom-nsis` mode.

## Direct source evidence

In `InstallerWizard.nsi`, near lines 263–292, `.onInit` checks command line parameters via `${GetParameters}`. A nonempty string becomes `$strInstallAppDirectory`, `$bolSkipWelcomePage=true`, `$bolAutomaticCompile=true`.

Near lines 305–330, `OptionsPageShow` recognizes this mode, selects `App/AppInfo/appinfo.ini` and `installer.ini` and skips the selection page using `Abort`. In the installer `Section Main`, near lines 1344–1380, the wizard invokes its **bundled** `App/nsis/makensis.exe` against generated `Other/Source/PortableApps.comInstaller.nsi` (or plugin variant). Near lines 1456–1461 it automatically skips the successful final page.

**Crucial caveat:** This is an automated **wizard**, not a documented windowless CLI compiler. It still creates a progress page and may display a final error page if a required field is absent. Its `OptionsPageShow` sets fields required for later compilation; using NSIS `/S` when launching the *wizard* may skip those callbacks. Do not assume that `/S` is safe. Instead provide a single full folder path, check all required fields before starting, run with a watchdog, validate output, and preserve vendor logs. The finished PAF is its own installer and is tested separately with `/S /D=...`.

Near lines 187–205 and 596–740 the wizard reads key AppInfo fields. Required fields include Details Name/AppID and Version DisplayVersion/PackageVersion, with license truth values used for compliance. Near line 1355 the wizard can delete an existing output filename; near lines 1430–1452 it removes temporary injected source files, and optional components may be moved. That is why `build-official.ps1` **always makes an isolated copy**, prevents output collisions and does not allow the wizard to operate on the original application folder.

The bundled wizard's compiler log is expected under its `Data/PortableApps.comInstallerLog.txt` and copied to `official-compile.log`/`vendor-makensis.log` for failures. SourceForge's official download page displays the SHA256 hash for v3.9.24. Both hash and URL are pinned in this kit.

## What r2 intentionally does NOT do

- Modify or recompile PortableApps.comInstaller's official NSIS source and mislabel a fork as the unmodified tool.
- Bundle vendor executables in our MIT repository.
- Send the application source ZIP to a third-party build server beyond GitHub Actions/SourceForge.
- Inject `Data`, user profiles, TraceGuard backups or persistent caches into PAF payload.
- Override a valid old release tag or replace any installed application without user testing.
- Claim a fully windowless vendor packaging GUI until an actual Windows CI run establishes compatibility.
- Assume that successful official packaging gives official PortableApps.com certification, signing or redistribution rights.

## Official references

- https://github.com/PortableApps/Installer (repository mainly metadata; packaged tool includes runtime/template)
- https://github.com/PortableApps/Launcher
- https://portableapps.com/apps/development/portableapps.com_installer
- https://portableapps.com/manuals/PortableApps.comLauncher/ref/paf/installer.html
- https://portableapps.com/development/portableapps.com_format
- https://sourceforge.net/projects/portableapps/files/PortableApps.com%20Installer/PortableApps.comInstaller_3.9.24.paf.exe/download
