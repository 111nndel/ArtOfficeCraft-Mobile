import subprocess
import tempfile
import unittest
from pathlib import Path
import engine_updater as m

class UpdaterTests(unittest.TestCase):
    def test_versions(self):
        self.assertLess(m.version('v0.14.0'), m.version('v0.15.0'))
        for t in ('main', 'v0.14.0-rc', '../x', 'v0.01.0'):
            with self.assertRaises(ValueError):
                m.version(t)

    def test_pins(self):
        x=m.config()
        self.assertEqual(set(x['engines']),set(m.ENGINES))
        for n,c in x['engines'].items():
            self.assertTrue(c['repo'].endswith('/'+n+'.git'))
            self.assertEqual(40,len(c['commit']))

    def test_reject_untracked_compiler_input(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp)
            subprocess.run(['git','init','--quiet',str(folder)],check=True)
            self.assertTrue(m.clean_source(folder))
            (folder/'ARTOFFICECRAFT_SOURCE_ATTESTATION.json').write_text('{}')
            self.assertTrue(m.clean_source(folder))
            (folder/'build.rs').write_text('fn main() {}')
            self.assertFalse(m.clean_source(folder))

    def test_cargo_version(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp)
            (folder/'Cargo.toml').write_text('[workspace.package]\\nversion = "0.15.0"\\n'.replace('\\n','\n'),encoding='utf-8')
            m.cargo_valid(folder,'v0.15.0')
            with self.assertRaises(RuntimeError):m.cargo_valid(folder,'v0.14.0')

if __name__=='__main__':
    unittest.main()
