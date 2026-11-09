"""Compare actual-size rasters; fixed fixture thresholds do not prove all PDF fidelity."""
import argparse
import json
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageOps, ImageStat

# Chosen before the first renderer comparison, not fitted to observed failures.
POLICY = {'pageMeanError': 8.0, 'pageLargeErrorPercent': 5.0,
          'regionMeanError': 12.0, 'regionLargeErrorPercent': 15.0,
          'largeErrorThreshold': 32, 'inkThreshold': 220,
          'minimumReferenceInkPixels': 100, 'minimumInkRatio': .75,
          'maximumInkRatio': 1.45}


def metrics(reference, candidate):
    diff = ImageChops.difference(reference, candidate)
    high = ImageChops.lighter(ImageChops.lighter(*diff.split()[:2]), diff.split()[2])
    count = high.point(lambda v: 255 if v > POLICY['largeErrorThreshold'] else 0).histogram()[255]
    return {'meanError': sum(ImageStat.Stat(diff).mean) / 3,
            'largeErrorPercent': 100 * count / (reference.width * reference.height)}


def ink_pixels(image):
    return ImageOps.grayscale(image).point(
        lambda v: 0 if v < POLICY['inkThreshold'] else 255).histogram()[0]


def compare_images(reference, candidate, expected_size, regions):
    errors = []
    result = {'referenceSize': list(reference.size), 'candidateSize': list(candidate.size),
              'expectedSize': list(expected_size), 'regions': [], 'errors': errors}
    if reference.size != tuple(expected_size) or candidate.size != tuple(expected_size):
        errors.append('Page dimensions differ; images were not resized to conceal it')
        result['passed'] = False
        return result
    reference, candidate = reference.convert('RGB'), candidate.convert('RGB')
    result.update(metrics(reference, candidate))
    if result['meanError'] > POLICY['pageMeanError'] or result['largeErrorPercent'] > POLICY['pageLargeErrorPercent']:
        errors.append('Whole-page difference exceeds the fixed fixture policy')
    if not regions:
        errors.append('No content regions: an empty-page comparison is not a fidelity check')
    for region in regions:
        box = region['box']
        if (len(box) != 4 or not all(isinstance(n, int) for n in box) or
                not (0 <= box[0] < box[2] <= reference.width and
                     0 <= box[1] < box[3] <= reference.height)):
            errors.append('Invalid content region: ' + region['name'])
            continue
        expected, actual = reference.crop(box), candidate.crop(box)
        ref_ink, actual_ink = ink_pixels(expected), ink_pixels(actual)
        ratio = actual_ink / ref_ink if ref_ink else None
        detail = {'name': region['name'], 'box': box, 'referenceInkPixels': ref_ink,
                  'candidateInkPixels': actual_ink, 'inkRatio': ratio,
                  **metrics(expected, actual)}
        passed = (ref_ink >= POLICY['minimumReferenceInkPixels'] and
                  POLICY['minimumInkRatio'] <= ratio <= POLICY['maximumInkRatio'] and
                  detail['meanError'] <= POLICY['regionMeanError'] and
                  detail['largeErrorPercent'] <= POLICY['regionLargeErrorPercent'])
        detail['passed'] = passed
        if not passed:
            errors.append('Content region differs or its reference is empty: ' + region['name'])
        result['regions'].append(detail)
    result['passed'] = not errors
    return result


def compare_suite(root):
    manifest = json.loads((root / 'fixture/manifest.json').read_text())
    report = {'schema': 1, 'policy': POLICY, 'scale': manifest['scale'],
              'pdfSha256': manifest['pdfSha256'], 'pages': [],
              'scope': 'Six synthetic cases on Linux; no Android or universal document-fidelity claim.'}
    output = root / 'comparison'
    output.mkdir(exist_ok=True)
    for page in manifest['pages']:
        number = page['page']
        paths = [root / f'reference/page-{number}.png', root / f'rust/page-{number:02}.ppm']
        if not all(p.is_file() for p in paths):
            report['pages'].append({'name': page['name'], 'page': number,
                                    'passed': False, 'errors': ['Missing renderer output']})
            continue
        with Image.open(paths[0]) as ref, Image.open(paths[1]) as actual:
            ref, actual = ref.convert('RGB'), actual.convert('RGB')
            result = compare_images(ref, actual, page['size'], page['regions'])
            result.update(name=page['name'], page=number)
            actual.save(root / f'rust/page-{number:02}.png')
            # Resizing is for the review sheet only. Metrics always use exact rasters.
            sheet = Image.new('RGB', (1200, 850), 'white')
            draw = ImageDraw.Draw(sheet)
            draw.text((14, 8), f"{page['name']}: Poppler reference / PDFCraft Rust", fill='black')
            for image, x in ((ref, 0), (actual, 600)):
                preview = image.copy()
                preview.thumbnail((590, 800))
                sheet.paste(preview, (x + (600 - preview.width) // 2, 35))
            sheet.save(output / f'pair-{number:02}.png')
            if ref.size == actual.size:
                diff = ImageChops.difference(ref, actual).point(lambda v: min(255, v * 4))
                diff.save(output / f'diff-{number:02}.png')
            report['pages'].append(result)
    report['passed'] = len(report['pages']) == 6 and all(p['passed'] for p in report['pages'])
    (root / 'comparison.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('root', type=Path)
    report = compare_suite(p.parse_args().root)
    print(json.dumps(report, indent=2))
    raise SystemExit(0 if report['passed'] else 1)
