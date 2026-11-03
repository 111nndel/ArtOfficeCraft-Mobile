// Ordinary Android 16 app: real SAF filter/import and touch-only size changes.
// Uses only a dedicated emulator and generated QA files under Download/AOC-QA-018.
// Run: node tools/test_grid_touch_import.js emulator-5582 path/to/x86_64.apk
const fs=require('fs'), path=require('path'), cp=require('child_process');
const device=process.argv[2], apk=process.argv[3];
if(!/^emulator-\d+$/.test(device||'') || !apk || !fs.existsSync(apk))throw Error('Pass a QA emulator and APK');
const adb=path.join(process.env.ANDROID_HOME||process.env.ANDROID_SDK_ROOT,'platform-tools',process.platform==='win32'?'adb.exe':'adb');
const proof=path.resolve('build/grid-touch-import-018'),pkg='ai.artofficecraft.artofficecraft_mobile';
fs.mkdirSync(proof,{recursive:true});
function command(args,binary=false){
  const r=cp.spawnSync(adb,['-s',device,...args],{encoding:binary?undefined:'utf8',timeout:30000,maxBuffer:20*1024*1024});
  if(r.status!==0)throw Error(`${args.slice(0,4).join(' ')}: ${r.stderr||r.error||r.stdout}`);
  return r.stdout;
}
const pause=ms=>new Promise(r=>setTimeout(r,ms));
function nodes(){
  command(['shell','uiautomator','dump','/data/local/tmp/aoc-grid018.xml']);
  const xml=command(['exec-out','cat','/data/local/tmp/aoc-grid018.xml']);fs.writeFileSync(path.join(proof,'latest.xml'),xml);
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
(async()=>{
  if(Number(command(['shell','getprop','ro.build.version.sdk']).trim())<36)throw Error('Use Android 16 or newer');
  command(['install','-r',path.resolve(apk)]);
  command(['shell','am','force-stop',pkg]);command(['shell','am','start','-n',pkg+'/.MainActivity','-f','0x10008000']);
  await waitFor(/^Files(?:\n|$)/);
  const directory='/sdcard/Download/AOC-QA-018';command(['shell','mkdir','-p',directory]);
  command(['push',path.resolve('test/fixtures/formatted-grid.xlsx'),directory+'/Formatted.xlsx']);
  fs.writeFileSync(path.join(proof,'unrelated.txt'),'QA distraction, not an office document');
  command(['push',path.join(proof,'unrelated.txt'),directory+'/unrelated.txt']);
  const types={Document:'application/vnd.openxmlformats-officedocument.wordprocessingml.document',Spreadsheet:'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',Presentation:'application/vnd.openxmlformats-officedocument.presentationml.presentation',PDF:'application/pdf'};
  const verified=[];
  for(const [kind,mime] of Object.entries(types)){
    await openPicker(kind);
    const state=command(['shell','dumpsys','activity','activities']);fs.writeFileSync(path.join(proof,'intent-'+kind+'.txt'),state);
    if(!state.includes('typ='+mime))throw Error(`Missing runtime MIME filter ${kind}`);
    verified.push({kind,mime});shot('picker-'+kind);
    command(['shell','input','keyevent','4']);await pause(300);
  }
  await openPicker('Spreadsheet');
  tap(await waitFor(/^Show roots$|^Open navigation drawer$/));
  // ADB-pushed fixtures are not DownloadManager entries; browse the real storage root.
  tap(await waitFor(n=>/^sdk_gphone/.test(n.label) && n['resource-id']==='android:id/title','Emulator storage root'));
  tap(await waitFor('Download'));
  tap(await waitFor('AOC-QA-018'));
  shot('filtered-xlsx-folder');
  tap(await waitFor('Formatted.xlsx'));
  await waitFor(/Imported merged title/);shot('imported-layout');
  const columnPattern=/^A(?:,|\n|$)/, rowPattern=/^4(?:,|\n|$)/;
  const colBefore=rect(await waitFor(columnPattern));
  await dragHeld(await waitFor(columnPattern),140,0);
  await pause(700);
  const colAfter=rect(await waitFor(columnPattern));
  if(colAfter.w-colBefore.w<110)throw Error(`Column drag did not change width: ${colBefore.w} -> ${colAfter.w}`);
  const rowBefore=rect(await waitFor(rowPattern));
  await dragHeld(await waitFor(rowPattern),0,-90);
  await pause(700);
  const rowAfter=rect(await waitFor(rowPattern));
  if(rowBefore.h-rowAfter.h<60)throw Error(`Row drag did not change height: ${rowBefore.h} -> ${rowAfter.h}`);
  shot('touch-resized');
  tap(await waitFor('Undo'));await pause(500);
  const restored=rect(await waitFor(rowPattern));
  if(Math.abs(restored.h-rowBefore.h)>4)throw Error('Undo did not restore row height');
  tap(await waitFor('Redo'));await pause(500);
  shot('touch-redone');
  const result={passed:true,types:verified,columnPixels:{before:colBefore.w,after:colAfter.w},rowPixels:{before:rowBefore.h,after:rowAfter.h,undo:restored.h},device,api:36};
  fs.writeFileSync(path.join(proof,'result.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
})().catch(e=>{console.error(e.stack);process.exitCode=1;});
