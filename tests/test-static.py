"""Fast portable-builder structure checks; stdlib only. Use before Windows acceptance."""
from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
a=(root/'action.yml').read_text()
n=(root/'nsis/community-installer.nsi').read_text()
src=(root/'scripts/build.ps1').read_text()
wf=(root/'.github/workflows/portable-paf-from-release.yml').read_text()
test=(root/'tests/test-installer.ps1').read_text()
assert 'using: composite' in a
assert 'custom-nsis' in a and 'official' in a
assert 'App\\*.*' in n and 'Other\\*.*' in n
assert not re.search(r'File\s+/r\s+.*\\Data\\',n,re.I)
assert not re.search(r'RMDir\s+/r\s+"?\$INSTDIR(?:\\Data)?\s',n,re.I)
assert '.__UPB_Backup' in n and 'Function Rollback' in n
assert 'IfFileExists "$INSTDIR\\${LAUNCHER_FILE}"' in n
assert 'IfFileExists "$INSTDIR\\Other"' in n
assert 'CreateDirectory "$INSTDIR\\Data"' in n
assert 'Assert-PE' in src and 'Assert-Archive' in src
assert 'portable-release-publisher@v1.1.1' in wf
assert wf.count("dry-run: 'true'")==1 and wf.count("dry-run: 'false'")==1
assert "prune: 'false'" in wf
assert 'Get-FileHash' in (root/'scripts/download-release.ps1').read_text()
assert 'App/Fixture/1.0.0.0' in test
assert 'Data/TraceGuard/empty/inner' in test
assert 'MakeInstaller $v3' in test
for path in root.rglob('*.ps1'):
    source=path.read_text()
    for found in re.findall(r'\$([A-Za-z_][A-Za-z_0-9]*):(?=[^A-Za-z0-9_])',source):
        if found.lower() not in ('env',):
            raise AssertionError(f'Possible PowerShell interpolation issue in {path}: ${found}:')
print('PASS: Static structure, Data exclusions, rollback hooks, publisher and test coverage')
