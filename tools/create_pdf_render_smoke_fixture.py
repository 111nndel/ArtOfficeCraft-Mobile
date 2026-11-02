from pathlib import Path
base=Path(__file__).resolve().parents[1]/'build'/'pdf-render-smoke'
base.mkdir(parents=True,exist_ok=True)
stream=b'BT /F1 24 Tf 60 740 Td (ArtOfficeCraft PDF render test v0.6) Tj ET\n'
objects=[
 b'<< /Type /Catalog /Pages 2 0 R >>',
 b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
 b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
 b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
 b'<< /Length '+str(len(stream)).encode()+b' >>\nstream\n'+stream+b'endstream'
]
out=bytearray(b'%PDF-1.4\n%\xe2\xe3\xcf\xd3\n')
offsets=[0]
for i,obj in enumerate(objects,1):
    offsets.append(len(out))
    out.extend(str(i).encode()+b' 0 obj\n'+obj+b'\nendobj\n')
start=len(out)
out.extend(b'xref\n0 '+str(len(offsets)).encode()+b'\n0000000000 65535 f \n')
for o in offsets[1:]:
    out.extend(f'{o:010d} 00000 n \n'.encode())
out.extend(b'trailer\n<< /Size '+str(len(offsets)).encode()+b' /Root 1 0 R >>\nstartxref\n'+str(start).encode()+b'\n%%EOF\n')
p=base/'pdf-render-smoke.pdf'
p.write_bytes(out)
print('PDF_SAMPLE',p,'BYTES',len(out))
