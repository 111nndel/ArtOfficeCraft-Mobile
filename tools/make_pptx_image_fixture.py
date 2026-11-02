#!/usr/bin/env python3
"""Create an original raster-image test PPTX from an existing normal PPTX.
No external packages, images, licenses, or network access are needed.
Usage: python tools/make_pptx_image_fixture.py base.pptx output.pptx
"""
from pathlib import Path
import struct, sys, zlib, zipfile

def png_image(width=320,height=200):
    # Original colored bands and accent pattern; no third-party visual assets.
    rows=[]
    for y in range(height):
        line=bytearray(b'\0')
        for x in range(width):
            if x//40%2 == 0:
                color=(34,112,210) if y<height//2 else (21,170,112)
            else:
                color=(242,142,44) if y<height//2 else (111,62,178)
            if (x-y)%53<4:color=(250,250,250)
            line.extend(color)
        rows.append(line)
    def chunk(kind, payload):
        data=kind+payload
        return struct.pack('>I',len(payload))+data+struct.pack('>I',zlib.crc32(data)&0xffffffff)
    return (
        bytes([137,80,78,71,13,10,26,10])+
        chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,2,0,0,0))+
        chunk(b'IDAT',zlib.compress(b''.join(rows),6))+
        chunk(b'IEND',b'')
    )

def main(base:Path,out:Path):
    if not zipfile.is_zipfile(base):raise ValueError('Base PPTX is not a ZIP')
    with zipfile.ZipFile(base,'r') as z:
        xml=z.read('ppt/slides/slide2.xml')
        rels=z.read('ppt/slides/_rels/slide2.xml.rels')
        types=z.read('[Content_Types].xml')
        if b'rId20' in rels or b'QA_Pattern' in xml:
            raise ValueError('Fixture would conflict with existing slide image')
        pic=(
          b'<p:pic><p:nvPicPr><p:cNvPr id="4321" name="QA_Pattern"/>'
          b'<p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr>'
          b'<p:nvPr/></p:nvPicPr>'
          b'<p:blipFill><a:blip r:embed="rId20"/>'
          b'<a:stretch><a:fillRect/></a:stretch></p:blipFill>'
          b'<p:spPr><a:xfrm><a:off x="6100000" y="2400000"/>'
          b'<a:ext cx="3950000" cy="2100000"/></a:xfrm>'
          b'<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>'
          b'</p:spPr></p:pic>'
        )
        if xml.count(b'</p:spTree>')!=1:raise ValueError('Unknown slide structure')
        xml=xml.replace(b'</p:spTree>',pic+b'</p:spTree>')
        relationship=(
          b'<Relationship Id="rId20" Type="http://schemas.openxmlformats.org/'
          b'officeDocument/2006/relationships/image" Target="../media/qa-pattern.png"/>'
        )
        if rels.count(b'</Relationships>')!=1:raise ValueError('Unexpected slide rels')
        rels=rels.replace(b'</Relationships>',relationship+b'</Relationships>')
        if b'Extension="png"' not in types:
            types=types.replace(b'</Types>',
                b'<Default Extension="png" ContentType="image/png"/></Types>')
        out.parent.mkdir(exist_ok=True,parents=True)
        with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as output:
            for item in z.infolist():
                contents={ 'ppt/slides/slide2.xml':xml,
                  'ppt/slides/_rels/slide2.xml.rels':rels,
                  '[Content_Types].xml':types }.get(item.filename)
                output.writestr(item,contents if contents is not None else z.read(item.filename))
            output.writestr('ppt/media/qa-pattern.png',png_image())
    with zipfile.ZipFile(out) as test:
        assert test.testzip() is None
    print('PPTX_IMAGE_FIXTURE',out,'BYTES',out.stat().st_size)

if __name__=='__main__':
    if len(sys.argv)!=3:
        raise SystemExit('Usage: script.py input.pptx output.pptx')
    main(Path(sys.argv[1]),Path(sys.argv[2]))
