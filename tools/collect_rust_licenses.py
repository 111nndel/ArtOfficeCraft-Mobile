"""Collect resolved Rust dependency license texts offline; fail on missing notices."""
import argparse,json,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def collect(metadata):
    active={node['id'] for node in metadata['resolve']['nodes']}
    result=[]
    for pkg in metadata['packages']:
        if pkg['id'] not in active: continue
        root=Path(pkg['manifest_path']).parent
        candidates=[]
        if pkg.get('license_file'): candidates.append(Path(pkg['license_file']))
        for folder in [root,*list(root.parents)[:3]]:
            if not folder.is_dir():continue
            for file in folder.iterdir():
                if file.is_file() and re.search(r'licen[cs]e|copying|notice|copyright',file.name,re.I):
                    candidates.append(file)
            # Registry packages carry their own text; never borrow a sibling's license.
            if pkg.get('source'): break
        texts=[];seen=set()
        for file in candidates:
            if not file.is_file() or file.stat().st_size>2*1024*1024:continue
            value=file.read_text(encoding='utf-8',errors='replace')
            if value in seen:continue
            seen.add(value);texts.append({'name':file.name,'text':value})
        if not texts:raise RuntimeError(f"Missing license text: {pkg['name']} {pkg['version']}")
        result.append({'name':pkg['name'],'version':pkg['version'],'license':pkg.get('license'),
            'repository':pkg.get('repository'),'texts':texts})
    return sorted(result,key=lambda p:(p['name'],p['version']))

def main():
    p=argparse.ArgumentParser();p.add_argument('--metadata');args=p.parse_args()
    if args.metadata: metadata=json.loads(Path(args.metadata).read_text(encoding='utf-8-sig'))
    else:
        proc=subprocess.run(['cargo','metadata','--offline','--locked','--format-version','1',
          '--filter-platform','aarch64-linux-android','--manifest-path',str(ROOT/'native/artoffice_core/Cargo.toml')],
          stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=True)
        metadata=json.loads(proc.stdout)
    entries=collect(metadata)
    target=ROOT/'assets/legal/rust-licenses.json';target.parent.mkdir(parents=True,exist_ok=True)
    target.write_text(json.dumps(entries,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(f'{len(entries)} resolved Rust packages; license texts saved without local paths')
if __name__=='__main__':main()
