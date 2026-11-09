"""Generate original, passive PDF cases; no private or third-party sample PDFs."""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
from pypdf import PdfReader, PdfWriter
from pypdf.generic import (RectangleObject, DictionaryObject, ArrayObject,
                           NameObject, NumberObject, FloatObject, DecodedStreamObject)
from reportlab.lib import colors
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

SCALE = 2
WIDTH, HEIGHT = 600, 800


def pixel_box(box, crop, rotation):
    left, bottom, right, top = crop
    w, h = right - left, top - bottom
    points = []
    for x in (box[0], box[2]):
        for y in (box[1], box[3]):
            px, py = x - left, top - y
            px, py = {0: (px, py), 90: (h - py, px),
                      180: (w - px, h - py), 270: (py, w - px)}[rotation]
            points.append((round(px * SCALE), round(py * SCALE)))
    return [min(x for x, _ in points), min(y for _, y in points),
            max(x for x, _ in points), max(y for _, y in points)]


def make_fixture(output, font_directory):
    output.mkdir(parents=True, exist_ok=True)
    font_files = {'Regular': 'DejaVuSans.ttf', 'Bold': 'DejaVuSans-Bold.ttf',
                  'Italic': 'DejaVuSans-Oblique.ttf'}
    fonts = []
    for name, filename in font_files.items():
        path = font_directory / filename
        pdfmetrics.registerFont(TTFont('Fidelity' + name, str(path)))
        fonts.append({'name': filename, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                      'source': 'https://dejavu-fonts.github.io/',
                      'license': 'Bitstream-Vera; DejaVu changes public domain'})

    # Original raster document, with the same openly licensed typeface.
    scan = Image.new('RGB', (1040, 840), '#f8fafc')
    draw = ImageDraw.Draw(scan)
    raster_font = ImageFont.truetype(str(font_directory / font_files['Regular']), 32)
    draw.text((36, 26), 'Скан: проверка кириллицы и JPEG', fill='#14253d', font=raster_font)
    for row, label in enumerate(('Документ 0123456789', 'Красный, зелёный, синий', 'Чёткие линии и мелкие детали')):
        y = 100 + row * 90
        draw.rectangle((32, y, 1008, y + 66), outline='#64748b', width=2)
        draw.text((48, y + 12), label, fill='#202020', font=raster_font)
    for y in range(420, 780):
        draw.line((32, y, 1008, y), fill=(round(255 * (y - 420) / 359), 100, 180))
    scan.save(output / 'scan.jpg', quality=92, subsampling=0)
    alpha = Image.new('RGBA', (480, 240), (0, 0, 0, 0))
    a = ImageDraw.Draw(alpha)
    a.ellipse((10, 10, 230, 230), fill=(240, 50, 60, 135))
    a.rectangle((140, 35, 470, 205), fill=(10, 120, 240, 165))
    alpha.save(output / 'alpha.png')

    raw = output / 'fixture-raw.pdf'
    c = canvas.Canvas(str(raw), pagesize=(WIDTH, HEIGHT), invariant=1,
                      pageCompression=1, pdfVersion=(1, 4))
    c.setTitle('ArtOfficeCraft original PDF renderer fixture')
    c.setAuthor('ArtOfficeCraft Mobile test fixture')
    cases = []

    def start(name, description, crop=None, rotation=0):
        crop = crop or [0, 0, WIDTH, HEIGHT]
        top = 710 if crop[1] else 750
        c.setFillColorRGB(.08, .15, .24)
        c.setFont('FidelityBold', 20)
        c.drawString(64, top, name)
        c.setFont('FidelityRegular', 10)
        c.drawString(64, top - 23, description)
        c.setStrokeColorRGB(.7, .76, .83)
        c.line(64, top - 35, 536, top - 35)
        c.setFont('FidelityRegular', 9)
        c.drawString(64, 75 if crop[1] else 28, f'Original synthetic case {len(cases) + 1} - no active PDF content')
        case = {'name': name, 'page': len(cases) + 1, 'crop': crop,
                'rotation': rotation, 'regions': []}
        w, h = crop[2] - crop[0], crop[3] - crop[1]
        if rotation in (90, 270):
            w, h = h, w
        case['size'] = [w * SCALE, h * SCALE]
        cases.append(case)
        return case

    def region(case, name, box):
        case['regions'].append({'name': name, 'box': pixel_box(box, case['crop'], case['rotation'])})

    case = start('01 Embedded Cyrillic', 'Regular, bold and italic TrueType subsets; text and a small table.')
    texts = [('Regular', 22, 'Съешь ещё этих мягких французских булок.'),
             ('Bold', 18, 'Ёж, щука, цифры 0123456789'),
             ('Italic', 14, 'Кириллица: АБВГД абвгд; Latin ABC xyz'),
             ('Regular', 9, 'Мелкий текст: проверяем перенос, интервалы, знаки № 17 и € 25.')]
    for i, (face, size, text) in enumerate(texts):
        y = 650 - i * 72
        # Keep the fixture readable rather than clipping an intentionally long line.
        size = min(size, 470 / pdfmetrics.stringWidth(text, 'Fidelity' + face, 1))
        c.setFont('Fidelity' + face, size)
        c.setFillColorRGB(.05, .07, .1)
        c.drawString(64, y, text)
        region(case, face + str(i), [60, y - 5, 540, y + size + 8])
    for row in range(4):
        y = 225 + row * 35
        c.setFillColorRGB(.91, .95, .98)
        c.setStrokeColorRGB(.35, .45, .55)
        c.rect(64, y, 472, 35, fill=1)
        c.setFillColorRGB(.05, .08, .12)
        c.setFont('FidelityRegular', 11)
        c.drawString(76, y + 12, f'Строка {row + 1}: значение {row * 125}.50')
    region(case, 'table', [62, 223, 538, 367])
    c.showPage()

    case = start('02 Raster document', 'Original JPEG image containing text, lines and a colour gradient.')
    c.drawImage(str(output / 'scan.jpg'), 40, 180, width=520, height=420)
    region(case, 'jpeg', [40, 180, 560, 600])
    c.showPage()

    case = start('03 Transparency', 'PDF alpha blending and an RGBA PNG over a checkerboard.')
    for row in range(10):
        for col in range(16):
            level = .9 if (row + col) % 2 else .98
            c.setFillColorRGB(level, level, level)
            c.rect(60 + col * 30, 180 + row * 24, 30, 24, stroke=0, fill=1)
    c.drawImage(str(output / 'alpha.png'), 60, 180, width=480, height=240, mask='auto')
    c.saveState()
    c.setFillAlpha(.45)
    c.setFillColorRGB(.95, .15, .2)
    c.rect(64, 480, 290, 130, fill=1, stroke=0)
    c.setFillColorRGB(.1, .3, .95)
    c.circle(390, 535, 100, fill=1, stroke=0)
    c.restoreState()
    region(case, 'pdf alpha', [60, 430, 530, 640])
    region(case, 'png alpha', [60, 180, 540, 420])
    c.showPage()

    case = start('04 Vector clipping', 'Bezier curves and transformed strokes clipped to a rounded shape.')
    c.saveState()
    path = c.beginPath()
    path.roundRect(80, 250, 440, 390, 42)
    c.clipPath(path, stroke=0, fill=0)
    for i in range(24):
        c.setStrokeColorRGB(i / 30, .35, 1 - i / 30)
        c.setLineWidth(2)
        path = c.beginPath()
        path.moveTo(20, 210 + i * 22)
        path.curveTo(180, 820, 420, 50, 580, 360 + i * 18)
        c.drawPath(path)
    c.restoreState()
    c.setStrokeColorRGB(.1, .2, .3)
    c.roundRect(80, 250, 440, 390, 42, stroke=1, fill=0)
    region(case, 'curves', [76, 246, 524, 644])
    c.showPage()

    case = start('05 Rotation 90', 'Expected: this complete portrait content rotates clockwise.', rotation=90)
    for x, y, colour in ((80, 600, (.9, .1, .1)), (420, 600, (.1, .7, .2)),
                          (80, 150, (.1, .3, .9)), (420, 150, (.6, .2, .7))):
        c.setFillColorRGB(*colour)
        c.rect(x, y, 100, 90, stroke=0, fill=1)
    c.setFillColorRGB(.05, .08, .12)
    c.setFont('FidelityBold', 20)
    c.drawString(100, 390, 'Поворот страницы: 90')
    region(case, 'rotated text', [90, 380, 510, 425])
    region(case, 'corner markers', [76, 146, 524, 694])
    c.showPage()

    case = start('06 Offset CropBox', 'Only the inset page region should be visible.', crop=[40, 50, 560, 750])
    c.setStrokeColorRGB(1, 0, 0)
    c.setLineWidth(8)
    c.rect(4, 4, 592, 792)  # This outer border must be cropped away.
    c.setStrokeColorRGB(.15, .35, .6)
    c.setLineWidth(2)
    c.rect(65, 110, 470, 540)
    c.setFont('FidelityRegular', 17)
    c.setFillColorRGB(.1, .2, .3)
    c.drawString(85, 600, 'Обрезка: начало координат смещено')
    c.drawImage(str(output / 'scan.jpg'), 85, 190, width=430, height=347)
    region(case, 'inset text', [80, 590, 530, 630])
    region(case, 'inset image', [85, 190, 515, 537])
    c.showPage()
    case = start('07 Original Type3 glyphs', 'Original vector glyph programs with explicit widths and font matrix.')
    c.setFillColorRGB(.1, .22, .4)
    c._code.append('BT /AOCType3 96 Tf 1 0 0 1 80 400 Tm (ABBAAB) Tj ET')
    region(case, 'type3 glyphs', [75, 390, 450, 480])
    c.showPage()

    case = start('08 Form appearance', 'AcroForm text field and checkbox appearance streams; no actions.')
    c.acroForm.textfield(name='original_text', x=80, y=480, width=400, height=52,
                        value='Mobile PDF 123', fontName='Helvetica', fontSize=22,
                        borderWidth=1, forceBorder=True, fillColor=colors.white, textColor=colors.black)
    c.acroForm.checkbox(name='original_check', x=90, y=360, size=36,
                       checked=True, buttonStyle='check', forceBorder=True, fillColor=colors.white, textColor=colors.black)
    region(case, 'form text', [84, 492, 350, 524])
    region(case, 'checkbox', [94, 364, 122, 392])
    c.showPage()
    c.save()

    reader = PdfReader(raw)
    writer = PdfWriter()
    writer.clone_document_from_reader(reader)
    for page, case in zip(writer.pages, cases, strict=True):
        page.cropbox = RectangleObject(case['crop'])
        if case['rotation']:
            page.rotate(case['rotation'])
    # These glyphs are original geometric drawings, not extracted font outlines.
    procs = DictionaryObject()
    for name, program in {
        'A': b'600 0 0 0 600 700 d1 40 0 m 300 700 l 560 0 l h f',
        'B': b'600 0 0 0 600 700 d1 50 0 480 280 re f 50 420 480 280 re f',
    }.items():
        stream = DecodedStreamObject()
        stream.set_data(program)
        procs[NameObject('/' + name)] = writer._add_object(stream)
    font = DictionaryObject({
        NameObject('/Type'): NameObject('/Font'), NameObject('/Subtype'): NameObject('/Type3'),
        NameObject('/FontBBox'): RectangleObject([0, 0, 600, 700]),
        NameObject('/FontMatrix'): ArrayObject([FloatObject(.001), NumberObject(0), NumberObject(0), FloatObject(.001), NumberObject(0), NumberObject(0)]),
        NameObject('/CharProcs'): procs,
        NameObject('/Encoding'): DictionaryObject({NameObject('/Differences'): ArrayObject([NumberObject(65), NameObject('/A'), NameObject('/B')])}),
        NameObject('/FirstChar'): NumberObject(65), NameObject('/LastChar'): NumberObject(66),
        NameObject('/Widths'): ArrayObject([NumberObject(600), NumberObject(600)]),
        NameObject('/Resources'): DictionaryObject(),
    })
    writer.pages[6]['/Resources']['/Font'][NameObject('/AOCType3')] = writer._add_object(font)
    writer.add_metadata({'/Title': 'ArtOfficeCraft synthetic PDF fidelity fixture',
                         '/Author': 'ArtOfficeCraft Mobile test fixture'})
    with (output / 'fixture.pdf').open('wb') as stream:
        writer.write(stream)
    check = PdfReader(output / 'fixture.pdf')
    assert len(check.pages) == 8 and 'Кириллица' in check.pages[0].extract_text()
    assert '/OpenAction' not in check.trailer['/Root']
    assert '/JavaScript' not in check.trailer['/Root'].get('/Names', {})
    manifest = {'schema': 1, 'scale': SCALE, 'pages': cases, 'fonts': fonts,
                'pdfBytes': (output / 'fixture.pdf').stat().st_size,
                'pdfSha256': hashlib.sha256((output / 'fixture.pdf').read_bytes()).hexdigest()}
    (output / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    copyright_file = Path('/usr/share/doc/fonts-dejavu-core/copyright')
    notice = copyright_file.read_text().split('Files: debian/*')[0]
    (output / 'FONT-NOTICE.txt').write_text(notice)
    (output / 'FIXTURE-NOTICE.txt').write_text(
        'Original generated PDF, images and labels: ArtOfficeCraft Mobile, MIT.\n'
        'Embedded font subsets: DejaVu fonts, Bitstream-Vera; changes public domain.\n'
        'See FONT-NOTICE.txt and manifest.json for provenance.\n')
    raw.unlink()
    return manifest


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('output', type=Path)
    p.add_argument('--fonts', type=Path, default=Path('/usr/share/fonts/truetype/dejavu'))
    args = p.parse_args()
    make_fixture(args.output, args.fonts)
