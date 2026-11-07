import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from collect_rust_licenses import supplemental_texts


class SupplementalLicenseTests(unittest.TestCase):
    def test_exact_version_source_and_notice_integrity_are_required(self):
        with tempfile.TemporaryDirectory() as tmp:
            project=Path(tmp)
            folder=project/'licenses/third-party'
            folder.mkdir(parents=True)
            notice=folder/'LICENSE'
            notice.write_text('Original upstream notice\n')
            crate=project/'crate'
            crate.mkdir()
            (crate/'.cargo_vcs_info.json').write_text(json.dumps({'git':{'sha1':'abc'}}))
            package=dict(name='ratex-font',version='0.1.14',repository='https://example.org/repo',license='MIT')
            entry=dict(packages=['ratex-font'],version='0.1.14',repository=package['repository'],license='MIT',commit='abc',texts=[dict(path='licenses/third-party/LICENSE',sha256=hashlib.sha256(notice.read_bytes()).hexdigest())])
            (folder/'overrides.json').write_text(json.dumps([entry]))
            self.assertEqual(supplemental_texts(package,crate,project=project)[0]['text'],notice.read_text())
            self.assertEqual(supplemental_texts({**package,'version':'0.1.15'},crate,project=project),[])
            with self.assertRaisesRegex(RuntimeError,'source mismatch'):
                supplemental_texts({**package,'repository':'https://different.example'},crate,project=project)
            notice.write_text('Changed license')
            with self.assertRaisesRegex(RuntimeError,'hash mismatch'):
                supplemental_texts(package,crate,project=project)


if __name__=='__main__':unittest.main()
