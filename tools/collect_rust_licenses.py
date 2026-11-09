"""Collect resolved Rust dependency license texts offline; fail on missing notices."""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def supplemental_texts(pkg, root, *, project=ROOT):
    """Exact, reviewed upstream notices for published crates missing license files."""
    entries=json.loads((project/'licenses/third-party/overrides.json').read_text(encoding='utf-8'))
    matches=[e for e in entries if pkg['name'] in e['packages'] and pkg['version']==e['version']]
    if not matches:return []
    if len(matches)!=1:raise RuntimeError('Ambiguous supplemental license')
    entry=matches[0]
    vcs=json.loads((root/'.cargo_vcs_info.json').read_text(encoding='utf-8'))
    if pkg.get('repository')!=entry['repository'] or pkg.get('license')!=entry['license'] or vcs['git']['sha1']!=entry['commit']:
        raise RuntimeError('Supplemental license source mismatch')
    texts=[]
    for notice in entry['texts']:
        file=(project/notice['path']).resolve()
        if not file.is_relative_to(project.resolve()):raise RuntimeError('License path escapes project')
        data=file.read_bytes()
        if hashlib.sha256(data).hexdigest()!=notice['sha256']:raise RuntimeError('Supplemental license hash mismatch')
        texts.append({'name':file.name,'text':data.decode('utf-8')})
    return texts

def collect(metadata):
    active={node['id'] for node in metadata['resolve']['nodes']}
    result=[]
    for pkg in metadata['packages']:
        if pkg['id'] not in active: continue
        root=Path(pkg['manifest_path']).parent
        candidates=[]
        if pkg.get('license_file'): candidates.append(Path(pkg['license_file']))
        if pkg['name']=='pdfcraft-fonts' and pkg.get('source') is None:
            inter_notice=root.parents[1]/'assets'/'fonts'/'OFL-Inter.txt'
            if not inter_notice.is_file():
                raise RuntimeError('Missing bundled PDFCraft Inter font license')
            candidates.append(inter_notice)
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
        if not texts:texts=supplemental_texts(pkg,root)
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
