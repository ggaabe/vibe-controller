import React from 'react';
import {Composition, registerRoot} from 'remotion';
import {ProductFilm} from './ProductFilm';
import {Workflow} from './Workflow';
import {FILM_DURATION,SCREENSHOT_DURATION,OCR_DURATION} from './workflowState';

const Root = () => <>
  <Composition id="VibeController" component={ProductFilm} durationInFrames={FILM_DURATION} fps={30} width={1920} height={1080}/>
  <Composition id="ScreenshotWorkflow" component={Workflow} durationInFrames={SCREENSHOT_DURATION} fps={30} width={1920} height={1080}/>
  <Composition id="OCRWorkflow" component={Workflow} defaultProps={{ocrMode:true}} durationInFrames={OCR_DURATION} fps={30} width={1920} height={1080}/>
</>;
registerRoot(Root);
