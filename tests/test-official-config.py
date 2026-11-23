"""PortableApps official config-generator unit tests, no Windows required."""
import importlib.util
import tempfile
from pathlib import Path

base=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('pacconfig',base/'scripts/generate-official-config.py')
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
upstream=base/'third_party/portableapps-installer-3.9.24/App/installer'

def verify(display, version, extra='', language='English', forbidden=False):
    with tempfile.TemporaryDirectory() as tmp:
        root=Path(tmp)/'FixturePortable'
        (root/'App/AppInfo').mkdir(parents=True)
        (root/'Other/Source').mkdir(parents=True)
        (root/'App/AppInfo/appinfo.ini').write_text(f'''[Format]\nType=PortableApps.comFormat\nVersion=3.9\n[Details]\nName=Fixture Portable\nAppID=FixturePortable\nLanguage={language}\n[Version]\nDisplayVersion={display}\nPackageVersion={version}\n[Control]\nStart=FixturePortable.exe\n''')
        (root/'Other/Source/installer.ini').write_text(extra)
        config=root/'Other/Source/PortableApps.comInstallerConfig.nsh'
        if forbidden:
            try:m.generate(root,upstream,config)
            except ValueError:return
            raise AssertionError('Unsupported feature silently accepted')
        m.generate(root,upstream,config)
        content=config.read_text(encoding='utf-16')
        assert f'!define VERSION "{version}"' in content
        assert f'!define FILENAME "FixturePortable_{display}_' in content or language=='Multilingual'
        assert '!define INSTALLERLANGUAGE "English"' in content or language=='Multilingual'
        return content

c1=verify('1.0.0','1.0.0.0','[MainDirectories]\nRemoveAppDirectory=true\n')
c2=verify('2.5.1','2.5.1.0','[DirectoriesToPreserve]\nPreserveDirectory1=App\\Fixture\\UserExtras\n')
assert c1!=c2
assert '!define PRESERVEDIRECTORY1 "App\\Fixture\\UserExtras"' in c2
verify('2.5.1','2.5.1.0','[OptionalComponents]\nOptionalComponents=true\n',forbidden=True)
verify('2.5.1','2.5.1.0','[DownloadFiles]\nDownloadURL=https://example.org/file.zip\n',forbidden=True)
verify('2.5.1','2.5.1.0','[FilesToRemove]\nRemoveFile1=Data\\profile\\secret.txt\n',forbidden=True)
cm=verify('2.5.1','2.5.1.0','[Languages]\nEnglish=true\nFilipino=true\n',language='Multilingual')
assert '!define USES_ENGLISH "true"' in cm
assert '!define USES_FILIPINO "true"' in cm
print('PASS: Official version auto-config, basic options, multilingual and explicit advanced/Data guards')
