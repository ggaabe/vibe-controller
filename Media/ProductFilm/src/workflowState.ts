export const SCREENSHOT_DURATION = 720;
export const OCR_DURATION = 360;
export const WORKFLOW_START = 780;
export const OCR_START = WORKFLOW_START + SCREENSHOT_DURATION - 12;
export const CHOICE_START = OCR_START + OCR_DURATION - 12;
export const OUTRO_START = CHOICE_START + 144;
export const FILM_DURATION = OUTRO_START + 186;

const clamp=(v:number)=>Math.min(1,Math.max(0,v));
export const progress=(f:number,a:number,b:number)=>clamp((f-a)/(b-a));
const within=(f:number,a:number,b:number)=>f>=a&&f<b;

export type WorkflowCue = {key:string;title:string;detail:string;buttons:string[];stick:[number,number];step:number};

export function workflowCue(f:number,ocr=false):WorkflowCue {
  let key='A',title='Click into the conversation.',detail='A is your regular left click.',buttons:string[]=[],stick:[number,number]=[0,0],step=0;
  if(ocr){
    key='X';title='Capture text, not pixels.';detail='X opens your TextSniper OCR shortcut.';
    if(within(f,30,45))buttons=['X'];
    if(f>=70&&f<166){key='LT + STICK';title='Select the words you need.';detail='Hold LT and move the left stick to select.';step=1;if(f<150){buttons=['LT'];stick=[.7,-.38];}}
    if(f>=166&&f<218){key='OCR';title='An image becomes text.';detail='TextSniper recognizes it and copies the result.';step=2;}
    if(f>=218&&f<259){key='A';title='Choose where it goes.';detail='Click into the AI composer.';step=3;if(within(f,229,241))buttons=['A'];}
    if(f>=259){key='Y';title='Paste the exact words.';detail='The recognized text is ready for your AI.';step=4;if(within(f,276,291))buttons=['Y'];}
  } else {
    if(within(f,36,49))buttons=['A'];
    if(f>=65&&f<100){key='B';title='Start an area screenshot.';detail='B activates the screenshot selection shortcut.';step=1;if(within(f,78,93))buttons=['B'];}
    if(f>=100&&f<190){key='LT + STICK';title='Frame what matters.';detail='Hold LT to drag. Move the left stick to select.';step=2;if(f<176){buttons=['LT'];stick=[.8,-.45];}}
    if(f>=190&&f<240){key='Y';title='Paste the screenshot.';detail='The capture goes straight into the AI composer.';step=3;if(within(f,207,221))buttons=['Y'];}
    if(f>=240&&f<400){key='RT';title='Tell your AI what you want.';detail='Tap RT to send your configured dictation shortcut.';step=4;if(within(f,251,267))buttons=['RT'];}
    if(f>=400&&f<452){key='R3';title='A quick correction.';detail='Tap the right stick to Backspace.';step=5;if(f>=405&&f<447&&(f-405)%7<4)buttons=['R3'];}
    if(f>=452&&f<506){key='RT';title='Say the new word.';detail='Dictate “blue” to finish the instruction.';step=6;if(within(f,460,476))buttons=['RT'];}
    if(f>=506&&f<561){key='L3';title='Press Enter. Send it.';detail='Click the left stick to send your message.';step=7;if(within(f,524,540))buttons=['L3'];}
    if(f>=561&&f<607){key='AI';title='Now your AI has the context.';detail='An image and a clear instruction. In one message.';step=8;}
    if(f>=607&&f<660){key='LT + STICK';title='Select the reply.';detail='Hold LT and sweep across the text.';step=9;if(f<651){buttons=['LT'];stick=[.8,0];}}
    if(f>=660){key='VIEW';title='Copy, without reaching.';detail='The overlapping-rectangles button sends Copy.';step=10;if(within(f,675,690))buttons=['View'];}
  }
  return {key,title,detail,buttons,stick,step};
}

export function dictatedText(f:number):string {
  const original='Use this screenshot. Make the card green.';
  if(f<270)return '';
  if(f<400)return original.slice(0,Math.floor(progress(f,270,381)*original.length));
  if(f<452){const deletions=Math.max(0,Math.min(6,Math.floor((f-405)/7)+1));return original.slice(0,original.length-deletions);}
  return 'Use this screenshot. Make the card '+('blue.').slice(0,Math.floor(progress(f,469,494)*5));
}
