# Portable Package Builder — r3 Source-Only Dual Engine (candidate)

The existing custom NSIS builder is preserved. The new official-source branch does **not** download `PortableApps.comInstaller_*.paf.exe`, use SourceForge mirrors, or start an interactive wizard.

**Current limitation:** The original uploaded `PortableApps_Installer_Source.zip` contains only the packaging *wizard* sources. It does not contain the official *application installer template* (`PortableApps.comInstaller.nsi` and support files). The new `official` engine is only runnable with a complete **generated official app installer source tree**. It now fails fast with `OFFICIAL_SOURCE_MISSING` rather than failing on download or silently substituting custom NSIS.

## Engines

- `custom-nsis` **(default)**: your previously working independent NSIS builder.
- `official`: invokes NSIS directly on official **generated per-app** sources from `source-dir/Other/Source` or `official-source-dir`, with metadata refreshed on an isolated staging copy.
- `both`: builds distinct custom and official installer outputs; missing official sources cause a clear overall failure.

## Example GitHub Action

```yaml
- uses: vhick/Portable-Package-Builder@YOUR_NEW_TESTED_TAG
  with:
    source-dir: work/MyAppPortable
    output-dir: dist
    engine: both
    official-source-dir: work/MyAppPortable/Other/Source
    package-revision: r3
```

If you only want a reliable build **now**, keep `engine: custom-nsis`. For the genuine official source engine, see `docs/NO-DOWNLOAD-DESIGN.md` and `docs/OFFICIAL-SOURCE-AUDIT.md`.

## Tests

- `python tests/test-static.py` — offline structural checks.
- `.github/workflows/self-test.yml` — Windows custom NSIS upgrade and rollback tests.
- `.github/workflows/official-smoke-test.yml` — offline guard tests; full official source compilation requires complete generated source input and must be verified on Windows.

The included example reusable workflow checks out the shared builder **main** during pre-release testing. Pin that checkout to a verified tag before production publishing.

The uploaded vendor wizard sources are kept under `third_party` for GPL attribution and future review. They are **not** enough to compile a real official installer in unattended CI without the missing template and dependent source files.
