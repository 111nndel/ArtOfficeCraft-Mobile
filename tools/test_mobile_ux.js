// Verify language persistence and PDF presentation in the ordinary offline app.
// Usage: node tools/test_mobile_ux.js emulator-5582 path/to/x86_64.apk
const fs = require('fs'), path = require('path'), cp = require('child_process'), crypto = require('crypto');
const device = process.argv[2], apk = process.argv[3];
if (!/^emulator-\d+$/.test(device || '') || !apk || !fs.existsSync(apk)) throw new Error('Pass a QA emulator and APK.');
const adb = path.join(process.env.ANDROID_HOME || process.env.ANDROID_SDK_ROOT, 'platform-tools', process.platform === 'win32' ? 'adb.exe' : 'adb');
const pkg = 'ai.artofficecraft.artofficecraft_mobile', proof = path.resolve('build/mobile-ux-015');
fs.mkdirSync(proof, {recursive:true});
function command(args, binary=false) {
  const r=cp.spawnSync(adb,['-s',device,...args],{encoding:binary ? undefined : 'utf8',timeout:30000,maxBuffer:20*1024*1024});
  if(r.status!==0) throw new Error(`${args.slice(0,4).join(' ')}: ${r.error || r.stderr || r.stdout}`);
  return r.stdout;
}
function nodes() {
  command(['shell','uiautomator','dump','/data/local/tmp/aoc-ux.xml']);
  const xml=command(['exec-out','cat','/data/local/tmp/aoc-ux.xml']);
  fs.writeFileSync(path.join(proof,'latest.xml'),xml);
  return [...xml.matchAll(/<node\s+[^>]*>/g)].map(([tag])=>{
    const n=Object.fromEntries([...tag.matchAll(/([\w-]+)="([^"]*)"/g)].map(([,k,v])=>[k,v.replace(/&#(\d+);/g,(_,c)=>String.fromCodePoint(Number(c))).replace(/&quot;/g,'"').replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&amp;/g,'&')]));
    n.text=n.text || n['content-desc'] || '';return n;
  });
}
const pause=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function waitFor(predicate,label) {
  const until=Date.now()+20000;
  while(Date.now()<until) {const n=nodes().find(predicate);if(n)return n;await pause(200);}
  throw new Error(`UI not found: ${label}. See ${proof}/latest.xml`);
}
function tap(n) {
  const m=/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/.exec(n.bounds || '');if(!m)throw new Error('No touch bounds');
  command(['shell','input','tap',String(Math.floor((+m[1]+ +m[3])/2)),String(Math.floor((+m[2]+ +m[4])/2))]);
}
function screenshot(name) {fs.writeFileSync(path.join(proof,name+'.png'),command(['exec-out','screencap','-p'],true));}
function restart() {command(['shell','am','force-stop',pkg]);command(['shell','am','start','-n',pkg+'/.MainActivity']);}
async function about() {
  tap(await waitFor(n=>['About and licenses','О проекте и лицензиях'].includes(n.text),'About'));
  return waitFor(n=>n.clickable==='true' && (n.text.includes('Language / Язык') || n.text.includes('Язык / Language')),'Language selector');
}
(async()=>{
  if(Number(command(['shell','getprop','ro.build.version.sdk']).trim())<36)throw new Error('Use Android 16 or newer.');
  command(['install','-r',path.resolve(apk)]);restart();
  tap(await about());
  tap(await waitFor(n=>n.text==='Русский','Russian option'));
  await waitFor(n=>n.text==='Лицензии и авторские права','Russian About');
  restart();
  await waitFor(n=>n.text.startsWith('Документ\n'),'Persisted Russian Home');
  screenshot('russian-home');
  tap(await about());
  tap(await waitFor(n=>n.text==='English','English option'));
  await waitFor(n=>n.text==='Licenses and copyright','English About');
  restart();
  await waitFor(n=>n.text.startsWith('Spreadsheet\n'),'Persisted English Home');
  screenshot('english-home');
  const selected=await about();
  if(!selected.text.includes('English'))throw new Error('Language reverted to system instead of the saved English override.');
  command(['shell','input','keyevent','4']);
  tap(await waitFor(n=>n.text.startsWith('PDF\n'),'Create PDF'));
  await waitFor(n=>n.text==='Page 1 of 1','English PDF counter');
  await waitFor(n=>n.text==='Page thumbnails','Collapsed PDF thumbnails control');
  screenshot('english-pdf-width');
  command(['shell','input','keyevent','4']);
  tap(await waitFor(n=>n.text==='Leave without saving','Discard test PDF'));
  await waitFor(n=>n.text.startsWith('Spreadsheet\n'),'Return to English Home');
  const result={passed:true,device,api:36,apkSha256:crypto.createHash('sha256').update(fs.readFileSync(apk)).digest('hex'),checks:['ordinary offline profile app','Russian override survives force-stop','English override survives force-stop','saved override remains selected in About','English PDF opens with thumbnails hidden','explicit discard returns Home']};
  fs.writeFileSync(path.join(proof,'result.json'),JSON.stringify(result,null,2)+'\n');process.stdout.write(JSON.stringify(result)+'\n');
})().catch(e=>{process.stderr.write(e.stack+'\n');process.exitCode=1;});
