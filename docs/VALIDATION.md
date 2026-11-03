# Validation / acceptance checklist

## Static checks achievable outside Windows

- [ ] `action.yml` and all workflows parse as YAML.
- [ ] All referenced helper files exist.
- [ ] No Data input is embedded in the NSIS script.
- [ ] No broad uninstall of `$INSTDIR` or host profile directories.
- [ ] No automatic uploading of Actions artifacts.
- [ ] Publisher invoked with dry-run before final publishing.
- [ ] Official provenance distinct from independent NSIS.

## Windows synthetic self-test (must run in GitHub Actions)

Manual workflow `.github/workflows/self-test.yml` does:

1. PowerShell AST parsing of scripts.
2. NSIS installation if necessary.
3. Compile genuine minimal v1 and v2 installers with an original test icon.
4. Silent first installation.
5. Add `Data/profile/bookmarks.txt` and an empty `Data/TraceGuard/empty/inner` tree.
6. Upgrade to v2; assert old App/version directory gone and new files present, bookmarks SHA256 unchanged, empty trees exist, and temporary backup cleaned.
7. Compile an intentionally failing v3 installer; assert rollback to v2 and Data preservation.
8. Assert unrelated AppID destinations are refused.
9. Hold the launcher open exclusively and assert installer refuses the locked file.
10. Verify PE and 7z archive integrity.

These are synthetic tests. A successful synthetic test does **not** establish that Brave, OBS, or Thunderbird runtime behavior is portable or that a Windows Platform install succeeded.

## Manual real-application acceptance

- [ ] Install generated `.paf.exe` into a clean PortableApps directory with ordinary GUI.
- [ ] Check PortableApps Menu recognition and native launcher startup.
- [ ] Verify browser/app profile initialization and shutdown.
- [ ] Upgrade over a copy of an old package; old numbered App directories gone.
- [ ] Profile, TraceGuard, and empty directories preserved.
- [ ] Move installed portable folder and relaunch; user data still accessible.
- [ ] Confirm no app-wide installer side effects or unapproved registry writes.
- [ ] Check `Other` and custom App plugin folders against app-specific migration policies.
- [ ] Publish independently labeled result after verification.

## Status at delivery

The scripts and assets are provided for GitHub Actions testing. **No actual Windows NSIS compilation, installation, rollback, official PAF compilation, or publisher execution is claimed in this environment.**
