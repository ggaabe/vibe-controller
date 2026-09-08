import React, {useLayoutEffect,useMemo} from 'react';
import * as THREE from 'three';
import {useCurrentFrame} from 'remotion';
import {dictatedText,progress} from './workflowState';

type Ctx=CanvasRenderingContext2D;
const blue='#75b9ff';
const rect=(c:Ctx,x:number,y:number,w:number,h:number,r:number,fill:string,stroke?:string)=>{c.beginPath();c.roundRect(x,y,w,h,r);c.fillStyle=fill;c.fill();if(stroke){c.strokeStyle=stroke;c.lineWidth=2;c.stroke();}};
function text(c:Ctx,s:string,x:number,y:number,size=24,color='#e9eef7',weight=500){c.font=`${weight} ${size}px Manrope, sans-serif`;c.fillStyle=color;c.fillText(s,x,y);}
function wrap(c:Ctx,s:string,x:number,y:number,width:number,size=28,color='#e7eef8',line=40){c.font=`500 ${size}px Manrope, sans-serif`;let row='';let py=y;for(const word of s.split(' ')){const test=row?`${row} ${word}`:word;if(c.measureText(test).width>width&&row){text(c,row,x,py,size,color);row=word;py+=line;}else row=test;}text(c,row,x,py,size,color);return py;}
function cursor(c:Ctx,x:number,y:number,cross=false){c.save();c.translate(x,y);c.shadowColor='#0009';c.shadowBlur=4;c.lineWidth=2;c.strokeStyle='#0b1323';c.fillStyle='#fff';if(cross){c.shadowBlur=0;c.strokeStyle='#fff';c.lineWidth=3;c.beginPath();c.moveTo(-16,0);c.lineTo(16,0);c.moveTo(0,-16);c.lineTo(0,16);c.stroke();}else{c.beginPath();c.moveTo(0,0);c.lineTo(0,35);c.lineTo(9,26);c.lineTo(17,42);c.lineTo(24,39);c.lineTo(16,23);c.lineTo(30,23);c.closePath();c.fill();c.stroke();}c.restore();}
function design(c:Ctx,x:number,y:number,w:number,h:number,thumbnail=false){
  c.save();c.translate(x,y);c.scale(w/500,h/390);
  rect(c,0,0,500,390,15,'#ecede5');
  text(c,'A LITTLE MORE ROOM',25,39,14,'#627461',700);
  text(c,'Make space to create.',25,83,32,'#203e35',700);
  text(c,'Ideas move better when you do.',25,119,18,'#687c70');
  rect(c,25,151,450,177,9,'#bbceb4');
  c.fillStyle='#e7e9d0';c.beginPath();c.arc(247,240,70,0,Math.PI*2);c.fill();
  c.fillStyle='#54765c';c.beginPath();c.moveTo(199,295);c.lineTo(247,177);c.lineTo(295,295);c.closePath();c.fill();
  text(c,'Explore your next idea  ↗',25,365,20,'#365d49',600);
  c.restore();
}

function backdrop(c:Ctx){
  c.fillStyle='#111722';c.fillRect(0,0,1280,800);
  rect(c,0,0,1280,43,0,'#232d3d');
  ['#e97976','#e3bd66','#6cc794'].forEach((v,i)=>{c.fillStyle=v;c.beginPath();c.arc(23+i*23,22,6,0,Math.PI*2);c.fill();});
  text(c,'VIBE WORKSPACE  /  ILLUSTRATED DEMO',140,29,16,'#aabbd0',600);
  rect(c,20,65,570,707,16,'#202b39');
  text(c,'REFERENCE',45,101,17,'#a7b5ca',700);
  design(c,49,143,512,402);
  text(c,'A visual idea, ready to share.',49,594,23,'#c2cedc');
  text(c,'No keyboard or mouse used in this example.',49,641,18,'#869ab5');
  rect(c,612,65,649,707,16,'#171e2a');
  text(c,'AI CHAT',644,108,20,'#d0dded',700);
  c.fillStyle='#3be095';c.beginPath();c.arc(1208,100,5,0,Math.PI*2);c.fill();
}

function selection(c:Ctx,x:number,y:number,w:number,h:number,p:number){
  // The selection stays clear while the rest of the desktop is dimmed.
  c.fillStyle='#03081270';c.fillRect(0,43,1280,757);
  c.save();c.beginPath();c.rect(x,y,Math.max(1,w*p),Math.max(1,h*p));c.clip();
  design(c,49,143,512,402);c.restore();
  c.strokeStyle=blue;c.lineWidth=3;c.setLineDash([10,6]);c.strokeRect(x,y,w*p,h*p);c.setLineDash([]);
  for(const [px,py]of[[x,y],[x+w*p,y],[x,y+h*p],[x+w*p,y+h*p]])rect(c,px-4,py-4,8,8,2,'#e8f5ff');
  cursor(c,x+w*p,y+h*p,true);
}

function toast(c:Ctx,label:string,sub:string){rect(c,736,141,478,93,12,'#173b45','#4eabb5');text(c,'✓ '+label,758,179,26,'#bcf2e4',700);text(c,sub,758,211,18,'#92cabe');}

function waveform(c:Ctx,f:number){
  rect(c,700,148,500,110,18,'#213d65','#6da7f5');
  for(let i=0;i<28;i++){const h=10+(Math.sin(f*.28+i*.63)**2)*30+(Math.cos(f*.12+i*.81)**2)*9;rect(c,725+i*8,191-h/2,4,h,2,'#b0dcff');}
  text(c,'Listening…',981,198,23,'#d9edff',600);
  text(c,'Your microphone · your dictation app',724,237,17,'#91b6e6');
}

function screenshot(c:Ctx,f:number){
  backdrop(c);
  const sent=f>=530, attached=f>=211;
  const msg=dictatedText(f);
  if(!sent){
    text(c,'Give your AI some context.',652,312,31,'#e2ebf8',600);
    text(c,'Attach an image. Say what to change.',652,354,22,'#849bb8');
    rect(c,640,393,593,328,17,'#222d3d',f>=40?blue:'#3d4b5e');
    if(attached){design(c,662,411,160,126,true);text(c,'Screenshot',839,456,21,'#c9d8ed');text(c,'Attached to your message',839,489,17,'#91a4bf');}
    if(msg)wrap(c,msg,666,attached?587:467,530,29,'#eff5ff',41);else text(c,'Message your AI…',666,attached?591:467,26,'#7f94b0');
    text(c,'+',664,694,35,'#a8bedb');rect(c,1164,662,42,40,20,msg?'#72b4ff':'#40536e');text(c,'↑',1176,691,28,'#0e1a2b',700);
  }else{
    rect(c,706,143,515,319,17,'#243853','#416594');
    design(c,727,163,145,113,true);text(c,'Screenshot',890,214,20,'#b9d4f7');
    wrap(c,'Use this screenshot. Make the card blue.',730,329,458,29,'#f1f6ff',40);
    text(c,'SENT WITH ENTER',1003,438,14,'#93b6e1',700);
    if(f>=563){
      text(c,'AI',651,519,19,blue,700);
      const reply='I’ll rebuild the card in blue using your screenshot.';
      const display=reply.slice(0,Math.floor(progress(f,563,599)*reply.length));
      if(f>=610){const p=progress(f,611,650);rect(c,646,543,550*p,95,3,'#4d8dc777');}
      wrap(c,display,653,573,548,27,'#d5e4f7',40);
      if(f>=611&&f<652)cursor(c,653+545*progress(f,611,650),570+40*progress(f,611,650));
    }
    rect(c,640,683,590,58,13,'#222d3d','#394e69');text(c,'Message your AI…',661,721,22,'#7f94b0');
  }
  if(f>=40&&f<68)cursor(c,978,514);
  if(f>=88&&f<181){const p=progress(f,102,175);selection(c,49,143,512,402,p);text(c,'DRAG TO CAPTURE',59,128,17,'#cbe4ff',700);}
  if(f>=181&&f<210)toast(c,'Screenshot copied','Clipboard → ready to paste with Y');
  if((f>=266&&f<390)||(f>=475&&f<500))waveform(c,f);
  if(f>=675)toast(c,'Reply copied','View button → Copy');
}

function ocr(c:Ctx,f:number){
  backdrop(c);
  text(c,'Bring the words along, too.',650,301,31,'#e2ebf8',600);
  text(c,'Turn text in an image into editable context.',650,343,22,'#849bb8');
  rect(c,640,413,593,294,17,'#222d3d',f>=236?blue:'#3d4b5e');
  if(f<281)text(c,'Message your AI…',666,468,26,'#7f94b0');
  else{wrap(c,'Make space to create.',665,474,535,33,'#f1f6ff',45);text(c,'EDITABLE TEXT — PASTED FROM CLIPBOARD',666,532,15,'#77b8dc',700);}
  text(c,'+',665,677,34,'#a8bedb');rect(c,1164,649,42,40,20,'#72b4ff');text(c,'↑',1176,678,28,'#0e1a2b',700);
  if(f>=44&&f<163){const p=progress(f,80,150);selection(c,71,191,458,54,p);text(c,'TEXTSNIPER · SELECT TEXT',73,177,17,'#d3eaff',700);}
  if(f>=164&&f<281){toast(c,'Text recognized & copied','TextSniper OCR → clipboard');rect(c,735,266,479,78,12,'#1d344e','#729bd3');text(c,'Make space to create.',758,315,28,'#def0ff',600);}
  if(f>=236&&f<269)cursor(c,1002,484);
}

export const WorkflowScreen = ({ocrMode=false}:{ocrMode?:boolean}) => {
  const f=useCurrentFrame();
  const resource=useMemo(()=>{
    if(typeof document==='undefined')return null;
    const canvas=document.createElement('canvas');canvas.width=1280;canvas.height=800;
    const texture=new THREE.CanvasTexture(canvas);texture.colorSpace=THREE.SRGBColorSpace;texture.minFilter=THREE.LinearFilter;texture.magFilter=THREE.LinearFilter;
    return {canvas,texture};
  },[]);
  useLayoutEffect(()=>{
    if(!resource)return;const c=resource.canvas.getContext('2d');if(!c)return;
    if(ocrMode)ocr(c,f);else screenshot(c,f);
    resource.texture.needsUpdate=true;
  },[f,ocrMode,resource]);
  useLayoutEffect(()=>()=>resource?.texture.dispose(),[resource]);
  return <meshBasicMaterial map={resource?.texture??null} toneMapped={false}/>;
};
