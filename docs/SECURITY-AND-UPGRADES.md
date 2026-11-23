# r4 security and upgrade policy

- Portable input `Data` is private. Do not copy it to the temporary build stage or install package. Check for reparse points before copying the portable app; use a fresh, isolated directory.
- The vendor official-source engine does not download any `PortableApps.comInstaller_*.paf.exe`, and does not execute its interactive installer wizard. It runs the bundled, SHA-256-reviewed `App/nsis/makensis.exe` directly to compile the vendor `PortableApps.comInstaller.nsi` source.
- The source generator reads the portable app's current version from `appinfo.ini`; it does not need updates when the packaged application version changes.
- The upstream installer/toolchain version is fixed to reviewed 3.9.24.0. Future official installer upgrades require an audited source snapshot, updated manifest hashes and Windows smoke validation; do not pull unreviewed `latest` releases automatically.
- Preserve legal notices and trademarks. Packaging a commercial application with the upstream PortableApps.com Installer can have licensing restrictions; check the official project policy.
- Keep `custom-nsis` default until the new official smoke test passes and a representative app has been verified on Windows. The two installer implementations have different upgrade and rollback behavior; only the custom NSIS engine has the previous automated rollback acceptance test.
- `installer.ini` advanced features not implemented by the source-only config generator are rejected rather than ignored or downgraded. Do not assume that an official-source-compiled installer is digitally signed or officially endorsed by PortableApps.com.
