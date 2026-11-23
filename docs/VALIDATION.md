# r4 validation and test boundaries

## Local validation

- `python tests/test-static.py`: builder structure, separate custom engine, offline vendor toolchain paths, Data safety and release publisher guardrails.
- `python tests/test-official-config.py`: real generation of the 3.9.24 `PortableApps.comInstallerConfig.nsh` for multiple application versions, supported preservation rules and multilingual mode; rejects unsupported online/optional-components and unsafe Data removal.
- YAML syntax and upstream SHA-256 manifest validation.

## Windows integration — required before publishing new builder release

1. Run Actions → **Official PortableApps 3.9.24 - Real Headless Build Smoke Test**.
2. Confirm log says `PASS: Original vendor 3.9.24 NSIS template compiled headlessly into genuine official PAF` and both custom+official results exist.
3. Confirm no hanging UI processes and no SourceForge/installer downloads; inspect `official-makensis.log` on failure.
4. Run **Universal Packager Self-Test** for custom installer upgrade, rollback and Data persistence.
5. Test an actual third-party application with its `installer.ini` options and manually inspect both installer outputs, and do a separate interactive installer/upgrade test before publishing broadly.

Windows compilation and runtime have **not** been executed in the local Linux validation environment. The new GitHub Actions smoke test executes them on Windows 2022; do not label r4 confirmed working before it passes. The smoke test compiles and inspects installer payloads; it is not an unattended installation or upgrade test for the official installer.
