"""Exercise the real MSBuild collector with isolated package directories."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

TARGET = Path(__file__).resolve().parents[1] / 'PublishNotices.targets'
DOTNET = os.environ.get('DOTNET', 'dotnet')


class CollectionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.output = self.root / 'publish'
        self.output.mkdir()
        project = ET.Element('Project')
        props = ET.SubElement(project, 'PropertyGroup')
        ET.SubElement(props, 'SelfContained').text = 'true'
        ET.SubElement(props, 'PublishDir').text = str(self.output) + os.sep
        items = ET.SubElement(project, 'ItemGroup')
        self.packs = []
        for family, kind in [('Microsoft.NETCore.App', 'Runtime'), ('Microsoft.WindowsDesktop.App', 'Runtime'), ('Microsoft.NETCore.App', 'Host')]:
            package = f'{family}.{kind}.win-x64'
            directory = self.root / package
            directory.mkdir()
            (directory / 'LICENSE').write_bytes(b'upstream copyright\r\nPermission is hereby granted\r\n')
            if family == 'Microsoft.NETCore.App':
                (directory / 'THIRD-PARTY-NOTICES.TXT').write_bytes(b'.NET third-party text\r\n\xc2\xa9 original bytes\r\n')
            item = ET.SubElement(items, 'ResolvedRuntimePack' if kind == 'Runtime' else 'ResolvedAppHostPack', Include=package)
            for key, value in dict(FrameworkName=family, NuGetPackageId=package, NuGetPackageVersion='10.0.99', PackageDirectory=str(directory)).items():
                ET.SubElement(item, key).text = value
            self.packs.append(directory)
        ET.SubElement(project, 'Import', Project=str(TARGET))
        self.project = self.root / 'test.proj'
        ET.ElementTree(project).write(self.project, encoding='utf-8')

    def collect(self):
        return subprocess.run([DOTNET, 'msbuild', str(self.project), '-t:PublishLicenseNotices', '-nologo'], capture_output=True, text=True)

    def test_preserves_upstream_bytes_and_removes_stale_versions(self):
        stale = self.output / 'licenses' / 'obsolete.txt'
        stale.parent.mkdir()
        stale.write_text('old version')
        result = self.collect()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(stale.exists())
        for package in self.packs:
            for source in package.iterdir():
                copied = self.output / 'licenses' / package.name / '10.0.99' / source.name
                self.assertEqual(copied.read_bytes(), source.read_bytes())
        self.assertTrue((self.output / 'LICENSE.txt').is_file())

    def test_missing_upstream_license_blocks_publication(self):
        (self.packs[1] / 'LICENSE').unlink()
        result = self.collect()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Missing upstream license', result.stdout)

    def test_missing_runtime_third_party_notices_blocks_publication(self):
        (self.packs[0] / 'THIRD-PARTY-NOTICES.TXT').unlink()
        result = self.collect()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Missing upstream third-party notices', result.stdout)


if __name__ == '__main__':
    unittest.main()
