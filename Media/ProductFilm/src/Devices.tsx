import React, {useLayoutEffect, useMemo} from 'react';
import {useLoader, useThree} from '@react-three/fiber';
import {ThreeCanvas} from '@remotion/three';
import {staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import * as THREE from 'three';
import {BLUE,ease,lin} from './design';

const Texture = ({file}:{file:string}) => {
  const t=useLoader(THREE.TextureLoader,staticFile(file));
  t.colorSpace=THREE.SRGBColorSpace;
  return <meshBasicMaterial map={t} transparent toneMapped={false} side={THREE.DoubleSide}/>;
};

const rounded = (w:number,h:number,r:number) => {
  const s=new THREE.Shape(),x=-w/2,y=-h/2;
  s.moveTo(x+r,y);s.lineTo(x+w-r,y);s.quadraticCurveTo(x+w,y,x+w,y+r);
  s.lineTo(x+w,y+h-r);s.quadraticCurveTo(x+w,y+h,x+w-r,y+h);
  s.lineTo(x+r,y+h);s.quadraticCurveTo(x,y+h,x,y+h-r);
  s.lineTo(x,y+r);s.quadraticCurveTo(x,y,x+r,y);
  return s;
};

const Slab = ({width,height,depth,color,radius=.09}:{width:number,height:number,depth:number,color:string,radius?:number}) => {
  const shape=useMemo(()=>rounded(width,height,radius),[width,height,radius]);
  return <><extrudeGeometry args={[shape,{depth,steps:1,bevelEnabled:true,bevelSegments:2,bevelSize:.012,bevelThickness:.012}]}/><meshStandardMaterial color={color} metalness={.75} roughness={.32}/></>;
};

const ControllerShape = () => {
  const s=new THREE.Shape();
  s.moveTo(-2.55,1.52); s.bezierCurveTo(-3.15,1.52,-3.62,1.1,-3.8,.4);
  s.bezierCurveTo(-4.0,-.3,-4.3,-1.3,-4.21,-1.7);
  s.bezierCurveTo(-4.18,-2.45,-3.9,-2.77,-3.53,-2.51);
  s.bezierCurveTo(-3.1,-2.27,-2.65,-1.58,-2.12,-1.18);
  s.bezierCurveTo(-1.67,-.84,-1.08,-1.5,0,-1.5);
  s.bezierCurveTo(1.08,-1.5,1.67,-.84,2.12,-1.18);
  s.bezierCurveTo(2.65,-1.58,3.1,-2.27,3.53,-2.51);
  s.bezierCurveTo(3.9,-2.77,4.18,-2.45,4.21,-1.7);
  s.bezierCurveTo(4.3,-1.3,4,-.3,3.8,.4);
  s.bezierCurveTo(3.62,1.1,3.15,1.52,2.55,1.52);
  s.bezierCurveTo(1.2,1.72,-1.2,1.72,-2.55,1.52);
  return s;
};

export type GamepadInput = {buttons?: string[]; leftStick?: [number,number]; intensity?: number};

export const Gamepad = ({family='xbox',scale=1,rotation=[0,0,0],position=[0,0,0],explode=0,input={}}:{family?:'xbox'|'playstation',scale?:number,rotation?:[number,number,number],position?:[number,number,number],explode?:number,input?:GamepadInput}) => {
  const shape=useMemo(ControllerShape,[]);
  const controls:Record<string,[number,number,number]>={A:[2.43,-.13,.27],B:[3.01,.45,.27],X:[1.85,.45,.27],Y:[2.43,1.03,.27],View:[-.54,.34,.24],LT:[-2.12,2.10,.48],RT:[2.12,2.10,.48],L3:[-2.17,.38,.51],R3:[1,-.9,.51]};
  return <group scale={scale} rotation={rotation} position={position}>
    <mesh position={[0,0,-.36]}><extrudeGeometry args={[shape,{depth:.42,bevelEnabled:true,bevelSegments:3,steps:1,bevelSize:.07,bevelThickness:.07}]}/><meshStandardMaterial color={family==='xbox'?'#252b36':'#cbd3e0'} roughness={.38} metalness={.42}/></mesh>
    <mesh position={[0,0,.20]}><planeGeometry args={[10,6.6]}/><Texture file={`${family}.svg`}/></mesh>
    {family==='xbox' && <group>
      {[[-2.17,.38],[1,-.9]].map(([x,y],i)=><group key={i} position={[x+(i===0?(input.leftStick?.[0]??0)*.25:0),y+(i===0?(input.leftStick?.[1]??0)*.25:0),.26+explode*(i===0?1.4:.65)-(input.buttons?.includes(i===0?'L3':'R3') ? .08 : 0)]}>
        <mesh rotation={[Math.PI/2,0,0]}><cylinderGeometry args={[.47,.51,.2,48]}/><meshStandardMaterial color="#252c38" roughness={.42} metalness={.35}/></mesh>
        <mesh position={[0,0,.13]}><ringGeometry args={[.42,.44,64]}/><meshBasicMaterial color={BLUE} transparent opacity={.2+explode*.8}/></mesh>
      </group>)}
    </group>}
    {family==='xbox' && input.buttons?.map(id=>{
      const c=controls[id];if(!c)return null;const [x,y,r]=c;
      return <group key={id} position={[x,y,(id==='L3'||id==='R3') ? .48 : .29]} scale={id==='LT'||id==='RT'?[1.03,.62,1]:[1,1,1]}>
        <mesh><circleGeometry args={[r,48]}/><meshBasicMaterial color={BLUE} transparent opacity={.35*(input.intensity??1)} depthWrite={false}/></mesh>
        <mesh position={[0,0,.003]}><ringGeometry args={[r,r+.045,48]}/><meshBasicMaterial color="#bde2ff" transparent opacity={input.intensity??1} depthWrite={false}/></mesh>
        <mesh position={[0,0,-.002]}><ringGeometry args={[r+.065,r+.12,48]}/><meshBasicMaterial color={BLUE} transparent opacity={.25*(input.intensity??1)} depthWrite={false}/></mesh>
      </group>;
    })}
  </group>;
};

export const HeroController = ({pair=false}:{pair?:boolean}) => {
  const f=useCurrentFrame(); const {width,height}=useVideoConfig();
  return <ThreeCanvas width={width} height={height} camera={{position:[0,0,13],fov:39}} gl={{alpha:true,antialias:true}}>
    <ambientLight intensity={1.6}/><directionalLight position={[-5,7,9]} intensity={3}/><pointLight position={[5,0,4]} color="#4897ff" intensity={40}/>
    <group>
      {pair ? <>
        <Gamepad position={[-3.6,-.1,0]} scale={.77} rotation={[.18+Math.sin(f/90)*.05,.2, -.08]}/>
        <Gamepad family="playstation" position={[3.5,.15,-.4]} scale={.77} rotation={[.15,-.23,.07]}/>
      </> : <Gamepad position={[2.85,-.05,0]} scale={1} rotation={[ease(f,0,80,.5,.2),ease(f,0,140,-.6,-.22),ease(f,0,120,-.12,.05)]} explode={ease(f,45,100)*.25}/>}
    </group>
  </ThreeCanvas>;
};

const Mouse = ({x,y}:{x:number,y:number}) => {
  const shape=useMemo(()=>{const s=new THREE.Shape();s.moveTo(0,.18);s.lineTo(0,-.22);s.lineTo(.09,-.12);s.lineTo(.18,-.29);s.lineTo(.24,-.26);s.lineTo(.15,-.09);s.lineTo(.30,-.09);s.closePath();return s;},[]);
  return <group position={[x,y,.142]}>
    <mesh position={[.07,-.05,-.006]}><circleGeometry args={[.25,40]}/><meshBasicMaterial color="#58a6ff" transparent opacity={.21}/></mesh>
    <mesh><shapeGeometry args={[shape]}/><meshBasicMaterial color="#ffffff"/></mesh>
  </group>;
};

export const Laptop = ({index,position,rotation,progress,screen}:{index:number,position:[number,number,number],rotation:number,progress:number,screen?:React.ReactNode}) => {
  const active=Math.floor(progress)===index;
  const part=progress-index;
  const keys=useMemo(()=>Array.from({length:65},(_,i)=>({x:(i%13-6)*.248,z:Math.floor(i/13)*.225})),[]);
  return <group position={position} rotation={[0,rotation,0]}>
    <mesh position={[0,-.15,1.05]} rotation={[-Math.PI/2,0,0]}><Slab width={3.85} height={2.55} depth={.13} color="#939eaf"/></mesh>
    <mesh position={[0,.002,.68]}><boxGeometry args={[3.43,.013,1.26]}/><meshStandardMaterial color="#141923" roughness={.5}/></mesh>
    {keys.map((k,i)=><mesh key={i} position={[k.x,.022,k.z+.20]}><boxGeometry args={[.212,.018,.176]}/><meshStandardMaterial color="#263040" metalness={.4} roughness={.47}/></mesh>)}
    <mesh position={[0,.002,1.78]}><boxGeometry args={[1.4,.017,.7]}/><meshStandardMaterial color="#758292" metalness={.7} roughness={.35}/></mesh>
    <group rotation={[-.13,0,0]}>
      <mesh position={[0,1.2,-.06]}><Slab width={3.83} height={2.42} depth={.12} color="#6b7586"/></mesh>
      <mesh position={[0,1.2,.09]}><planeGeometry args={[3.69,2.27]}/><meshBasicMaterial color="#05070c"/></mesh>
      <mesh position={[0,1.2,.103]}><planeGeometry args={[3.52,2.12]}/>{screen??<Texture file={['app-xbox.jpg','desktop-create.svg','desktop-focus.svg'][index]}/>}</mesh>
      <mesh position={[0,2.338,.08]}><circleGeometry args={[.019,12]}/><meshBasicMaterial color="#162333"/></mesh>
      {active && <Mouse x={lin(part,0,1,-1.53,1.50)} y={1.15+Math.sin(part*Math.PI*2+index)*.20}/>}
      {active && <mesh position={[0,.03,.09]}><planeGeometry args={[3.25,.014]}/><meshBasicMaterial color={BLUE}/></mesh>}
    </group>
  </group>;
};

const Orbit = () => {
  const f=useCurrentFrame();const {camera}=useThree();
  useLayoutEffect(()=>{camera.position.set(ease(f,0,260,6.1,-2.7),ease(f,0,200,6.5,5.4),ease(f,0,200,15,16.2));camera.lookAt(0,.85,.3);camera.updateProjectionMatrix();},[camera,f]);return null;
};

export const MacWorld = () => {
  const f=useCurrentFrame();const {width,height}=useVideoConfig();
  const p=lin(f,42,245,.08,2.94);
  const curve=useMemo(()=>new THREE.CatmullRomCurve3([new THREE.Vector3(-6,.02,1.45),new THREE.Vector3(-3,.02,3.0),new THREE.Vector3(0,.02,3.35),new THREE.Vector3(3,.02,3.0),new THREE.Vector3(6,.02,1.45)]),[]);
  return <ThreeCanvas width={width} height={height} camera={{position:[6,6.5,15],fov:40}} gl={{alpha:true,antialias:true}}>
    <Orbit/><ambientLight intensity={1.8}/><directionalLight position={[1,8,6]} intensity={3.5}/><pointLight position={[-5,3,5]} color="#308bff" intensity={85}/><pointLight position={[8,3,1]} color="#8791ff" intensity={65}/>
    <group>
      <group position={[0,-.36,0]}>
        <Laptop index={0} position={[-4.55,0,0]} rotation={.17} progress={p}/>
        <Laptop index={1} position={[0,0,-.42]} rotation={0} progress={p}/>
        <Laptop index={2} position={[4.55,0,0]} rotation={-.17} progress={p}/>
        <mesh><tubeGeometry args={[curve,90,.015,8,false]}/><meshBasicMaterial color="#5c9ef5" transparent opacity={.65}/></mesh>
        <Gamepad position={[-.8,.11,4.1]} rotation={[-1.24,0,.12]} scale={.27}/>
      </group>
    </group>
  </ThreeCanvas>;
};
