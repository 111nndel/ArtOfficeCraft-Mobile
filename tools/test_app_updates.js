// Real updater UI and system installer on a disposable Android 16 emulator.
const fs=require('fs'),path=require('path'),cp=require('child_process');
const device=process.argv[2],apk=process.argv[3],fixture=JSON.parse(fs.readFileSync(process.argv[4]));
if(!/^emulator-\d+$/.test(device||''))throw Error('Use a dedicated emulator');
const adb=path.join(process.env.ANDROID_HOME,'platform-tools/adb'),pkg='ai.artofficecraft.artofficecraft_mobile';
const proof=path.resolve('build/app-update-qa');fs.mkdirSync(proof,{recursive:true});
function command(args,binary=false){const r=cp.spawnSync(adb,['-s',device,...args],{encoding:binary?undefined:'utf8',timeout:30000,maxBuffer:20*1024*1024});if(r.status!==0)throw Error(r.stderr||r.error||r.stdout);return r.stdout;}
const pause=ms=>new Promise(r=>setTimeout(r,ms));
function nodes(){
 command(['shell','uiautomator','dump','/data/local/tmp/aoc-updates.xml']);
 const xml=command(['exec-out','cat','/data/local/tmp/aoc-updates.xml']);fs.writeFileSync(path.join(proof,'latest.xml'),xml);
 return [...xml.matchAll(/<node\s+[^>]*>/g)].map(([tag])=>{const n=Object.fromEntries([...tag.matchAll(/([\w-]+)="([^"]*)"/g)].map(([,k,v])=>[k,v.replace(/&amp;/g,'&').replace(/&#(\d+);/g,(_,c)=>String.fromCodePoint(+c))]));n.label=n.text||n['content-desc']||'';return n;});
}
function tap(n){const m=/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/.exec(n.bounds||'');if(!m)throw Error('No bounds');command(['shell','input','tap',String((+m[1]+ +m[3])>>1),String((+m[2]+ +m[4])>>1)]);}
function matches(n,p){return p instanceof RegExp?p.test(n.label):n.label.split('\n').includes(p);}
async function wait(p){const end=Date.now()+45000;while(Date.now()<end){const n=nodes().find(n=>matches(n,p));if(n)return n;await pause(150);}throw Error('UI not found: '+p);}
async function reveal(p){for(let i=0;i<8;i++){const n=nodes().find(n=>matches(n,p));if(n)return n;command(['shell','input','swipe','540','1850','540','900','300']);await pause(150);}throw Error('Cannot reveal '+p);}
function shot(name){fs.writeFileSync(path.join(proof,name+'.png'),command(['exec-out','screencap','-p'],true));}
function requests(){const p=path.join(proof,'requests.jsonl');return fs.existsSync(p)?fs.readFileSync(p,'utf8').trim().split('\n').filter(Boolean).map(JSON.parse):[];}
function mode(value){fs.writeFileSync(path.join(proof,'mode.txt'),value);}
async function launch(){command(['shell','am','force-stop',pkg]);command(['shell','am','start','-n',pkg+'/.MainActivity']);await wait(/^Files(?:\n|$)/);}
async function about(){tap(await wait('About and licenses'));await wait(new RegExp('^'+fixture.currentVersion.replace(/\./g,'\\.')+' · Preview$'));}
async function check(){tap(await reveal('Check for updates'));await wait('Version '+fixture.nextVersion+' is available');}
async function chooseMode(label){
 for(let i=0;i<4;i++){const found=nodes().find(n=>matches(n,'Manually')||matches(n,'Automatically'));if(found){tap(found);tap(await wait(label));return;}command(['shell','input','swipe','540','750','540','1800','300']);}
 throw Error('Mode selector missing');
}
(async()=>{
 mode('valid');command(['install','-r',apk]);await launch();
 if(requests().length)throw Error('Manual startup made a network request');
 await about();await reveal('Check for updates');shot('about-current-version');
 await check();
 if(requests().some(r=>r.path.endsWith('.apk')))throw Error('Manual check downloaded APK automatically');
 for(const bad of ['corrupt','wrong-key','old-code']){
  // A fresh check selects that fixture's size/hash before every download.
  mode(bad);await check();
  tap(await reveal('Download update'));
  await wait('Could not check or download the update. Try again later.');
  if(nodes().some(n=>n.label==='Install'))throw Error('Invalid APK was offered for install: '+bad);
  shot('update-rejected-'+bad);
 }
 mode('valid');await chooseMode('Automatically');
 await wait('Version '+fixture.nextVersion+' is ready to install');shot('update-auto-ready');
 const before=requests().length;
 await launch();await about();await reveal('Check for updates');
 await wait('Version '+fixture.nextVersion+' is ready to install');
 if(requests().length!==before)throw Error('Auto restart repeated a check inside the daily interval');
 await chooseMode('Manually');
 await wait('The app contacts GitHub only when you check or download an update.');
 await launch();await about();await reveal('Check for updates');
 await wait(/^Update mode\nManually$/);
 if(requests().length!==before)throw Error('Manual restart accessed network');
 await wait('Version '+fixture.nextVersion+' is ready to install');
 tap(await reveal('Install'));
 await wait('Allow from this source');shot('update-source-permission');
 tap(await wait('Allow from this source'));command(['shell','input','keyevent','4']);
 tap(await reveal('Install'));
 await wait(/^Update$/);shot('update-system-confirmation');
 tap(await wait(/^Cancel$/));
 await wait('Version '+fixture.nextVersion+' is ready to install');
 tap(await reveal('Install'));tap(await wait(/^Update$/));
 await pause(2000);
 await wait(/^Done$|^Open$/);shot('update-system-installed');
 tap(await wait(/^Open$/));await wait(/^Files(?:\n|$)/);
 await launch();shot('update-home-after-upgrade');
 const state=command(['shell','dumpsys','package',pkg]);
 fs.writeFileSync(path.join(proof,'installed-package.txt'),state);
 if(!state.includes('versionCode='+fixture.nextCode))throw Error('New package version was not installed');
 await wait('Formatted.xlsx'); // The pre-update editor draft survives replacement.
 tap(await wait('About and licenses'));
 await wait(new RegExp('^'+fixture.nextVersion.replace(/\./g,'\\.')+' · Preview$'));
 await reveal('Check for updates');await wait('Manually');shot('update-installed-version');
 const result={passed:true,manualStartupNoNetwork:true,manualCheckNoDownload:true,automaticDownload:true,
  dailyThrottle:true,modeSurvivesRestart:true,verifiedCacheSurvivesRestart:true,
  rejected:['checksum','signingCertificate','nonIncreasingVersion'],androidPermissionScreen:true,
  installerConfirmationAndCancel:true,realSameKeyUpgrade:true,draftPreserved:true,
  installedVersion:fixture.nextVersion,installedCode:fixture.nextCode};
 fs.writeFileSync(path.join(proof,'result.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));
})().catch(e=>{console.error(e.stack);process.exitCode=1;});
