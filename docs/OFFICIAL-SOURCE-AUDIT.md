# Source audit — r3 (2026-11-23)

## What failed in r2

`logs_122094582442.zip`: custom NSIS succeeded; official attempt failed immediately on a SourceForge HTML/redirect/mirror response, with `Vendor distribution download unexpectedly small`. `official-installer-diagnostics.zip` contains only the custom compiler log, not an official compilation log. Thus the old official engine was **never tested**.

## Uploaded ZIP inventory (directly checked)

- `PortableApps_Installer_Source.zip`: `Source/InstallerWizard.nsi` (PortableApps.com Installer wizard 3.9.24), `MoveFiles.nsh`, `ReadINIStrWithDefault.nsh`, `TBProgress.nsh`, bitmaps, license, readme. It is the *wizard source* and **does not include** `App/installer/PortableApps.comInstaller.nsi`, its generated `PortableApps.comInstallerConfig.nsh`, its language assets, or the actual NSIS plugin/toolchain directory.
- `PortableApps_NSIS_Source.zip`: `PortableApps.comInstallerCustom.nsh`, AppSource.txt, license/readme. It is an optional custom-code hook, **not the vendor installer template**.
- `PortableApps_Launcher_Source.zip`: separate launcher/generator source, which is not the installer engine.
- `Universal-Portable-Package-Builder-Kit-r1(1).zip`: custom NSIS builder and incomplete official download prototype.

## Direct source observations

`InstallerWizard.nsi`: `.onInit` lines 277–287 accepts a folder path to activate automatic mode; `OptionsPageShow` lines 310–329 configures source paths; Section Main lines 486–514 copies complete template from `$EXEDIR\App\installer\*.*` into an app's `Other\Source`, lines 543–547 writes generated config, and lines 1368–1379 invokes an NSIS compiler with that generated source. The missing `App\installer` template is crucial, not optional. In this mode the wizard is an automatic **GUI** generator, not a guaranteed windowless compiler. Avoid adding `/S` to its invocation.

## r3 design / honest boundary

- `custom-nsis` remains unchanged and operates without official source.
- `official` uses `makensis.exe` directly on a **complete generated official PortableApps.comInstaller.nsi + PortableApps.comInstallerConfig.nsh and all dependencies**, staged on a clean copy. It does not launch the wizard or fetch executable tools from PortableApps/SourceForge.
- `both` builds both separately; custom output can already exist if the official source is missing, and the overall job fails instead of falsely claiming success.
- Default `official-source-dir` empty means the portable application's `Other/Source` directory; optional override points to complete *generated* source for that exact app. Core source can be obtained through the full official tool's `App/installer` assets, but that is a distinct input the user has **not** uploaded. A raw `App/installer` template by itself is also not a generated per-app configuration.
- r3 regenerates known version/identity defines in the staged config (`VERSION`, `DISPLAYVERSION`, `APPID`, `PORTABLEAPPNAME`), but custom install options and other generator fields are NOT automatically regenerated. Changes outside these fields require regenerating complete source. If the vendor changes macros, r3 **fails closed** with `OFFICIAL_SOURCE_INCOMPATIBLE` rather than silently compiling an invalid package.
- The uploaded wizard source is included separately under `third_party/portableapps-installer-wizard-source/` for audit, not misrepresented as a complete template.
- A green guard-only smoke test is **not** proof of a successful official installer. Full integration requires `official-source-dir` and a Windows run.

## Source authenticity

Preserve the original NSIS vendor template, license, README and supporting files. Direct compiling generated official source does not grant signing or endorsement. Before distributing under any official naming convention ensure compliance with PortableApps licenses and format. Upstream source versions can be replaced without changing `build.ps1`; update and validate the source folder independently. No automatic "latest" promise can be made without a verified upstream source-code feed.
