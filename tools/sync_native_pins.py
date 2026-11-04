"""Resolve approved git commits to Cargo path dependencies.

This script does not fetch or execute downloaded source code.
It refuses dirty or mismatched upstream checkouts, including untracked compiler
inputs. All four adapters use the exact approved commits.
"""
from engine_updater import config, clean_source
import json
import re
import subprocess
import sys
import tomllib
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
LOCK=ROOT/'upstream'/'engines.lock.json'
CARGO=ROOT/'native'/'artoffice_core'/'Cargo.toml'
def git(path,*args):
    return subprocess.check_output(['git','-C',str(path),*args],text=True,
                                   stderr=subprocess.STDOUT).strip()

PATCH_BEGIN = '# BEGIN ArtOfficeCraft reviewed PDF dependency patches'
PATCH_END = '# END ArtOfficeCraft reviewed PDF dependency patches'


def pdf_patch_block(folder, cargo_base):
    """Keep the decoder fixes shipped by the exact reviewed PdfCraft source."""
    manifest = tomllib.loads((folder / 'Cargo.toml').read_text(encoding='utf-8-sig'))
    patches = manifest.get('patch', {}).get('crates-io', {})
    lines = [PATCH_BEGIN, '[patch.crates-io]']
    for name in ('hayro-jbig2',):
        entry = patches.get(name)
        if not isinstance(entry, dict) or set(entry) != {'path'}:
            raise RuntimeError(f'{name}: upstream patch changed; review required')
        target = (folder / entry['path']).resolve()
        if not target.is_relative_to(folder.resolve()):
            raise RuntimeError('Upstream patch escapes the reviewed source')
        package = tomllib.loads((target / 'Cargo.toml').read_text(encoding='utf-8-sig'))['package']
        if package.get('name') != name:
            raise RuntimeError('Upstream patch package name mismatch')
        relative = target.relative_to(folder.resolve()).as_posix()
        lines.append(f'{name} = {{ path = {json.dumps(cargo_base + relative)} }}')
    return '\n'.join([*lines, PATCH_END])


def install_patch_block(cargo, block):
    pattern = re.escape(PATCH_BEGIN) + r'.*?' + re.escape(PATCH_END)
    if cargo.count(PATCH_BEGIN) != cargo.count(PATCH_END) or cargo.count(PATCH_BEGIN) > 1:
        raise RuntimeError('Malformed managed dependency patch section')
    remaining = re.sub(pattern, '', cargo, flags=re.S)
    if '[patch.crates-io]' in remaining:
        raise RuntimeError('Unmanaged Cargo patches require review')
    return remaining.rstrip() + '\n\n' + block + '\n'


def main():
    pins=config()['engines']
    for name in ('wordcraft','gridcraft','deckcraft','pdfcraft'):
        v=pins[name]
        assert re.fullmatch(r'v\d+\.\d+\.\d+',v['tag'])
        assert re.fullmatch(r'[0-9a-f]{40}',v['commit'])
        folder=ROOT/'upstream'/'staged'/name/(v['tag']+'-'+v['commit'][:12])
        if not folder.is_dir():
            print(f'{name}: source not staged. Run stage-rust-engines.ps1 first.', file=sys.stderr)
            return 2
        if git(folder,'rev-parse','HEAD')!=v['commit']:
            raise RuntimeError(f'{name}: commit mismatch; refusing build')
        if not clean_source(folder):
            raise RuntimeError(f'{name}: modified or untracked source files; refusing build')
        print(f'{name}: {v["tag"]} {v["commit"][:12]} verified')
    w=pins['wordcraft']
    wbase='../../upstream/staged/wordcraft/'+w['tag']+'-'+w['commit'][:12]+'/crates/'
    cargo=CARGO.read_text(encoding='utf-8')
    cargo,count1=re.subn(r'(wordcraft-doc\s*=\s*\{\s*path\s*=\s*")[^"]+',
                         lambda m:m.group(1)+wbase+'doc',cargo)
    cargo,count2=re.subn(r'(wordcraft-docx\s*=\s*\{\s*path\s*=\s*")[^"]+',
                         lambda m:m.group(1)+wbase+'docx',cargo)
    if (count1,count2)!=(1,1):
        raise RuntimeError('Could not locate expected WordCraft Cargo path fields')
    grid=pins['gridcraft']
    base='../../upstream/staged/gridcraft/'+grid['tag']+'-'+grid['commit'][:12]+'/crates/'
    for name in ('core','model','xlsx','calc','numfmt','engine'):
        crate='gridcraft-'+name
        cargo,count=re.subn(
            r'('+re.escape(crate)+r'\s*=\s*\{\s*path\s*=\s*")[^"]+',
            lambda m:m.group(1)+base+name, cargo,
        )
        if count != 1:
            raise RuntimeError('GridCraft Cargo dependency missing: '+crate)
    deck=pins['deckcraft']
    deckbase='../../upstream/staged/deckcraft/'+deck['tag']+'-'+deck['commit'][:12]+'/crates/'
    for name in ('model','pptx'):
        crate='deckcraft-'+name
        cargo,count=re.subn(
            r'('+re.escape(crate)+r'\s*=\s*\{\s*path\s*=\s*")[^"]+',
            lambda m:m.group(1)+deckbase+name, cargo,
        )
        if count != 1:
            raise RuntimeError('DeckCraft Cargo dependency missing: '+crate)
    pdf=pins['pdfcraft']
    pdfbase='../../upstream/staged/pdfcraft/'+pdf['tag']+'-'+pdf['commit'][:12]+'/crates/'
    for name in ('cos','model'):
        crate='pdfcraft-'+name
        cargo,count=re.subn(
            r'('+re.escape(crate)+r'\s*=\s*\{\s*path\s*=\s*")[^"]+',
            lambda m:m.group(1)+pdfbase+name, cargo,
        )
        if count != 1:
            raise RuntimeError('PDFCraft Cargo dependency missing: '+crate)
    pdfroot = ROOT/'upstream'/'staged'/'pdfcraft'/(pdf['tag']+'-'+pdf['commit'][:12])
    cargo = install_patch_block(cargo, pdf_patch_block(pdfroot, pdfbase.removesuffix('crates/')))
    CARGO.write_text(cargo,encoding='utf-8')
    print('Native WordCraft, GridCraft, DeckCraft and PDFCraft COS/model paths synchronized to approved pins')
    return 0

if __name__=='__main__':
    raise SystemExit(main())
