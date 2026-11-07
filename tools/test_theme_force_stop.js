// Ordinary offline APK: prove the saved appearance survives real Android exits.
const fs = require('fs'), path = require('path'), cp = require('child_process'), zlib = require('zlib');
const device = process.argv[2], apk = process.argv[3];
if (!/^emulator-\d+$/.test(device || '') || !fs.existsSync(apk || '')) throw new Error('Pass a dedicated QA emulator and ordinary APK.');
const adb = path.join(process.env.ANDROID_HOME || process.env.ANDROID_SDK_ROOT, 'platform-tools', process.platform === 'win32' ? 'adb.exe' : 'adb');
const pkg = 'ai.artofficecraft.artofficecraft_mobile', proof = path.resolve('build/theme-force-stop-017');
fs.mkdirSync(proof, {recursive:true});
function command(args, binary=false) {
  const r=cp.spawnSync(adb,['-s',device,...args],{encoding:binary ? undefined : 'utf8',timeout:30000,maxBuffer:24*1024*1024});
  if(r.status!==0) throw new Error(String(r.error || r.stderr || r.stdout));
  return r.stdout;
}
function nodes() {
  command(['shell','uiautomator','dump','/data/local/tmp/aoc-theme.xml']);
  const xml=command(['exec-out','cat','/data/local/tmp/aoc-theme.xml']);
  fs.writeFileSync(path.join(proof,'latest.xml'),xml);
  return [...xml.matchAll(/<node\s+[^>]*>/g)].map(([s])=>Object.fromEntries([...s.matchAll(/([\w-]+)="([^"]*)"/g)].map(([,k,v])=>[k,v])));
}
async function ready() {
  for(let n=0;n<12;n++) {
    const button=nodes().find(n=>['Change theme','Изменить тему'].includes(n['content-desc'] || n.text));
    if(button) return button;
    await new Promise(r=>setTimeout(r,250));
  }
  throw new Error('Home theme button not found');
}
// Decode Android's 8-bit RGB/RGBA PNG to inspect actual scaffold pixels,
// independently of the app's own preference file and widget state.
function appearance(png) {
  let offset=8, width, height, channels, idat=[];
  while(offset<png.length) {
    const len=png.readUInt32BE(offset), type=png.toString('ascii',offset+4,offset+8), data=png.subarray(offset+8,offset+8+len);
    if(type==='IHDR') {
      width=data.readUInt32BE(0); height=data.readUInt32BE(4);
      if(data[8]!==8 || ![2,6].includes(data[9])) throw new Error('Unsupported screenshot PNG');
      channels=data[9]===6?4:3;
    }
    if(type==='IDAT') idat.push(data);
    offset+=len+12;
  }
  const raw=zlib.inflateSync(Buffer.concat(idat)), stride=width*channels, pixels=Buffer.alloc(stride*height);
  let input=0;
  for(let y=0;y<height;y++) {
    const filter=raw[input++];
    for(let x=0;x<stride;x++) {
      const i=y*stride+x, a=x>=channels?pixels[i-channels]:0, b=y?pixels[i-stride]:0, c=y&&x>=channels?pixels[i-stride-channels]:0;
      let predictor=0;
      if(filter===1) predictor=a;
      else if(filter===2) predictor=b;
      else if(filter===3) predictor=Math.floor((a+b)/2);
      else if(filter===4) { const p=a+b-c, pa=Math.abs(p-a), pb=Math.abs(p-b), pc=Math.abs(p-c); predictor=pa<=pb&&pa<=pc?a:pb<=pc?b:c; }
      else if(filter!==0) throw new Error('Unknown PNG filter');
      pixels[i]=(raw[input++]+predictor)&255;
    }
  }
  const samples=[];
  for(let n=0;n<30;n++) for(const x of [2,width-3]) {
    const i=(Math.floor(height*(.2+n*.02))*width+x)*channels;
    samples.push((pixels[i]+pixels[i+1]+pixels[i+2])/3);
  }
  samples.sort((a,b)=>a-b);
  const median=samples[Math.floor(samples.length/2)];
  if(median<80) return 'dark';
  if(median>180) return 'light';
  throw new Error('Ambiguous scaffold appearance: '+median);
}
function capture(name, expected) {
  const png=command(['exec-out','screencap','-p'],true);
  fs.writeFileSync(path.join(proof,name+'.png'),png);
  const mode=appearance(png);
  if(expected && mode!==expected) throw new Error(`${name}: expected ${expected}, saw ${mode}`);
  return mode;
}
async function toggle() {
  const n=await ready(), m=/\[(\d+),(\d+)\]\[(\d+),(\d+)\]/.exec(n.bounds);
  command(['shell','input','tap',String(Math.floor((+m[1]+ +m[3])/2)),String(Math.floor((+m[2]+ +m[4])/2))]);
  await new Promise(r=>setTimeout(r,700));
}
async function restart() {
  command(['shell','am','force-stop',pkg]);
  command(['shell','am','start','-n',pkg+'/.MainActivity']);
  await ready();
}
(async()=>{
  if(Number(command(['shell','getprop','ro.build.version.sdk']).trim())<36) throw new Error('Android 16 QA device required');
  command(['install','-r',path.resolve(apk)]);
  await restart();
  if(capture('initial')==='dark') await toggle();
  capture('light-selected','light');
  await toggle(); capture('dark-selected','dark');
  for(let n=1;n<=3;n++) {await restart(); capture('dark-cold-'+n,'dark');}
  command(['shell','input','keyevent','4']);
  command(['shell','am','start','-n',pkg+'/.MainActivity']);
  await ready(); capture('dark-after-back-exit','dark');
  await toggle(); capture('light-again','light');
  await restart(); capture('light-cold','light');
  const result={passed:true,device,checks:['dark survives three actual force-stops','dark survives Back exit','light persists too','actual rendered pixels verified']};
  fs.writeFileSync(path.join(proof,'result.json'),JSON.stringify(result,null,2)+'\n');
  process.stdout.write(JSON.stringify(result)+'\n');
})().catch(e=>{process.stderr.write(e.stack+'\n');process.exitCode=1;});
