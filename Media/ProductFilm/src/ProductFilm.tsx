import React from 'react';
import {AbsoluteFill, AnimatedImage, Img, Sequence, staticFile, useCurrentFrame} from 'remotion';
import {Backdrop, BLUE, ease, FooterBrand, Headline, Kicker, lin, Pointer, Scene} from './design';
import {HeroController, MacWorld} from './Devices';
import {Audio} from '@remotion/media';
import {Workflow} from './Workflow';
import {WORKFLOW_START,OCR_START,CHOICE_START,OUTRO_START,SCREENSHOT_DURATION,OCR_DURATION} from './workflowState';

const Dot = ({color}:{color:string}) => <span style={{width:11,height:11,borderRadius:50,background:color,display:'inline-block'}}/>;

const AppWindow = ({live=false}:{live?:boolean}) => <div style={{width:1100,height:744,borderRadius:20,overflow:'hidden',background:'#191c21',border:'1px solid #ffffff36',boxShadow:'0 45px 100px #0009, 0 2px 3px #ffffff18 inset'}}>
  <div style={{height:42,background:'#252b32',display:'flex',alignItems:'center',gap:9,padding:'0 16px',borderBottom:'1px solid #ffffff0b'}}>
    <Dot color="#fa6b67"/><Dot color="#e4b357"/><Dot color="#53bb76"/>
    <div style={{margin:'auto',paddingRight:50,fontSize:13,fontWeight:600,color:'#b4bdcb'}}>Vibe Controller</div>
  </div>
  <div style={{height:67,display:'flex',alignItems:'center',padding:'0 24px',background:'#22272e',gap:12,borderBottom:'1px solid #ffffff10'}}>
    <Img src={staticFile('app-icon.png')} style={{width:36,height:36,borderRadius:9}}/>
    <div><div style={{fontSize:19,fontWeight:700,letterSpacing:-.5}}>Vibe Controller</div><div style={{fontSize:10,color:'#8e99a9',marginTop:3}}>Xbox Controller · USB · Direct HID</div></div>
    <div style={{marginLeft:'auto',color:'#71d7a3',fontSize:11,background:'#43806524',borderRadius:15,padding:'5px 10px'}}>● Ready</div>
    <span style={{fontSize:11,marginLeft:12,color:'#aab4c4'}}>Enabled</span><div style={{width:35,height:19,borderRadius:15,background:'#4387ff',padding:2}}><div style={{width:15,height:15,borderRadius:15,background:'#fff',marginLeft:16}}/></div>
  </div>
  <div style={{height:597,position:'relative',overflow:'hidden'}}>
    {!live && <Img src={staticFile('app-xbox.jpg')} style={{position:'absolute',width:1375,height:770,maxWidth:'none',left:-274,top:-84}}/>}
    {live && <div style={{position:'absolute',inset:0,background:'#232831'}}><div style={{height:66,padding:'18px 29px',display:'flex',alignItems:'center',gap:24,fontSize:13,color:'#a9b4c4'}}><strong style={{fontSize:24,color:'#f1f4fb',marginRight:'auto'}}>Controller map</strong><span>All Apps</span><span style={{padding:'7px 13px',color:BLUE,background:'#37577b50',borderRadius:7}}>Default</span><span style={{color:'#68d7a0'}}>● Live input</span></div><AnimatedImage src={staticFile('xbox-live-feedback.gif')} width={800} height={528} style={{position:'absolute',left:150,top:67}}/></div>}
  </div>
  <div style={{height:38,background:'#232a32',display:'flex',alignItems:'center',padding:'0 23px',justifyContent:'space-between',fontSize:11,color:'#91a0b5'}}><span style={{color:'#68d7a0'}}>● Universal Control ready</span><span>Customizable. Connected. Yours.</span></div>
</div>;

const FloatingControl = ({label,action,detail,x,y,start,z=160,icon}:{label:string,action:string,detail:string,x:number,y:number,start:number,z?:number,icon?:React.ReactNode}) => {
  const f=useCurrentFrame();const p=ease(f,start,start+30);
  return <div style={{position:'absolute',left:x,top:y,width:290,padding:'25px 27px',borderRadius:18,background:'linear-gradient(135deg,#283c57ef,#182336f5)',border:'1px solid #8fc2ff80',boxShadow:'0 30px 60px #0007, 0 0 55px #3888ff18',opacity:p,transform:`translateZ(${p*z}px) translateY(${(1-p)*45}px)`,backfaceVisibility:'hidden'}}>
    <div style={{display:'flex',alignItems:'center',gap:14,marginBottom:17}}><div style={{minWidth:47,height:43,padding:'0 9px',border:'1px solid #859bbb70',borderRadius:11,display:'flex',alignItems:'center',justifyContent:'center',background:'#0c1623',fontSize:17,fontWeight:700,color:BLUE}}>{icon??label}</div><span style={{color:'#b2c1d6',fontSize:14}}>{label}</span></div>
    <div style={{fontSize:28,fontWeight:600,letterSpacing:-.8}}>{action}</div>
    <div style={{marginTop:8,fontSize:14,color:'#a1b0c4'}}>{detail}</div>
  </div>;
};

const Intro = () => {
  const f=useCurrentFrame();
  return <Scene duration={156}><Backdrop/><div style={{position:'absolute',inset:0,opacity:ease(f,0,32),transform:`scale(${ease(f,0,120,1.08,1)})`}}><HeroController/></div>
    <div style={{position:'absolute',left:100,top:300,width:650}}><Kicker>A new way to Mac</Kicker><Headline lines={['Your controller.','Your workspace.']} size={88} delay={7}/><div style={{fontSize:24,lineHeight:1.5,color:'#a5b3c8',marginTop:30,opacity:ease(f,37,63)}}>A familiar feel.<br/>A whole new kind of control.</div></div>
    <div style={{position:'absolute',left:1100,top:854,display:'flex',gap:12,alignItems:'center',color:'#b8c6db',opacity:ease(f,61,83),fontSize:16}}><span style={{width:7,height:7,background:BLUE,borderRadius:20,boxShadow:`0 0 18px ${BLUE}`}}/> Xbox + PlayStation</div>
    <FooterBrand chapter="01 / FEEL AT HOME"/>
  </Scene>;
};

const Interface = () => {
  const f=useCurrentFrame();
  return <Scene duration={216}><Backdrop/>
    <div style={{position:'absolute',left:98,top:128,zIndex:20}}><Kicker>Built around you</Kicker><Headline lines={['Every control.','In your control.']} size={72}/></div>
    <div style={{position:'absolute',left:635,top:175,width:1100,height:744,perspective:1900}}>
      <div style={{position:'absolute',transformStyle:'preserve-3d',transform:`rotateX(${ease(f,0,210,12,5)}deg) rotateY(${ease(f,0,210,-25,-14)}deg) rotateZ(-5deg) scale(${ease(f,0,150,.92,1)})`}}>
        <AppWindow/>
        <FloatingControl label="LEFT STICK" action="Move naturally." detail="Analog control. Pixel-level precision." x={-235} y={335} start={30} z={160} icon={<span style={{fontSize:28}}>◎</span>}/>
        <FloatingControl label="A" action="Click. Just like that." detail="Your primary click, under your thumb." x={600} y={486} start={72} z={230}/>
        <FloatingControl label="LT" action="Grab and drag." detail="Hold the trigger. Move the stick." x={677} y={-3} start={115} z={165}/>
      </div>
    </div>
    <div style={{position:'absolute',left:103,top:507,width:360,color:'#95a5bd',fontSize:23,lineHeight:1.55,opacity:ease(f,115,145)}}>Turn buttons, sticks, and triggers into the way you work.</div>
    <FooterBrand chapter="02 / MAKE IT YOURS"/>
  </Scene>;
};

const Modifiers = () => {
  const f=useCurrentFrame(); const held=f>37;
  const p=ease(f,37,76);
  return <Scene duration={156}><Backdrop warm/>
    <div style={{position:'absolute',left:98,top:150,width:690}}><Kicker>One more layer</Kicker><Headline lines={['Hold a button.','Unlock more.']} size={80}/><p style={{fontSize:23,color:'#a1afc4',lineHeight:1.55,marginTop:28,width:510,opacity:ease(f,17,40)}}>Modifier shortcuts when you need them.<br/>Your everyday controls when you don’t.</p></div>
    <div style={{position:'absolute',left:975,top:190,perspective:1400,transform:`rotate(-5deg) translateY(${Math.sin(f/55)*8}px)`}}>
      <div style={{width:650,height:535,transformStyle:'preserve-3d',transform:'rotateY(-16deg) rotateX(12deg)'}}>
        <div style={{position:'absolute',inset:0,background:'#191f2d',border:'1px solid #899bc441',borderRadius:28,boxShadow:'0 45px 100px #0009',padding:35}}>
          <div style={{fontSize:15,color:'#8493ab',letterSpacing:2}}>MAPPING LAYER</div>
          <div style={{display:'flex',gap:10,marginTop:24,fontSize:19}}><div style={{padding:'15px 23px',background:held?'#222b3c':'#355582',borderRadius:12}}>Default</div><div style={{padding:'15px 23px',background:held?'#3c76bb':'#222b3c',color:held?'#fff':'#8e9aaf',borderRadius:12}}>LB held</div></div>
          <div style={{borderTop:'1px solid #ffffff10',marginTop:35,paddingTop:28,fontSize:14,color:'#8c9eb7'}}>D-PAD RIGHT</div>
          <div style={{fontSize:31,marginTop:16,opacity:1-p}}>Switch Space Right</div>
          <div style={{position:'absolute',bottom:32,fontSize:14,color:'#8fa1bb'}}>Release LB to return to your default mapping.</div>
        </div>
        <div style={{position:'absolute',left:80,top:225,width:540,height:175,borderRadius:19,background:'linear-gradient(130deg,#294b7c,#142943)',border:'1px solid #8fbdff',boxShadow:'0 35px 55px #0008',padding:29,opacity:p,transform:`translateZ(${p*160}px) translateY(${-p*7}px)`}}>
          <div style={{display:'flex',alignItems:'center',gap:16}}><span style={{fontSize:19,color:BLUE}}>LB</span><span style={{fontSize:17,color:'#8399b8'}}>+</span><span style={{fontSize:25}}>→</span><span style={{marginLeft:'auto',fontSize:13,color:'#94bcf3'}}>MODIFIER SHORTCUT</span></div>
          <div style={{marginTop:21,fontSize:37,fontWeight:600,letterSpacing:-1}}>Cross Edge Right <span style={{color:BLUE}}>↗</span></div>
        </div>
      </div>
    </div>
    <div style={{position:'absolute',left:100,top:820,fontSize:18,color:'#8da4c1',opacity:ease(f,80,105)}}>App-specific mappings. System-wide fallback.</div>
    <FooterBrand chapter="03 / GO A LITTLE FURTHER"/>
  </Scene>;
};

const Handoff = () => {
  const f=useCurrentFrame(); const progress=lin(f,42,245,.08,2.94); const active=Math.floor(progress);
  return <Scene duration={300}><Backdrop/>
    <div style={{position:'absolute',top:99,width:'100%',zIndex:10,textAlign:'center'}}><Kicker>Native Universal Control</Kicker><Headline lines={['One controller. Across your Macs.']} size={74} centered/></div>
    <div style={{position:'absolute',inset:0,top:-45}}><MacWorld/></div>
    <div style={{position:'absolute',top:860,left:355,right:320,display:'flex',justifyContent:'space-between',fontSize:15,letterSpacing:2,color:'#a6b6cd'}}>{['LEAD MAC','SECOND MAC','THIRD MAC'].map((s,i)=><div key={s} style={{display:'flex',gap:12,alignItems:'center',color:active===i?'#cbe3ff':'#788aa6'}}><span style={{width:7,height:7,borderRadius:20,background:active===i?BLUE:'#394c66',boxShadow:active===i?`0 0 20px ${BLUE}`:undefined}}/>{s}</div>)}</div>
    <div style={{position:'absolute',left:0,right:0,top:929,textAlign:'center',fontSize:23,color:'#c1ccdc',opacity:ease(f,122,149)}}>Install on the lead Mac. <span style={{color:'#7c94b2'}}>Nothing to install on your other Macs.</span></div>
    <div style={{position:'absolute',left:0,right:0,top:974,textAlign:'center',fontSize:13,color:'#71809a'}}>Illustrated handoff · Universal Control configured in macOS · Virtual Hardware Support on lead Mac</div>
    <FooterBrand chapter="04 / STAY IN THE FLOW"/>
  </Scene>;
};

const Choice = () => {
  const f=useCurrentFrame();
  return <Scene duration={156}><Backdrop warm/>
    <div style={{position:'absolute',top:108,width:'100%',textAlign:'center'}}><Kicker>Made for your favorite controller</Kicker><Headline lines={['Choose your controller.']} size={85} centered/></div>
    <div style={{position:'absolute',inset:0,top:90,opacity:ease(f,0,25)}}><HeroController pair/></div>
    <div style={{position:'absolute',top:835,left:420,fontSize:19,letterSpacing:3,color:'#c0ccdd'}}>XBOX</div>
    <div style={{position:'absolute',top:835,right:365,fontSize:19,letterSpacing:3,color:'#c0ccdd'}}>PLAYSTATION</div>
    <div style={{position:'absolute',top:914,width:'100%',textAlign:'center',fontSize:22,color:'#91a4bd',opacity:ease(f,24,50)}}>USB or Bluetooth. Your shortcuts. Your profile.</div>
    <FooterBrand chapter="07 / PLUG INTO YOUR FLOW"/>
  </Scene>;
};

const Outro = () => {
  const f=useCurrentFrame();
  return <Scene duration={186}><Backdrop/>
    <div style={{position:'absolute',left:100,top:190,width:750}}>
      <div style={{display:'flex',alignItems:'center',gap:20,marginBottom:45,opacity:ease(f,0,23)}}><Img src={staticFile('app-icon.png')} style={{width:74,height:74,borderRadius:18}}/><span style={{fontSize:28,fontWeight:600,letterSpacing:-1}}>Vibe Controller</span></div>
      <Headline lines={['Less reaching.','More doing.']} size={99} delay={8}/>
      <p style={{fontSize:24,color:'#a2b2c9',marginTop:29,lineHeight:1.55,opacity:ease(f,37,61)}}>Put your Mac workspace<br/>in the palm of your hands.</p>
      <div style={{fontSize:21,color:'#d4e5ff',marginTop:52,display:'flex',alignItems:'center',gap:18,opacity:ease(f,66,92)}}><span style={{width:44,height:44,borderRadius:50,border:'1px solid #89bbff70',display:'grid',placeItems:'center',color:BLUE}}>↗</span>github.com/ggaabe/vibe-controller</div>
      <div style={{fontSize:14,color:'#778ba6',marginTop:22,opacity:ease(f,82,107)}}>Available for macOS · Signed + notarized download</div>
    </div>
    <div style={{position:'absolute',left:1130,top:240,perspective:1700,opacity:ease(f,0,35)}}><div style={{transform:`rotateY(-25deg) rotateX(8deg) rotateZ(7deg) scale(.69) translateY(${ease(f,0,150,25,0)}px)`,transformOrigin:'top left'}}><AppWindow live/></div></div>
    <FooterBrand chapter="YOUR CONTROLLER. YOUR WORKSPACE."/>
  </Scene>;
};

export const ProductFilm = () => <AbsoluteFill style={{background:'#080b12'}}>
  <Audio src={staticFile('score-workflow.wav')}/>
  <Sequence from={0} durationInFrames={156} premountFor={30}><Intro/></Sequence>
  <Sequence from={144} durationInFrames={216} premountFor={30}><Interface/></Sequence>
  <Sequence from={348} durationInFrames={156} premountFor={30}><Modifiers/></Sequence>
  <Sequence from={492} durationInFrames={300} premountFor={30}><Handoff/></Sequence>
  <Sequence from={WORKFLOW_START} durationInFrames={SCREENSHOT_DURATION} premountFor={30}><Workflow/></Sequence>
  <Sequence from={OCR_START} durationInFrames={OCR_DURATION} premountFor={30}><Workflow ocrMode/></Sequence>
  <Sequence from={CHOICE_START} durationInFrames={156} premountFor={30}><Choice/></Sequence>
  <Sequence from={OUTRO_START} durationInFrames={186} premountFor={30}><Outro/></Sequence>
</AbsoluteFill>;
