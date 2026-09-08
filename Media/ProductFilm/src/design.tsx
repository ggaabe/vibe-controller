import React from 'react';
import {AbsoluteFill, Easing, interpolate, useCurrentFrame, useVideoConfig} from 'remotion';
import {loadFont} from '@remotion/google-fonts/Manrope';

export const {fontFamily} = loadFont('normal', {weights:['400','500','600','700','800'], subsets:['latin']});
export const BLUE = '#6eacff';
export const INK = '#080b12';
export const ease = (f:number, a:number, b:number, x=0, y=1) => interpolate(f,[a,b],[x,y], {extrapolateLeft:'clamp',extrapolateRight:'clamp',easing:Easing.bezier(.22,.8,.22,1)});
export const lin = (f:number,a:number,b:number,x=0,y=1) => interpolate(f,[a,b],[x,y],{extrapolateLeft:'clamp',extrapolateRight:'clamp'});

export const Backdrop = ({warm=false}:{warm?:boolean}) => {
  const f=useCurrentFrame();
  return <AbsoluteFill style={{background:INK,overflow:'hidden'}}>
    <div style={{position:'absolute',width:1500,height:1200,left:480+Math.sin(f/180)*100,top:-110,background:`radial-gradient(ellipse, ${warm?'#343350':'#173255'} 0%, #0c1524 40%, transparent 69%)`,opacity:.66}}/>
    <div style={{position:'absolute',inset:0,background:'radial-gradient(ellipse at 50% 120%, #283a512f, transparent 58%)'}}/>
    <svg width="1920" height="1080" style={{position:'absolute',opacity:.10}}>
      <defs><pattern id="micro" width="44" height="44" patternUnits="userSpaceOnUse"><circle cx="1" cy="1" r=".7" fill="#b1c6e0"/></pattern></defs>
      <rect width="1920" height="1080" fill="url(#micro)"/>
    </svg>
  </AbsoluteFill>;
};

export const Kicker = ({children}:{children:React.ReactNode}) => <div style={{fontSize:17,fontWeight:700,letterSpacing:4.5,color:BLUE,textTransform:'uppercase',marginBottom:25}}>{children}</div>;

export const Headline = ({lines, delay=0, size=82, centered=false}:{lines:string[],delay?:number,size?:number,centered?:boolean}) => {
  const f=useCurrentFrame(); const {fps}=useVideoConfig();
  return <div style={{fontSize:size,fontWeight:600,letterSpacing:-size*.052,lineHeight:1.08,textAlign:centered?'center':'left'}}>
    {lines.map((line,i)=><div key={line} style={{overflow:'hidden',paddingBottom:6}}><div style={{transform:`translateY(${ease(f,delay+i*fps*.1,delay+fps*.75+i*fps*.1,110,0)}%)`,opacity:ease(f,delay+i*3,delay+21+i*3)}}>{line}</div></div>)}
  </div>;
};

export const FooterBrand = ({chapter}:{chapter:string}) => <div style={{position:'absolute',left:78,right:78,bottom:43,display:'flex',justifyContent:'space-between',fontSize:14,letterSpacing:1.2,color:'#8c9aae'}}><span>VIBE CONTROLLER</span><span>{chapter}</span></div>;

export const Pointer = ({size=45}:{size?:number}) => <svg width={size} height={size*1.25} viewBox="0 0 40 50" style={{filter:'drop-shadow(0 3px 4px #0007)'}}><path d="M5 3 L5 38 L14 29 L22 46 L29 43 L21 26 L35 26Z" fill="white" stroke="#0b1528" strokeWidth="2.5" strokeLinejoin="round"/></svg>;

export const Scene = ({children,duration}:{children:React.ReactNode,duration:number}) => {
  const f=useCurrentFrame();
  return <AbsoluteFill style={{opacity:lin(f,0,10)*lin(f,duration-10,duration,1,0),fontFamily,color:'#f4f7fb'}}>{children}</AbsoluteFill>;
};
