# Vibe Controller — product film

An editable 72.2-second, 1920 × 1080, 30 fps product film with original electronic music. Created in Remotion, React, and Three.js. All animation is deterministic and driven by the video frame. The expanded cut adds a controller-driven AI workflow to the original product film.

## Watch and edit

- Expanded video: `out/vibe-controller-workflow-film.mp4`
- Original 40-second cut (preserved): `out/vibe-controller-product-film.mp4`
- Poster: `out/poster.png`
- Composition and shot timing: `src/ProductFilm.tsx`
- Three-dimensional controllers, laptops, camera, and cursor: `src/Devices.tsx`
- Synchronized AI workflow, canvas screen, and control cues: `src/Workflow.tsx`, `src/WorkflowScreen.tsx`, `src/workflowState.ts`
- Original score generator: `score.mjs`

```sh
npm ci
npm run score
npm run studio
```

Export with `npm run render`. The `--gl=angle` flag is required for the verified macOS headless render path. `npm run poster` exports the Universal Control hero image. `npm run typecheck` checks the editable source and `npm test` validates every button cue and the dictation/editing state. `ScreenshotWorkflow` and `OCRWorkflow` are independently previewable compositions in Remotion Studio.

## Editorial sequence

| Time | Story |
| --- | --- |
| 0:00–0:05 | A familiar controller becomes a new way to use your Mac. |
| 0:05–0:12 | The app tilts in space; cursor, click, and drag controls lift out of it. |
| 0:12–0:17 | Holding LB reveals a Cross Edge Right shortcut. |
| 0:17–0:26 | An orbiting third-person view demonstrates a cursor moving through three Macs. |
| 0:26–0:50 | Click, capture, paste a screenshot, dictate, correct, send, then select and copy the AI reply. |
| 0:50–1:02 | TextSniper area selection, OCR to clipboard, click into the AI composer, and paste editable text. |
| 1:02–1:06 | Xbox and PlayStation controllers share the stage. |
| 1:06–1:12 | Product end card, animated native controller map, and repository address. |

## Gabe's workflow, visualized

The highlighted controller controls are synchronized to the illustrated laptop's screen: A → click; B → area screenshot; LT + left stick → drag selection; Y → paste; RT → configured voice-dictation shortcut; R3/right-stick click → Backspace; L3/left-stick click → Enter; View/overlapping rectangles → Copy; X → TextSniper OCR shortcut. The main example attaches a screenshot, dictates an instruction, backspaces “green.”, dictates “blue.”, and sends with Enter. The reply is then drag-selected and copied using View.

These are Gabe's customizable mappings, not fixed hardware functions. RT forwards the configured keyboard shortcut; it does not automatically discover different dictation shortcuts on remote Macs. Configure a matching dictation shortcut on each Mac and use your own microphone. The film does not imply that the controller is a microphone. TextSniper or equivalent OCR software is a separate companion app, not an included Vibe Controller OCR engine.

## Asset provenance and representation

The controller SVGs and icon come from this app's source assets. The app close-up uses an existing development-build UI capture from `dist/previews`, cropped into an editorial window treatment. The animated end-card map comes from the app's actual SwiftUI live-feedback components rendered with simulated input by `ControllerLiveFeedbackTests`. Surrounding window chrome and magnified shortcut callouts are rebuilt for the film; these shots are product illustrations, not an unedited screen recording.

The laptop bodies, camera moves, receiving desktops, cursor travel, and connection arc are original 3D/vector demonstrations. The Universal Control sequence is explicitly labeled “Illustrated handoff.” It does not claim to record a physical multi-Mac test. Universal Control must already be configured in macOS, and Vibe Controller's Virtual Hardware Support is installed on the lead Mac. The other Macs do not need Vibe Controller for native handoff.

The AI chat, dictation waveform, screenshot attachment, OCR recognition, and reply are illustrated examples, not a recording of a real AI service or an executed controller test. Dynamic CanvasTextures are drawn from the same frame timeline that drives the 3D button highlights. The film demonstrates this image-plus-voice workflow without claiming a keyboard and mouse are unnecessary for every possible task.

The soundtrack is an original deterministic synthesized composition: no sampled recordings, stock music, vocals, or third-party sound effects. `npm run score` regenerates the expanded stereo WAV, including edit-aligned accents. `node score.mjs` still regenerates the original 40-second score. Typography uses Manrope via Google Fonts. Xbox, PlayStation, Mac, and Universal Control names identify compatibility, not endorsement.

The film deliberately does not promote the hidden experimental A + stick zoom setting or network companion mode. No application configuration was changed to make this film.

## Delivery checks

Render keyframes from every shot, inspect device/texture loading and text boundaries, then export. Verify the expanded MP4 reports 72.2 seconds / 2,166 video frames, 1920 × 1080, 30 fps, H.264 video, and stereo audio. Render outputs and node_modules are ignored by git; the project, original generator, and source assets remain editable.

Original-cut verification, September 7, 2026: TypeScript check passed; all six scenes were visually reviewed from the encoded MP4, including cursor positions on each of the three Macs; the full file decoded without errors. The original delivery is H.264, 1920 × 1080, 30 fps, 1,200 frames, with 48 kHz stereo AAC. `out/review-contact-sheet.jpg` preserves that review.

Expanded-cut verification, September 7, 2026: TypeScript and workflow-timing tests passed. Encoded frames were visually checked for A, B, LT dragging, Y screenshot paste, RT dictation, R3 correction, L3 Enter, View copy, X OCR, OCR selection, and editable-text paste. The full MP4 decoded without errors. Verified: 2,166 H.264 frames / 72.2 seconds, 1920 × 1080, 30 fps, 48 kHz stereo AAC, approximately 20 MB. The AAC container adds 56 ms of padding. Source soundtrack mean level is −17.0 dBFS with a −1.9 dBFS peak. `out/workflow-review.jpg` is the encoded-frame review; `out/workflow-final-poster.png` is the send-to-AI hero frame.
