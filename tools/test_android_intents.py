from pathlib import Path
import unittest
import xml.etree.ElementTree as ET


class AndroidIntentTests(unittest.TestCase):
    def test_only_supported_mime_types_are_advertised_as_default_view_and_share_handlers(self):
        root = ET.parse(Path(__file__).resolve().parents[1] / 'android/app/src/main/AndroidManifest.xml').getroot()
        key = '{http://schemas.android.com/apk/res/android}'
        activity = root.find('application/activity')
        self.assertEqual(activity.get(key + 'launchMode'), 'singleTop')
        route_flag = next(m for m in activity.findall('meta-data')
                          if m.get(key + 'name') == 'flutter_deeplinking_enabled')
        self.assertEqual(route_flag.get(key + 'value'), 'false')
        expected = {'application/pdf',
                    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
                    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                    'application/vnd.openxmlformats-officedocument.presentationml.presentation'}
        for action in ('VIEW', 'SEND'):
            filters = [f for f in activity.findall('intent-filter')
                       if any(a.get(key + 'name') == 'android.intent.action.' + action for a in f.findall('action'))]
            self.assertEqual(len(filters), 1)
            self.assertEqual({d.get(key + 'mimeType') for d in filters[0].findall('data')}, expected)
            self.assertEqual([c.get(key + 'name') for c in filters[0].findall('category')], ['android.intent.category.DEFAULT'])
        self.assertEqual({p.get(key + 'name') for p in root.findall('uses-permission')},
                         {'android.permission.INTERNET', 'android.permission.REQUEST_INSTALL_PACKAGES'})
        provider = root.find('application/provider')
        self.assertEqual(provider.get(key + 'exported'), 'false')
        paths = ET.parse(Path(__file__).resolve().parents[1] / 'android/app/src/main/res/xml/update_paths.xml').getroot()
        self.assertEqual([(p.tag, p.get('path')) for p in paths], [('cache-path', 'updates/')])


if __name__ == '__main__':
    unittest.main()
