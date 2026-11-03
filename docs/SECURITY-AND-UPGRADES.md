# Safety and migration design

## Explicit ownership boundary

This generic installer manages only the PortableApps app folder name, verified `AppID`, root launcher, `App` and `Other` directories. It cannot own unrelated Windows profiles or AppData. It never embeds or removes `Data`.

## Replacement and rollback

The installer refuses destinations with different AppID and nonempty unknown folders, checks the launcher and optionally configured application executable for exclusive access, and stages the complete new managed payload before beginning replacement.

All renames happen within the portable root, which keeps them on one volume. Previously managed content is moved to a reserved backup directory; a successful install removes that backup, and ordinary errors trigger rollback. Reparse/symlink input trees are rejected by the PowerShell preflight. The compiler itself never inserts data from existing app profiles into its payload.

Limits: NSIS is not a durable transaction database. Abrupt power failure, drive removal, antivirus/file locks, malicious symlinks already present in an old destination tree, or a disk with insufficient free space can interrupt cleanup and require manual intervention. Do not delete `.__UPB_Backup` without first checking whether the original `App`, `Other` or launcher need to be recovered. The installer refuses new upgrades when a reserved backup or stage exists.

## Existing user content outside Data

PortableApps Format usually treats `App` and `Other` as replaceable managed files. Some applications may store user-installed plugins in `App`. Such applications need an application-specific migration plan or a preserve directory rule before using this default replacement policy. Do not silently use this generic engine when existing user content is scattered across App or Other. Use the official Installer's preserve path options where suitable, or extend the shared engine with explicit supported preserve paths before adopting it.

## Registry and runtime traces

This packaging module does not add startup entries, registry redirection or user-profile migration. Those belong to each app launcher and its TraceGuard. Standalone apps may still create Windows traces (Recent Items, registry MRU, fonts, encryption keys); no blanket no-traces claim is made.

## Source and legal notices

- [PortableApps.com Format 3.9](https://portableapps.com/development/portableapps.com_format)
- [PortableApps.com Installer](https://portableapps.com/apps/development/portableapps.com_installer)
- [GitHub composite actions](https://docs.github.com/en/actions/tutorials/create-actions/create-a-composite-action)
- [GitHub reusable workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations)
- [NSIS Scripting Reference](https://nsis.sourceforge.io/Docs/Chapter4.html)

The repository source code is MIT licensed; this **does not grant redistribution rights** to upstream apps, their trademarks, the PortableApps.com marks, or the official PortableApps Installer. The NSIS compiler and runtime are third-party tools covered by their own licenses.
