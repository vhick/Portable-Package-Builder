# Official source audit — extracted Installer 3.9.24

## Evidence and source distinction

Original `PortableApps_Installer_Source.zip` had `Other/Source/InstallerWizard.nsi` only (the *GUI generator*). The additional user-supplied `PortableApps.comInstaller_3.9.24.paf.zip` includes the missing **actual application installer template** `App/installer/PortableApps.comInstaller.nsi`, template config `PortableApps.comInstallerConfig.nsh`, 91+ translation and helper files, and the matching `App/nsis` compiler and plugins.

Vendor wizard `InstallerWizard.nsi` does the following: copies `App/installer/*` into the app's `Other/Source`, copies two header bitmaps from `App/default_bits`, appends many `!define ...` statements to the initially header-only config file based on `appinfo.ini` and `installer.ini`, and executes `App/nsis/makensis.exe` against the resulting template. It also mutates packaging files and may show interactive GUI. We replicate only the deterministic staging/config/compilation behavior in a staging copy, without executing the wizard binary.

## Official code retained

- `App/installer/PortableApps.comInstaller.nsi` — original unmodified source; copyright and GPL notices retained
- `App/installer/PortableApps.comInstallerConfig.nsh` — original license header, copied and appended with generated macros in stage
- `App/installer/*` — official languages, icon, BMP and NSIS helper files
- `App/default_bits/PortableApps.comInstallerHeader*.bmp` — explicit assets missing from `App/installer`, supplied by wizard during normal operation
- `App/nsis/*` — bundled compiler, libraries and plugins; intact to avoid mismatch with a future separately installed NSIS

Critical hashes checked at runtime against `UPSTREAM-MANIFEST.json` for integrity. No network request for official packaging sources or builder executable. No interactive UI process.

## Compatibility constraints

- Template asserts 3.9.24.0; **upstream version changes require review**, not blind substitution.
- `Other/Source/PortableApps.comInstallerCustom.nsh` is preserved in the isolated staged app, and USESCUSTOMCODE is defined if present.
- Advanced installer.ini sections not yet handled fail clearly.
- Installer-source inclusion is opt-in, via `[Source] IncludeInstallerSource=true`.
- Custom NSIS remains independent/default.
- The builder is not the official PortableApps.com organization; generated EXE uses their original installer template but is not certified/signed by them.
- Real GitHub Actions compiler smoke test is required before a release tag.

Official references: https://portableapps.com/apps/development/portableapps.com_installer ; https://github.com/PortableApps/Installer ; https://portableapps.com/development/portableapps.com_format
