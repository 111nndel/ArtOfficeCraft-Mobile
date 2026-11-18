// Ordinary Android 16 app: recent copies survive restart and an optional APK update.
// Uses only a dedicated emulator and generated QA files under Download/AOC-QA-018.
// Run: node tools/test_recent_imports.js emulator-5582 baseline.apk [update.apk]
const fs=require('fs'), path=require('path'), cp=require('child_process');
const device=process.argv[2], apk=process.argv[3], update=process.argv[4];
if(!/^emulator-\d+$/.test(device||'') || !apk || !fs.existsSync(apk) || (update && !fs.existsSync(update)))throw Error('Pass a QA emulator and APK');
const adb=path.join(process.env.ANDROID_HOME||process.env.ANDROID_SDK_ROOT,'platform-tools',process.platform==='win32'?'adb.exe':'adb');
const proof=path.resolve('build/recents-021'),pkg='ai.artofficecraft.artofficecraft_mobile';
fs.mkdirSync(proof,{recursive:true});
function command(args,binary=false){
  const r=cp.spawnSync(adb,['-s',device,...args],{encoding:binary?undefined:'utf8',timeout:30000,maxBuffer:20*1024*1024});
  if(r.status!==0)throw Error(`${args.slice(0,4).join(' ')}: ${r.stderr||r.error||r.stdout}`);
  return r.stdout;
}
const pause=ms=>new Promise(r=>setTimeout(r,ms));
function nodes(){
  command(['shell','uiautomator','dump','/data/local/tmp/aoc-recents021.xml']);
  const xml=command(['exec-out','cat','/data/local/tmp/aoc-recents021.xml']);fs.writeFileSync(path.join(proof,'latest.xml'),xml);
  return [...xml.matchAll(/<node\s+[^>]*>/g)].map(([tag])=>{
    const n=Object.fromEntries([...tag.matchAll(/([\w-]+)="([^"]*)"/g)].map(([,k,v])=>[k,v.replace(/&#(\d+);/g,(_,c)=>String.fromCodePoint(Number(c))).replace(/&quot;/g,'"').replace(/&amp;/g,'&')]));
    n.label=n.text||n['content-desc']||''; return n;
  });
}
async function waitFor(pattern,label=String(pattern)){
  const end=Date.now()+20000;
  while(Date.now()<end){const n=nodes().find(n=>typeof pattern==='function'?pattern(n):pattern instanceof RegExp?pattern.test(n.label):n.label===pattern);if(n)return n;await pause(150);}
  throw Error(`UI not found: ${label}`);
}
function rect(n){const m=/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/.exec(n.bounds||'');if(!m)throw Error('Missing bounds');return {x:+m[1],y:+m[2],w:+m[3]-m[1],h:+m[4]-m[2]};}
function tap(n){const r=rect(n);command(['shell','input','tap',String(Math.round(r.x+r.w/2)),String(Math.round(r.y+r.h/2))]);}
function shot(name){fs.writeFileSync(path.join(proof,name+'.png'),command(['exec-out','screencap','-p'],true));}
async function dragHeld(n,dx,dy){
  const r=rect(n),x=Math.round(r.x+r.w/2),y=Math.round(r.y+r.h/2);
  command(['shell','input','touchscreen','motionevent','DOWN',String(x),String(y)]);
  try {
    await pause(800); // Stay still until long press wins the gesture arena.
    command(['shell','input','touchscreen','motionevent','MOVE',String(x+dx),String(y+dy)]);
    await pause(150);
  } finally {
    command(['shell','input','touchscreen','motionevent','UP',String(x+dx),String(y+dy)]);
  }
}
async function openPicker(kind){
  tap(await waitFor(/^Files(?:\n|$)/));
  let button;
  for(let i=0;i<5;i++) {
    button=nodes().find(n=>n.label==='Open a file from this device');
    if(button && rect(button).h>110)break;
    command(['shell','input','swipe','540','1700','540','1100','350']);
    await pause(250);
  }
  if(!button)throw Error('Open button missing');
  tap(button);
  await waitFor('Which file would you like to open?');
  tap(await waitFor(new RegExp('^'+kind+'(?:\\n|$)')));
  await pause(500);
}
async function selectFixture(name) {
  if(!nodes().some(n=>n.label==='Open from')) tap(await waitFor(/^Show roots$|^Open navigation drawer$/));
  tap(await waitFor(n=>/^sdk_gphone/.test(n.label) && n['resource-id']==='android:id/title','Emulator storage'));
  tap(await waitFor('Download'));
  tap(await waitFor('AOC-QA-021'));
  // DocumentsUI may retain grid mode and older fixture files across QA runs.
  // Reach the generated file instead of assuming its title is on the first screen.
  let selected;
  for(let i=0;i<20;i++) {
    selected=nodes().find(n=>n.label===name);
    if(selected)break;
    command(['shell','input','swipe','540','2000','540','900','350']);
    await pause(250);
  }
  if(!selected)throw Error('Fixture not visible: '+name);
  tap(selected);
  await waitFor(n=>n.package===pkg && n.label.startsWith(name),'Opened '+name);
  await pause(800);
}

async function reveal(pattern) {
  const match=n=>typeof pattern==='function'?pattern(n):n.label===pattern;
  const visible=nodes().find(match);
  if(visible && rect(visible).h>0)return visible;
  // A selection toolbar can appear above the current scroll position.
  for(let i=0;i<3;i++) {
    command(['shell','input','swipe','540','850','540','2000','250']);
  }
  for(let i=0;i<10;i++) {
    const node=nodes().find(n=>typeof pattern==='function'?pattern(n):n.label===pattern);
    if(node && rect(node).h>0)return node;
    command(['shell','input','swipe','540','1850','540','850','300']);
    await pause(200);
  }
  throw Error('Could not reveal '+String(pattern)+'; visible labels: '+JSON.stringify(nodes().map(n=>n.label).filter(Boolean)));
}
async function freshHome() {
  command(['shell','am','force-stop',pkg]);
  command(['shell','am','start','-n',pkg+'/.MainActivity','-f','0x10008000']);
  await waitFor(/^Files(?:\n|$)/);
}
async function historyAction(label) {
  tap(await reveal('Recent file actions'));
  tap(await waitFor(label));
}
async function clearHistory() {
  await historyAction('Clear all recents');
  await waitFor('Clear all recents?');
  tap(await waitFor('Clear'));
  await waitFor('Removed from recents');
}

(async()=>{
  if(Number(command(['shell','getprop','ro.build.version.sdk']).trim())<36)throw Error('Use Android 16 or newer');
  command(['install','-r',path.resolve(apk)]);
  command(['shell','am','force-stop',pkg]);
  command(['shell','am','start','-n',pkg+'/.MainActivity','-f','0x10008000']);
  await waitFor(/^Files(?:\n|$)/);
  const runKey='Recent-'+Date.now(),first=runKey+'-A.xlsx',second=runKey+'-B.xlsx',directory='/sdcard/Download/AOC-QA-021';
  command(['shell','mkdir','-p',directory]);
  for(const name of [first,second])command(['push',path.resolve('test/fixtures/formatted-grid.xlsx'),directory+'/'+name]);
  await openPicker('Spreadsheet');
  await selectFixture(first);
  tap(await waitFor('File menu'));
  tap(await waitFor('Open XLSX'));
  await selectFixture(second);
  command(['shell','input','keyevent','4']);
  await pause(600);
  command(['shell','am','force-stop',pkg]);
  if(update)command(['install','-r',path.resolve(update)]);
  command(['shell','am','start','-n',pkg+'/.MainActivity','-f','0x10008000']);
  tap(await waitFor(n=>n.class==='android.widget.EditText','Find a file'));
  command(['shell','input','text',runKey]);
  command(['shell','input','keyevent','4']);
  const a=await waitFor(n=>n.label.startsWith(first),'First recent survives');
  await waitFor(n=>n.label.startsWith(second),'Second recent survives');
  shot('both-recents-after-force-stop');
  tap(a); await waitFor(n=>n.label.startsWith(first),'Reopened first');
  await waitFor(/Imported merged title/);
  command(['shell','input','keyevent','4']);
  tap(await waitFor(n=>n.label.startsWith(second),'Second recent'));
  await waitFor(n=>n.label.startsWith(second),'Reopened second');
  await waitFor(/Imported merged title/);

  // A history entry is a view onto a retained copy, not permission to delete it.
  command(['shell','input','keyevent','4']);
  await freshHome();
  const row=rect(await reveal(n=>n.label.startsWith(second)));
  const star=nodes().find(n=>n.label==='Add to favorites' &&
    rect(n).y+rect(n).h/2>=row.y && rect(n).y+rect(n).h/2<=row.y+row.h);
  if(!star)throw Error('Favorite action missing for second copy');
  tap(star);
  await waitFor('Remove from favorites');

  await freshHome();
  await historyAction('Clear all recents');
  await waitFor('Clear all recents?');
  tap(await waitFor('Cancel'));
  await reveal(n=>n.label.startsWith(second));
  shot('clear-cancel-retains-history');

  // Long press and batch removal must share the same reversible behavior.
  await freshHome();
  const item=await reveal(n=>n.label.startsWith(second));
  const bounds=rect(item),x=Math.round(bounds.x+bounds.w/2),y=Math.round(bounds.y+bounds.h/2);
  command(['shell','input','swipe',String(x),String(y),String(x),String(y),'900']);
  tap(await reveal('Select all'));
  await waitFor('Selected: 2');
  tap(await waitFor('Remove from recents'));
  await waitFor('Removed from recents');
  tap(await waitFor('Undo'));
  await reveal(n=>n.label.startsWith(second));

  await freshHome();
  await clearHistory();
  tap(await waitFor('Undo'));
  await reveal(n=>n.label.startsWith(second));
  await freshHome();
  await clearHistory();
  await freshHome();
  await reveal(n=>n.label.split('\n').includes('No recent files yet'));
  shot('recent-history-cleared-after-restart');

  tap(await waitFor(/^Favorites(?:\n|$)/));
  await reveal(n=>n.label.startsWith(second));
  tap(await waitFor(/^Files(?:\n|$)/));
  tap(await reveal(n=>n.label.startsWith(first)));
  await waitFor(/Imported merged title/);
  command(['shell','input','keyevent','4']);
  tap(await waitFor(/^Home(?:\n|$)/));
  await reveal(n=>n.label.startsWith(first));
  await historyAction('Select documents');
  tap(await reveal('Select all'));
  await waitFor('Selected: 1');
  tap(await waitFor('Remove from recents'));
  await waitFor('Removed from recents');
  await reveal(n=>n.label.split('\n').includes('No recent files yet'));
  shot('single-reopened-copy-removed');

  tap(await waitFor(/^Files(?:\n|$)/));
  tap(await reveal(n=>n.label.startsWith(first)));
  await waitFor(/Imported merged title/);
  if(nodes().some(n=>n.label.includes('Removed from recents')))throw Error('History feedback followed the document into its editor');
  shot('history-feedback-absent-in-editor');
  command(['shell','input','keyevent','4']);
  tap(await waitFor(/^Home(?:\n|$)/));
  await clearHistory();
  await pause(6000);
  const expired=nodes();
  if(expired.some(n=>n.label.includes('Removed from recents') || n.label==='Undo'))throw Error('History feedback did not expire');
  await reveal(n=>n.label.split('\n').includes('No recent files yet'));
  shot('history-feedback-expired');

  const result={passed:true,device,api:36,installedUpdate:Boolean(update),files:[first,second],checks:['real Android file picker','second import from inside editor','force-stop and fresh process','both recent copies retained','both copies reopened','clear cancellation retains history','long press and batch removal with undo','clear all with undo','cleared history survives restart','favorites retained','hidden copy reopened from Files','reopened copy returns to recents without a duplicate','single entry removal','history feedback absent in editors','history feedback expires without restoring entries']};
  fs.writeFileSync(path.join(proof,'result.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
})().catch(e=>{console.error(e.stack);process.exitCode=1;});
