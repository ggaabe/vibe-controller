// Original deterministic electronic score. No samples or third-party recordings.
import {writeFileSync} from 'node:fs';
const sr=48000, seconds=Number(process.argv[2]??40), n=Math.round(sr*seconds);
if(!Number.isFinite(seconds)||seconds<4||seconds>300)throw new Error('Choose a duration between 4 and 300 seconds.');
const L=new Float64Array(n), R=new Float64Array(n);
let seed=78131;
const rnd=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296*2-1;};
const hz=m=>440*2**((m-69)/12);
const sin=(f,t)=>Math.sin(2*Math.PI*f*t);
function add(start,dur,fn,pan=0){const first=Math.floor(start*sr),len=Math.floor(dur*sr);for(let j=0;j<len;j++){const i=first+j;if(i>=n)break;if(i<0)continue;const v=fn(j/sr,j/len);L[i]+=v*Math.sqrt((1-pan)/2);R[i]+=v*Math.sqrt((1+pan)/2);}}
const chords=[[50,57,60,64],[46,53,57,60],[53,60,64,69],[48,55,59,62]];
for(let bar=0;bar<Math.ceil(seconds/2);bar++){
  const chord=chords[Math.floor(bar/2)%4];
  for(let k=0;k<chord.length;k++){
    const freq=hz(chord[k]);
    add(bar*2,3.5,(t)=>{const e=Math.min(t/.7,1)*Math.min((3.5-t)/1.2,1);return e*.027*(sin(freq*.998,t)+sin(freq*1.002,t)*.7+sin(freq*2,t)*.12);},(k-1.5)*.35);
  }
  for(let beat=0;beat<4;beat++){
    const start=bar*2+beat*.5;
    if(start>2 && start<seconds-4){
      add(start,.38,t=>.25*Math.sin(2*Math.PI*(43*t+2.9*(1-Math.exp(-t*22))))*Math.exp(-t*13));
      if(beat%2===1)add(start,.18,t=>rnd()*.08*Math.exp(-t*30)+sin(190,t)*.025*Math.exp(-t*35),.08);
    }
    const bass=hz(chord[0]-12);
    if(start<seconds-4)add(start,.47,t=>Math.min(t/.025,1)*Math.exp(-t*5)*.12*(sin(bass,t)+.25*sin(2*bass,t)));
  }
  for(let step=0;step<8;step++){
    const start=bar*2+step*.25;
    const freq=hz(chord[[0,2,1,3,2,1,3,2][step]]+12);
    const pan=Math.sin(step*1.9)*.65;
    if(start>1 && start<seconds-4){
      const note=(t)=>Math.min(t/.006,1)*Math.exp(-t*9)*.055*(sin(freq,t)+.24*sin(freq*2,t)+.09*sin(freq*3,t));
      add(start,.65,note,pan); add(start+.375,.65,t=>note(t)*.22,-pan);add(start+.75,.65,t=>note(t)*.1,pan);
      if(start>6)add(start+.125,.08,t=>rnd()*.019*Math.exp(-t*65),step%2===0?-.45:.45);
    }
  }
}
// Air swells bridge the six editorial moves.
for(const cut of seconds>40?[4.8,11.6,16.4,26,49.6,61.2,66]:[4.8,11.6,16.4,26,30.8]){
  let low=0;
  add(cut-.65,1.05,(t,p)=>{low=low*.83+rnd()*.17;return (rnd()-low)*Math.sin(p*Math.PI)**2*.038;},-.25);
  add(cut,.65,t=>sin(110,t)*.09*Math.exp(-t*7));
}
// A spacious resolved final chord underneath the product card.
for(const [i,m] of [50,57,60,64,69].entries())add(seconds-4,4,t=>Math.min(t/.12,1)*Math.exp(-t*.7)*.039*sin(hz(m),t),(i-2)*.3);
let peak=0;
for(let i=0;i<n;i++){const t=i/sr,fade=Math.min(t/1.1,1)*Math.min((seconds-t)/2.1,1);L[i]=Math.tanh(L[i]*1.4)*fade;R[i]=Math.tanh(R[i]*1.4)*fade;peak=Math.max(peak,Math.abs(L[i]),Math.abs(R[i]));}
const data=Buffer.alloc(44+n*4);
data.write('RIFF',0);data.writeUInt32LE(data.length-8,4);data.write('WAVEfmt ',8);data.writeUInt32LE(16,16);data.writeUInt16LE(1,20);data.writeUInt16LE(2,22);data.writeUInt32LE(sr,24);data.writeUInt32LE(sr*4,28);data.writeUInt16LE(4,32);data.writeUInt16LE(16,34);data.write('data',36);data.writeUInt32LE(n*4,40);
const gain=.8/peak;
for(let i=0;i<n;i++){data.writeInt16LE(Math.round(L[i]*gain*32767),44+i*4);data.writeInt16LE(Math.round(R[i]*gain*32767),46+i*4);}
writeFileSync(new URL(`./public/${process.argv[3]??'score.wav'}`,import.meta.url),data);
console.log(`Original score: ${seconds}s stereo, peak ${20*Math.log10(.8)} dBFS`);
