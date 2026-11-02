"""Resolve approved git commits to Cargo path dependencies.

This script does not fetch or execute downloaded source code.
It refuses a dirty or mismatched checkout. Only WordCraft is in the native
bridge today; Grid/Deck/PDF will use the same lock after porting.
"""
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
    config=json.loads(LOCK.read_text(encoding='utf-8'))
    pins=config['engines']
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
        if git(folder,'status','--porcelain','--untracked-files=no'):
            raise RuntimeError(f'{name}: modified tracked files; refusing build')
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
    CARGO.write_text(cargo,encoding='utf-8')
    print('Native WordCraft Cargo paths synchronized to approved pins')
    return 0

if __name__=='__main__':
    raise SystemExit(main())
