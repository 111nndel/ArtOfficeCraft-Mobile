import unittest
from PIL import Image, ImageDraw
from compare import compare_images


class ComparatorTests(unittest.TestCase):
    def setUp(self):
        self.reference = Image.new('RGB', (200, 200), 'white')
        ImageDraw.Draw(self.reference).rectangle((80, 80, 119, 119), fill='black')
        self.regions = [{'name': 'text-like content', 'box': [70, 70, 130, 130]}]

    def check(self, candidate, regions=None):
        return compare_images(self.reference, candidate, (200, 200),
                              self.regions if regions is None else regions)

    def test_identical_raster_passes(self):
        self.assertTrue(self.check(self.reference)['passed'])

    def test_missing_small_content_fails_even_when_whole_page_is_mostly_white(self):
        result = self.check(Image.new('RGB', (200, 200), 'white'))
        self.assertFalse(result['passed'])
        self.assertEqual(result['regions'][0]['candidateInkPixels'], 0)

    def test_wrong_dimensions_are_not_hidden_by_resizing(self):
        result = self.check(self.reference.resize((201, 200)))
        self.assertFalse(result['passed'])
        self.assertNotIn('meanError', result)

    def test_large_colour_error_fails_with_equal_ink_coverage(self):
        changed = self.reference.copy()
        ImageDraw.Draw(changed).rectangle((80, 80, 119, 119), fill='red')
        self.assertFalse(self.check(changed)['passed'])

    def test_missing_regions_cannot_certify_an_empty_page(self):
        self.assertFalse(self.check(self.reference, [])['passed'])

    def test_empty_reference_region_is_not_accepted(self):
        white = Image.new('RGB', (200, 200), 'white')
        result = compare_images(white, white, (200, 200), self.regions)
        self.assertFalse(result['passed'])

    def test_outside_region_is_reported(self):
        self.assertFalse(self.check(self.reference, [{'name': 'invalid', 'box': [-1, 2, 40, 30]}])['passed'])


if __name__ == '__main__':
    unittest.main()
