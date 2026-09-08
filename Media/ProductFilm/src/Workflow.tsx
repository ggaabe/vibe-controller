import React,{useMemo} from 'react';
import * as THREE from 'three';
import {ThreeCanvas} from '@remotion/three';
import {useCurrentFrame,useVideoConfig} from 'remotion';
import {Gamepad,Laptop} from './Devices';
import {Backdrop,BLUE,ease,FooterBrand,Headline,Kicker,Scene} from './design';
import {WorkflowScreen} from './WorkflowScreen';
import {OCR_DURATION,SCREENSHOT_DURATION,workflowCue} from './workflowState';

const ViewIcon=()=> <svg width="45" height="38" viewBox="0 0 45 38"><rect x="4" y="14" width="26" height="19" rx="2" fill="none" stroke="currentColor" strokeWidth="2.4"/><path d="M15 14V5H40V25H30" fill="none" stroke="currentColor" strokeWidth="2.4"/></svg>;

const WorkflowDevices=({ocrMode}:{ocrMode:boolean})=>{
  const f=useCurrentFrame();const{width,height}=useVideoConfig();const cue=workflowCue(f,ocrMode);
  const link=useMemo(()=>new THREE.CatmullRomCurve3([new THREE.Vector3(-1.3,-1.22,2),new THREE.Vector3(-.4,-.72,1.5),new THREE.Vector3(.55,-.5,.16)]),[]);
  const point=link.getPoint((f%18)/18);
  return <ThreeCanvas width={width} height={height} camera={{position:[0,0,12],fov:37}} gl={{alpha:true,antialias:true}}>
    <ambientLight intensity={1.7}/><directionalLight position={[-2,6,8]} intensity={3}/><pointLight position={[6,0,4]} color="#589dff" intensity={35}/>
    <group position={[2.45,-1.72,0]} scale={1.56} rotation={[0,ease(f,0,ocrMode?360:720,-.23,.10),0]}>
      <Laptop index={0} position={[0,0,0]} rotation={0} progress={-1} screen={<WorkflowScreen ocrMode={ocrMode}/>}/>
    </group>
    <Gamepad position={[-3.56,-1.12,1.8]} scale={.49} rotation={[.15,-.13,-.06]} input={{buttons:cue.buttons,leftStick:cue.stick,intensity:.95}}/>
    {cue.buttons.length>0 && <group><mesh><tubeGeometry args={[link,40,.008,6,false]}/><meshBasicMaterial color={BLUE} transparent opacity={.42}/></mesh><mesh position={point}><sphereGeometry args={[.035,12,12]}/><meshBasicMaterial color="#b8e0ff"/></mesh></group>}
  </ThreeCanvas>;
};

export const Workflow=({ocrMode=false}:{ocrMode?:boolean})=>{
  const f=useCurrentFrame();const cue=workflowCue(f,ocrMode);
  const label=cue.key==='VIEW'?<ViewIcon/>:cue.key==='LT + STICK'?<span style={{fontSize:19}}>LT + ◎</span>:cue.key;
  return <Scene duration={ocrMode?OCR_DURATION:SCREENSHOT_DURATION}><Backdrop warm={ocrMode}/>
    <div style={{position:'absolute',left:92,top:94,width:690}}><Kicker>{ocrMode?'TEXTSNIPER · OCR COMPANION':'YOUR CONTROLLER → YOUR AI'}</Kicker><Headline lines={ocrMode?['Text in an image?','Make it usable.']:['Show it.','Say it. Send it.']} size={65}/></div>
    <div style={{position:'absolute',inset:0,opacity:ease(f,0,22)}}><WorkflowDevices ocrMode={ocrMode}/></div>
    <div style={{position:'absolute',left:93,top:343,width:660}}>
      <div style={{display:'flex',alignItems:'center',gap:20}}><div style={{minWidth:69,height:63,padding:'0 10px',display:'flex',alignItems:'center',justifyContent:'center',border:'1px solid #89bfff90',borderRadius:16,background:'#1b3453',color:BLUE,fontSize:27,fontWeight:700}}>{label}</div><div style={{fontSize:32,fontWeight:600,letterSpacing:-1.1,maxWidth:535,lineHeight:1.2}}>{cue.title}</div></div>
      <div style={{fontSize:20,color:'#a7b9cf',marginTop:16,lineHeight:1.45,maxWidth:610}}>{cue.detail}</div>
      <div style={{marginTop:16,display:'flex',gap:7}}>{Array.from({length:ocrMode?5:11},(_,i)=><div key={i} style={{width:ocrMode?46:23,height:3,borderRadius:3,background:i<=cue.step?BLUE:'#24344c'}}/>)}</div>
    </div>
    <div style={{position:'absolute',left:840,top:167,color:'#7993b6',fontSize:16,letterSpacing:1.3}}>ILLUSTRATED AI WORKFLOW</div>
    <div style={{position:'absolute',left:92,bottom:124,fontSize:18,color:'#b6c8df'}}>Gabe’s mappings <span style={{color:'#728ba9'}}>· Every shortcut is customizable</span></div>
    <div style={{position:'absolute',left:92,right:92,bottom:83,fontSize:15,color:'#8499b4'}}>{ocrMode?'TextSniper or equivalent required · Separate OCR companion app · Recognized text is copied to your clipboard.':'RT sends your configured dictation shortcut. Use a matching shortcut on each Mac and your own microphone.'}</div>
    <FooterBrand chapter={ocrMode?'06 / CAPTURE THE WORDS':'05 / CONTEXT WITHOUT THE KEYBOARD'}/>
  </Scene>;
};
