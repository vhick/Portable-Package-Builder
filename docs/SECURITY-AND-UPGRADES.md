# Security and upgrades

The default custom-nsis packaging behavior is unchanged. All builds reject reparse points and forbid embedding the portable application's Data directory in the packaging stage.

The offline official-source engine never downloads or executes a PortableApps.com installer EXE. `makensis.exe` compiles the generated vendor application installer source in a private stage; outputs are integrity-checked and separately named. Compilation fails if required source is unavailable or unexpected macros appear. The vendor source version is controlled by the caller and its Git history; never auto-update compiler templates blindly during production builds.

`PortableApps.comInstaller.nsi`, `PortableApps.comInstallerConfig.nsh`, and any referenced support files must be complete and trust-reviewed. Generated output is not automatically signed or certified by PortableApps.com.

Preserve licensing and any existing `installer.ini` rules. Because generated config reflects app-specific installer settings, regenerate source when those settings change. Do not copy app private Data into a release.
