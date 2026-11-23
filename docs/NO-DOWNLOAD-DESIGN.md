# r4 no-download official source design

This file supersedes r3's missing-template/guard-only design. User provided the extracted PortableApps.com Installer 3.9.24 files, including the full vendor NSIS template/compiler and necessary bitmaps. The actual package build no longer needs to fetch `PortableApps.comInstaller*.paf.exe`, follow redirects, run the graphical wizard, or rely on SourceForge mirrors. Vendor source and toolchain are **bundled** and pinned to their reviewed hashes.

The `official-source-dir` input is now optional and should normally stay blank. If used, it must reference a **reviewed extracted vendor root** containing `App/installer`, `App/nsis` and `UPSTREAM-MANIFEST.json` for version 3.9.24.0; it does not take an application's `Other/Source` anymore. The source generator always creates the application-specific config itself, in an isolated copy.

The packaging tool's version does **not** automatically update; only the packaged application's version is dynamic. This protects CI stability and avoids pulling new untested vendor code.
