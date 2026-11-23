# r3 validation boundaries

Static tests validate source paths, action inputs, custom NSIS preservation, fail-closed missing-source behavior, Data exclusions and publisher guardrails. No Windows runtime proof exists for the r3 official-source path.

- Existing custom NSIS engine passed the user's r2 Windows smoke test (confirmed from logs_122094582442.zip).
- r2 official engine failed during mirror download (confirmed in logs). No official compiler was invoked.
- r3 source-only engine cannot be end-to-end tested with the provided ZIPs because the separate official generated application installer template is missing.

Run the Windows integration workflow with an application-matched complete generated official source folder. Confirm a separately generated official PAF and validate install behavior before tagging a production release.
