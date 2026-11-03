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
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
LOCK=ROOT/'upstream'/'engines.lock.json'
CARGO=ROOT/'native'/'artoffice_core'/'Cargo.toml'
def git(path,*args):
    return subprocess.check_output(['git','-C',str(path),*args],text=True,
                                   stderr=subprocess.STDOUT).strip()

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
    for name in ('core','model','xlsx','calc'):
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
    CARGO.write_text(cargo,encoding='utf-8')
    print('Native WordCraft, GridCraft, DeckCraft and PDFCraft COS/model paths synchronized to approved pins')
    return 0

if __name__=='__main__':
    raise SystemExit(main())
