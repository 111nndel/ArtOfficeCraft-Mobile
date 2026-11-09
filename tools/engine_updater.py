#!/usr/bin/env python3
"""Four fixed GitHub Rust engines: check published releases, stage, manually pin."""
import argparse, datetime, json, os, re, shutil, subprocess, sys, tempfile, tomllib, urllib.request
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
LOCK=ROOT/'upstream'/'engines.lock.json'
STAGED=ROOT/'upstream'/'staged'
ENGINES=('wordcraft','gridcraft','deckcraft','pdfcraft')

def version(tag):
    m=re.fullmatch(r'v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)',tag)
    if not m: raise ValueError('Not a stable version tag: '+str(tag))
    return tuple(map(int,m.groups()))

def config():
    x=json.loads(LOCK.read_text(encoding='utf-8'))
    if x.get('schema_version')!=1 or set(x['engines'])!=set(ENGINES):raise ValueError('Invalid lock file')
    for name,item in x['engines'].items():
        if item['repo']!=f'https://github.com/storytold/{name}.git':raise ValueError('Untrusted repository')
        version(item['tag'])
        if not re.fullmatch('[a-f0-9]{40}',item['commit']):raise ValueError('Invalid SHA-1')
    return x

def git(*args,cwd=None,timeout=240):
    exe=shutil.which('git') or 'git'
    p=subprocess.run([exe,*args],capture_output=True,text=True,encoding='utf-8',errors='replace',
                     cwd=cwd,timeout=timeout,env={**os.environ,'GIT_TERMINAL_PROMPT':'0'})
    if p.returncode:raise RuntimeError('git failed: '+p.stderr[-600:])
    return p.stdout.strip()

def clean_source(folder):
    # Our attestation is metadata, never compiler input. Reject every other untracked file.
    return not git("status","--porcelain","--untracked-files=all","--",".",
                   ":(exclude)ARTOFFICECRAFT_SOURCE_ATTESTATION.json",cwd=folder)

def remote_commit(repo,tag):
    version(tag)
    out=git('ls-remote','--tags',repo,f'refs/tags/{tag}',f'refs/tags/{tag}^{{}}')
    items=dict((ln.split()[1],ln.split()[0]) for ln in out.splitlines() if len(ln.split())==2)
    sha=items.get(f'refs/tags/{tag}^{{}}') or items.get(f'refs/tags/{tag}')
    if not sha or not re.fullmatch('[a-f0-9]{40}',sha):raise RuntimeError('Tag not found: '+tag)
    return sha

def latest(name):
    req=urllib.request.Request(f'https://api.github.com/repos/storytold/{name}/releases/latest',
        headers={'Accept':'application/vnd.github+json','User-Agent':'ArtOfficeCraft-Upstream-Check/1.0'})
    with urllib.request.urlopen(req,timeout=20) as resp: j=json.load(resp)
    tag=j['tag_name'];version(tag)
    if j.get('prerelease') or j.get('draft'):raise RuntimeError('Unstable release')
    return tag

def check(engine):
    cfg=config();result={};failed=False
    for name in ENGINES if engine=='all' else (engine,):
        item=cfg['engines'][name]
        try:
            head=latest(name)
            if remote_commit(item['repo'],item['tag'])!=item['commit']:
                raise RuntimeError('Pinned GitHub tag SHA changed; refusing update')
            state='NEW' if version(head)>version(item['tag']) else 'CURRENT'
            result[name]={'pinned':item['tag'],'published':head,'state':state}
            print(f'{name}: {item["tag"]} -> {head} ({state})')
        except Exception as e:
            failed=True;result[name]={'pinned':item['tag'],'error':str(e)}
            print(f'{name}: ERROR {e}',file=sys.stderr)
    report=ROOT/'upstream'/'reports'/'latest-check.json'
    report.parent.mkdir(exist_ok=True,parents=True)
    report.write_text(json.dumps({'checked_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
                        'engines':result},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Report:',report)
    return 1 if failed else 0

def cargo_valid(folder,tag):
    item=tomllib.loads((folder/'Cargo.toml').read_text(encoding='utf-8-sig'))
    if item['workspace']['package']['version']!=tag[1:]:raise RuntimeError('Cargo version does not match tag')

def stage_one(name,tag):
    cfg=config()['engines'][name];sha=remote_commit(cfg['repo'],tag)
    if tag==cfg['tag'] and sha!=cfg['commit']:raise RuntimeError('Pinned tag moved on GitHub')
    dest=STAGED/name/f'{tag}-{sha[:12]}'
    if dest.exists():
        if git('rev-parse','HEAD',cwd=dest)!=sha or not clean_source(dest):raise RuntimeError('Staged directory is modified')
        cargo_valid(dest,tag);print(f'{name}: staged already: {dest}');return
    dest.parent.mkdir(parents=True,exist_ok=True)
    tmp=Path(tempfile.mkdtemp(prefix='.new-',dir=dest.parent))
    try:
        git('clone','--quiet','--depth','1','--single-branch','--branch',tag,
            cfg['repo'],str(tmp),timeout=900)
        if git('rev-parse','HEAD',cwd=tmp)!=sha:raise RuntimeError('Remote tag changed during download')
        cargo_valid(tmp,tag)
        (tmp/'ARTOFFICECRAFT_SOURCE_ATTESTATION.json').write_text(json.dumps(
             {'repo':cfg['repo'],'tag':tag,'commit':sha},indent=2)+'\n',encoding='utf8')
        tmp.rename(dest)
    finally:
        if tmp.exists():shutil.rmtree(tmp,ignore_errors=True)
    print(f'{name}: staged {tag} {sha[:12]} in {dest}')

def pin(name,tag,approved):
    if not approved:raise ValueError('Use --ack-review after comparing changes and dependencies')
    cfg=config();sha=remote_commit(cfg['engines'][name]['repo'],tag)
    path=STAGED/name/f'{tag}-{sha[:12]}'
    if not path.is_dir() or git('rev-parse','HEAD',cwd=path)!=sha or not clean_source(path):
        raise RuntimeError('Run stage for exact version first')
    cargo_valid(path,tag)
    history=ROOT/'upstream'/'lock-history';history.mkdir(exist_ok=True,parents=True)
    backup=history/f'lock-{datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")}.json'
    shutil.copy2(LOCK,backup)
    cfg['engines'][name].update(tag=tag,commit=sha)
    temporary=LOCK.with_suffix('.json.tmp')
    temporary.write_text(json.dumps(cfg,indent=2,ensure_ascii=False)+'\n',encoding='utf8')
    os.replace(temporary,LOCK)
    print(f'Pinned {name}: {tag}, SHA {sha}; backup {backup}')
    print('This does NOT update compiled .so / APK; Android integration/tests still required.')

def main():
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='cmd',required=True)
    sub.add_parser('status')
    c=sub.add_parser('check');c.add_argument('--engine',choices=(*ENGINES,'all'),default='all')
    s=sub.add_parser('stage');s.add_argument('--engine',choices=(*ENGINES,'all'),default='all')
    s.add_argument('--latest',action='store_true');s.add_argument('--tag')
    a=sub.add_parser('pin');a.add_argument('--engine',choices=ENGINES,required=True)
    a.add_argument('--tag',required=True);a.add_argument('--ack-review',action='store_true')
    args=p.parse_args()
    try:
        if args.cmd=='status':
            for name,item in config()['engines'].items():print(name,item['tag'],item['commit'])
        elif args.cmd=='check':return check(args.engine)
        elif args.cmd=='stage':
            if args.tag and args.engine=='all':raise ValueError('Specify only one engine with --tag')
            failed=False
            for name in ENGINES if args.engine=='all' else (args.engine,):
                try:stage_one(name,args.tag or (latest(name) if args.latest else config()['engines'][name]['tag']))
                except Exception as e: print(f'{name}: ERROR {e}',file=sys.stderr);failed=True
            return 1 if failed else 0
        else:pin(args.engine,args.tag,args.ack_review)
        return 0
    except Exception as e:
        print('ERROR:',e,file=sys.stderr);return 2

if __name__=='__main__':sys.exit(main())
