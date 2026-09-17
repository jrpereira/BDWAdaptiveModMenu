"""Build a deterministic, allowlisted mod archive; never package local config."""
import argparse
import hashlib
import re
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
MODULE = "ModMenuDecorator"

def version(root=ROOT):
    text = (root / 'Scripts/main.lua').read_text(encoding='utf-8-sig')
    match = re.search(r"local VERSION\s*=\s*['\"](\d+\.\d+\.\d+)['\"]", text)
    if not match:
        raise ValueError('Missing semantic VERSION in Scripts/main.lua')
    value = match[1]
    if MODULE == 'ExtendedControls':
        metadata = (root / 'mod_settings.ini').read_text(encoding='utf-8-sig')
        declared = re.search(r'^Version\s*=\s*(\S+)', metadata, re.M)
        if not declared or declared[1] != value:
            raise ValueError('Metadata and Lua version disagree')
    return value

def build(root=ROOT, out=None, expected=None):
    release_version = version(root)
    if expected is not None and expected != release_version:
        raise ValueError('Release branch version does not match source version')
    out = out or root / 'dist'
    out.mkdir(parents=True, exist_ok=True)
    entries = {f'{MODULE}/{p.relative_to(root).as_posix()}': p for p in (root / 'Scripts').glob('*.lua')}
    for name in ['enabled.txt', 'README.md']:
        entries[f'{MODULE}/{name}'] = root / name
    if MODULE == 'ExtendedControls':
        entries[f'{MODULE}/mod_settings.ini'] = root / 'mod_settings.ini'
        entries[f'{MODULE}/config.example.ini'] = root / 'distribution/config.ini'
        entries['tools/Migrate-ShowBothWheels.ps1'] = root / 'tools/Migrate-ShowBothWheels.ps1'
    archive = out / f'{MODULE}-v{release_version}.zip'
    with ZipFile(archive, 'w', compression=ZIP_DEFLATED) as bundle:
        for name, path in sorted(entries.items()):
            info = ZipInfo(name, (2020, 1, 1, 0, 0, 0))
            info.compress_type = ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            bundle.writestr(info, path.read_bytes())
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix('.zip.sha256').write_text(f'{digest}  {archive.name}\n', encoding='ascii')
    return archive

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--expected-version')
    args = parser.parse_args()
    print(build(expected=args.expected_version))
