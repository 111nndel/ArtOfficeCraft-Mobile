// Exercise the ordinary offline app, outside the Flutter integration runner.
// Usage: node tools/test_recovery_force_stop.js emulator-5582 path/to/x86_64.apk
const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const crypto = require('crypto');
const device = process.argv[2];
const apk = process.argv[3];
if (!/^emulator-\d+$/.test(device || '') || !apk || !fs.existsSync(apk)) {
  throw new Error('Pass a dedicated emulator id and the ordinary x86_64 APK.');
}
const adb = path.join(process.env.ANDROID_HOME || process.env.ANDROID_SDK_ROOT, 'platform-tools', process.platform === 'win32' ? 'adb.exe' : 'adb');
const pkg = 'ai.artofficecraft.artofficecraft_mobile';
const proof = path.resolve('build/recovery-force-stop');
fs.mkdirSync(proof, {recursive:true});
function command(args, binary=false) {
  const r = cp.spawnSync(adb, ['-s',device,...args], {encoding:binary ? undefined : 'utf8', timeout:30000, maxBuffer:20*1024*1024});
  if (r.status !== 0) throw new Error(`${args.slice(0,4).join(' ')}: ${r.error || r.stderr || r.stdout}`);
  return r.stdout;
}
function nodes() {
  command(['shell','uiautomator','dump','/data/local/tmp/aoc-recovery.xml']);
  const xml=command(['exec-out','cat','/data/local/tmp/aoc-recovery.xml']);
  fs.writeFileSync(path.join(proof,'latest.xml'),xml);
  return [...xml.matchAll(/<node\s+[^>]*>/g)].map(([tag])=>{
    const node=Object.fromEntries([...tag.matchAll(/([\w-]+)="([^"]*)"/g)].map(([,k,v])=>[k,v.replace(/&#(\d+);/g,(_,code)=>String.fromCodePoint(Number(code))).replace(/&quot;/g,'"').replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&amp;/g,'&')]));
    // Flutter exposes most visible labels as Android content descriptions.
    node.text=node.text || node['content-desc'] || '';
    return node;
  });
}
const pause=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function waitFor(predicate,label) {
  const deadline=Date.now()+20000;
  while(Date.now()<deadline) {
    const all=nodes();const found=all.find(predicate);
    if(found) return found;
    await pause(200);
  }
  throw new Error(`UI not found: ${label}. See build/recovery-force-stop/latest.xml`);
}
function tap(node, yFraction=0.5) {
  const m=/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/.exec(node.bounds || '');
  if(!m) throw new Error('Missing touch bounds');
  command(['shell','input','tap',String(Math.floor((+m[1]+ +m[3])/2)),String(Math.floor(+m[2]+(+m[4]- +m[2])*yFraction))]);
}
function screenshot(name) {
  const bytes=command(['exec-out','screencap','-p'],true);
  if(bytes.subarray(0,4).toString('hex')!=='89504e47') throw new Error('Invalid screenshot');
  fs.writeFileSync(path.join(proof,name+'.png'),bytes);
}
(async()=>{
  if(Number(command(['shell','getprop','ro.build.version.sdk']).trim())<36) throw new Error('Use Android 16 or later.');
  command(['install','-r',path.resolve(apk)]);
  command(['shell','am','start','-n',pkg+'/.MainActivity']);
  tap(await waitFor(n=>(n.text.startsWith('Документ\n') || n.text.startsWith('Document\n')),'Create document'));
  // Android may merge this label into the whole page semantics bounds.
  // Touch the visible first line near the top, rather than the blank page center.
  tap(await waitFor(n=>(n.text.includes('Коснитесь, чтобы начать писать') || n.text.includes('Tap to start writing')),'Empty paragraph'),0.1);
  await waitFor(n=>n.class==='android.widget.EditText','Inline text field');
  const text='RECOVERY_FORCE_STOP_014';
  command(['shell','input','text',text]);
  await waitFor(n=>(n.text.includes('Черновик сохранён') || n.text.includes('Draft saved')),'Durable draft status');
  screenshot('before-force-stop');
  command(['shell','am','force-stop',pkg]);
  command(['shell','am','start','-n',pkg+'/.MainActivity']);
  await waitFor(n=>['Восстановить работу','Resume your work'].includes(n.text),'Home recovery section');
  screenshot('home-recovery');
  tap(await waitFor(n=>(n.text.startsWith('Новый документ.docx') || n.text.startsWith('New document.docx')),'Recovery document'));
  await waitFor(n=>n.class==='android.widget.EditText' && n.text===text,'Recovered unapplied text');
  screenshot('recovered-text');
  command(['shell','input','keyevent','4']);
  // If the system keyboard appeared, the first Back only hides it.
  let all=nodes();
  if(!all.some(n=>['Выйти без сохранения','Leave without saving'].includes(n.text))) {
    command(['shell','input','keyevent','4']);
  }
  tap(await waitFor(n=>['Выйти без сохранения','Leave without saving'].includes(n.text),'Explicit discard'));
  await waitFor(n=>n.text.includes('ArtOfficeCraft'),'Return to Home');
  const remaining=nodes();
  if(remaining.some(n=>['Восстановить работу','Resume your work'].includes(n.text))) throw new Error('Recovery entry remains after explicit discard.');
  const result={passed:true,device,api:36,text,apkSha256:crypto.createHash('sha256').update(fs.readFileSync(apk)).digest('hex'),checks:['ordinary offline app','unapplied text persisted','force-stop without orderly shutdown','fresh-process recovery UI','exact recovered text','explicit discard retires recovery']};
  fs.writeFileSync(path.join(proof,'result.json'),JSON.stringify(result,null,2)+'\n');
  process.stdout.write(JSON.stringify(result)+'\n');
})().catch(error=>{process.stderr.write(error.stack+'\n');process.exitCode=1;});
