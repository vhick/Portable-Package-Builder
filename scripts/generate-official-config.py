#!/usr/bin/env python3
"""Generate 3.9.24 vendor installer config for direct, non-GUI NSIS compilation.

This is an integration wrapper, not a replacement for upstream template. It
fails closed on unsupported vendor installer.ini features rather than silently
losing functionality. No network or subprocess operations.
"""
import argparse
import configparser
import re
from pathlib import Path


def read_ini(path):
    cfg = configparser.ConfigParser(interpolation=None, strict=True)
    cfg.optionxform = str.lower
    if path.is_file():
        with path.open('r', encoding='utf-8-sig') as f:
            cfg.read_file(f)
    return cfg


def g(cfg, sect, key, default=''):
    return cfg.get(sect, key, fallback=default).strip()


def safe_define(name, val):
    val = str(val)
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*', name):
        raise ValueError(f'Unsafe configuration define: {name}')
    if any(c in val for c in ('"', '$', '`', '\n', '\r')) or '${' in val:
        raise ValueError(f'Unsupported special character in {name} (NSIS injection protection)')
    return f'!define {name} "{val}"'


def bool_value(val, name):
    if val.lower() not in ('true', 'false'):
        raise ValueError(f'{name}: expected true or false, got {val!r}')
    return val.lower() == 'true'


def relative_path(value, section, key):
    if not value or value.startswith(('/', '\\')) or ':' in value or '..' in value.replace('\\', '/').split('/'):
        raise ValueError(f'{section}.{key}: expected a safe relative path')
    if any(c in value for c in ('"','$','`','\n','\r','*','?','<','>','|')):
        raise ValueError(f'{section}.{key}: unsafe path character')
    if value.replace('\\', '/').lower().split('/')[0] == 'data':
        raise ValueError(f'{section}.{key}: refusing to remove or overwrite the user Data folder')
    return value


def generate(root, template_dir, dest):
    app = read_ini(root/'App/AppInfo/appinfo.ini')
    inst_path = root/'Other/Source/installer.ini'
    inst = read_ini(inst_path)
    if not (root/'App/AppInfo/appinfo.ini').is_file():
        raise ValueError('Missing App/AppInfo/appinfo.ini')
    if g(app,'Format','Type') != 'PortableApps.comFormat':
        raise ValueError('Official compilation requires PortableApps.comFormat')
    required = [('Details','Name'),('Details','AppID'),('Version','PackageVersion'),('Version','DisplayVersion'),('Control','Start')]
    for sect,key in required:
        if not g(app,sect,key):
            raise ValueError(f'appinfo.ini missing required {sect}.{key}')
    name = g(app,'Details','Name')
    appid = g(app,'Details','AppID')
    version = g(app,'Version','PackageVersion')
    display = g(app,'Version','DisplayVersion')
    language = g(app,'Details','Language','English') or 'English'
    if not re.fullmatch(r'\d+\.\d+\.\d+\.\d+',version):
        raise ValueError('PackageVersion must have four numeric components')
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_.+\-]{1,90}',appid):
        raise ValueError('AppID contains unsupported characters')
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9 ._()+\-]{1,120}',name):
        raise ValueError('App name contains unsupported characters')
    if not re.fullmatch(r'[0-9A-Za-z ._+\-]+', display):
        raise ValueError('DisplayVersion contains unsupported filename characters')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+\.exe',g(app,'Control','Start')):
        raise ValueError('Control.Start must be a root .exe')
    # Explicitly reject sections that the wizard implements with stateful
    # filesystem moves, network downloads or plugins. Never ignore them.
    unsupported={'OptionalComponents', 'DownloadFiles', 'LegacyVersions', 'CopyLocalFiles'}
    for section in inst.sections():
        if section.casefold() in {x.casefold() for x in unsupported}:
            entries=[(key,val) for key,val in inst.items(section) if val.strip() and val.strip().lower() not in ('false','0')]
            if entries:
                raise ValueError(f'OFFICIAL_CONFIG_UNSUPPORTED: [{section}] has advanced wizard-only functionality. Use custom-nsis for this package until adapted.')
    known={
        'Source':{'includeinstallersource'},
        'CheckRunning':{'closeexe','closename'},
        'MainDirectories':{'removeappdirectory','removeotherdirectory'},
        'Languages':None,
        'DirectoriesToPreserve':{f'preservedirectory{i}' for i in range(1,11)},
        'DirectoriesToRemove':{f'removedirectory{i}' for i in range(1,11)},
        'FilesToPreserve':{f'preservefile{i}' for i in range(1,11)},
        'FilesToRemove':{f'removefile{i}' for i in range(1,11)},
    }
    for section in inst.sections():
        if section.casefold() in {s.casefold() for s in unsupported}:
            continue
        actual=next((k for k in known if k.casefold()==section.casefold()),None)
        if actual is None:
            raise ValueError(f'OFFICIAL_CONFIG_UNSUPPORTED: [{section}] section unknown; not silently ignored')
        if known[actual] is not None:
            extra=set(k.lower() for k,_ in inst.items(section))-known[actual]
            if extra:
                raise ValueError(f'OFFICIAL_CONFIG_UNSUPPORTED: [{section}] unsupported keys: {sorted(extra)}')
    all_languages=re.findall(r'^\s*\$\{IncludeLang\}\s+([A-Za-z0-9]+)',(template_dir/'PortableApps.comInstaller.nsi').read_text(encoding='utf-16'),flags=re.M)
    if not all_languages or 'English' not in all_languages:
        raise ValueError('OFFICIAL_SOURCE_INCOMPATIBLE: Cannot parse supported installer languages from 3.9.24 source')
    selected=set()
    if language.lower()=='multilingual':
        # Same default as the upstream wizard: if [Languages].English is not
        # explicitly specified, enable all languages. Otherwise honor true keys.
        english_setting=g(inst,'Languages','English')
        if not english_setting:
            selected=set(x.lower() for x in all_languages)
        else:
            for key,val in inst.items('Languages'):
                if key.lower() not in {x.lower() for x in all_languages}:
                    raise ValueError(f'Unsupported language in [Languages]: {key}')
                if bool_value(val,f'Languages.{key}'):
                    selected.add(key.lower())
            selected.add('english')  # required by upstream language fallback
    else:
        found=next((x for x in all_languages if x.lower()==language.lower()),None)
        if found is None:
            raise ValueError(f'Unsupported app language in official 3.9.24: {language}')
        language=found
    filename=appid+'_'+display+('_'+language if language.lower()!='multilingual' else '')
    filename=re.sub(r'\s+','_',filename)
    filename=filename.replace('+','Plus').replace('(','').replace(')','').replace('[','').replace(']','')
    if not re.fullmatch(r'[A-Za-z0-9_.\-]+',filename):
        raise ValueError('Generated installer filename is unsafe')
    out={
        'PORTABLEAPPNAME':name,
        'PORTABLEAPPNAMEDOUBLEDAMPERSANDS':name.replace('&','&&'),
        'APPID':appid,
        'VERSION':version,
        'DISPLAYVERSION':display,
        'FILENAME':filename,
        'REQUIRESADMIN':g(app,'Dependencies','RequiresAdmin','no'),
        'FINISHPAGERUN':g(app,'Control','Start'),
        'CHECKRUNNING':g(inst,'CheckRunning','CloseEXE',g(app,'Control','Start')),
        'CLOSENAME':g(inst,'CheckRunning','CloseName',name),
        'ADDONSDIRECTORYPRESERVE':g(app,'SpecialPaths','Plugins','NONE'),
        'INSTALLERCOMMENTS':'For additional details, visit PortableApps.com',
        'INSTALLERADDITIONALTRADEMARKS': (g(app,'Details','Trademarks')+'. ' if g(app,'Details','Trademarks') else ''),
    }
    if language.lower()=='multilingual':
        out['INSTALLERMULTILINGUAL']='true'
        for lang in all_languages:
            if lang.lower() in selected:out['USES_'+lang.upper()]='true'
    else:
        out['INSTALLERLANGUAGE']=language
    for sec,key,define,default in [('MainDirectories','RemoveAppDirectory','REMOVEAPPDIRECTORY','true'),('MainDirectories','RemoveOtherDirectory','REMOVEOTHERDIRECTORY','true')]:
        if bool_value(g(inst,sec,key,default),f'{sec}.{key}'):
            out[define]='true'
    if bool_value(g(inst,'Source','IncludeInstallerSource','false'),'Source.IncludeInstallerSource'):
        out['INCLUDEINSTALLERSOURCE']='true'
    for section,keyprefix,defprefix in [
        ('DirectoriesToPreserve','PreserveDirectory','PRESERVEDIRECTORY'),
        ('DirectoriesToRemove','RemoveDirectory','REMOVEDIRECTORY'),
        ('FilesToPreserve','PreserveFile','PRESERVEFILE'),
        ('FilesToRemove','RemoveFile','REMOVEFILE')]:
        for i in range(1,11):
            val=g(inst,section,keyprefix+str(i))
            if val:out[defprefix+str(i)]=relative_path(val,section,keyprefix+str(i))
    custom=dest.parent/'PortableApps.comInstallerCustom.nsh'
    if custom.exists():out['USESCUSTOMCODE']='true'
    eula=root/'App/AppInfo/EULA.txt'
    if eula.exists():out['LICENSEAGREEMENT']='eula.txt'
    elif (root/'Other/Source/EULA.txt').exists():
        # Stage-only migration, as performed by the upstream wizard.
        staged_eula=dest.parent.parent.parent/'App/AppInfo/EULA.txt'
        staged_eula.parent.mkdir(parents=True,exist_ok=True)
        staged_eula.write_bytes((root/'Other/Source/EULA.txt').read_bytes())
        out['LICENSEAGREEMENT']='eula.txt'
    eula_version=g(app,'License','EULAVersion')
    if eula_version:
        if not re.fullmatch(r'\d+',eula_version):raise ValueError('License.EULAVersion must be numeric')
        out['EULAVERSION']=eula_version
    # The bundled Config.nsh is a header; upstream wizard appends these defines.
    source=template_dir/'PortableApps.comInstallerConfig.nsh'
    if not source.is_file():raise ValueError('Missing upstream installer Config.nsh')
    raw=source.read_text(encoding='utf-16')
    dest.write_text(raw+'\r\n;Generated offline from appinfo.ini and supported installer.ini keys\r\n'+'\r\n'.join(safe_define(k,v) for k,v in out.items())+'\r\n',encoding='utf-16')
    print(f'Generated official NSIS config: {appid} {version} ({language}) with {len(out)} defines')
    print(f'Upstream output filename: {filename}.paf.exe')

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--app',type=Path,required=True)
    parser.add_argument('--template-dir',type=Path,required=True)
    parser.add_argument('--dest',type=Path,required=True)
    args=parser.parse_args()
    try:generate(args.app.resolve(),args.template_dir.resolve(),args.dest.resolve())
    except Exception as e:
        parser.exit(2, f'{type(e).__name__}: {e}\n')
