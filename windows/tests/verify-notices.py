"""Validate the distributable, including its ZIP, without running Windows code."""
import json
from pathlib import Path
import sys
import zipfile


def verify(read, names):
    def required(name):
        assert name in names, f'Missing distribution notice: {name}'
        data = read(name)
        assert data.strip(), f'Empty distribution notice: {name}'
        return data

    assert b'flyingcow-niu' in required('LICENSE.txt')
    required('THIRD-PARTY-NOTICES.txt')
    frameworks = json.loads(read('ClipKeep.runtimeconfig.json'))['runtimeOptions']['includedFrameworks']
    packs = dict(line.split('|') for line in required('licenses/packages.txt').decode('utf-8-sig').splitlines() if line)
    for framework in frameworks:
        matches = [(name, version) for name, version in packs.items()
                   if name.startswith(framework['name'] + '.Runtime.')]
        assert len(matches) == 1, f'Missing or ambiguous runtime notice: {framework["name"]}'
        assert matches[0][1] == framework['version'], 'Runtime and notice versions differ'
    assert any('.Host.' in name for name in packs), 'App host notices missing'
    for name, version in packs.items():
        base = f'licenses/{name}/{version}/'
        license_names = [n for n in names if n.startswith(base) and n[len(base):].upper() in ('LICENSE', 'LICENSE.TXT')]
        assert license_names, f'License missing for {name}'
        for filename in license_names:
            assert b'Permission is hereby granted' in required(filename)
        if name.startswith('Microsoft.NETCore.App.'):
            assert b'.NET' in required(base + 'THIRD-PARTY-NOTICES.TXT')
    print(f'License checks passed: {len(packs)} versioned runtime/host packs')


if __name__ == '__main__':
    path = Path(sys.argv[1])
    if path.is_dir():
        names = {p.relative_to(path).as_posix() for p in path.rglob('*') if p.is_file()}
        verify(lambda name: (path / name).read_bytes(), names)
    else:
        with zipfile.ZipFile(path) as archive:
            verify(archive.read, set(archive.namelist()))
