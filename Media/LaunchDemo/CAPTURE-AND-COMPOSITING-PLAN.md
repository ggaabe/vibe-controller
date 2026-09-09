# Controller-first screen pop-out demo

Status: production plan, 2026-09-08. Local Demo Capture is now implemented in the development source: Option-revealed app-menu access, selected-display videos, controller/accepted-action logs, and sync slates. See ../../docs/DEMO-CAPTURE.md and ../../docs/LAUNCH-DEMO-SCRIPT.md. The tracked screen replacement and foreground roto still require a representative real shot; they are not automatic app features.

## Creative direction

Use the real first-person phone footage as the setting. A synchronized, clean display recording begins pinned inside the laptop bezel, lifts forward, rotates toward a readable front-facing view, then settles back. Preserve the hands and pink controller in front of the floating screen throughout. Use this on selected demonstration moments, not continuously.

The approved concept is spatial screen replacement/pop-out; the exact look still needs one representative rendered shot before applying it across the video. This follows the speech-editing and motion-graphics workflow's subject-protection and representative-shot review principles. Resolve/Fusion remains the editor; no ChatCut project or JSX assets are involved.

## Compositing order, back to front

1. Original phone recording: desk, computers, room.
2. Clean screen replacement tracked to the filmed display plane.
3. Animated duplicate of the synchronized screen recording, expanding out of that plane. Blend/hide redundant screen layers as needed so no mismatched time or duplicate animation appears during the transition.
4. Foreground isolation of the original hands, forearms, controller, and any cable crossing the floating screen. These pixels come from the same phone frames, not generated replacements.
5. Minimal labels/captions in positions that leave both the controller and important UI unobstructed.

Start with a 2.5D corner-pinned transition; only solve a full 3D camera if the chosen shot needs it. Build the hand/controller matte with AI-assisted isolation where useful, plus tracked manual roto and edge cleanup. Inspect fast thumb movements, gaps between fingers, cable edges, and motion blur. A mask can keep hands in front, but cannot restore anything outside the camera frame.

Let the clean panel expand mainly above the controller. Keep the action/result region clear of the hands even though the hands can naturally overlap the panel's lower edge. Avoid a floating screen that hides the button press or lets the foreground obscure the important text.

## First proof shot

- Record one short take, approximately 15–25 seconds, on a single Mac first.
- Capture a screenshot selection, dictate a short request, and submit it. Allow the actual workflow duration; do not rush or speed up input-to-result intervals to hit the target.
- Keep hands/controller comfortably in the lower part of the phone frame, with enough room above for readable UI. Inspect the actual framing before settling panel dimensions.
- Keep the relevant screen corners visible. Avoid abrupt neck turns, extreme angles, focus hunting, or sweeping hands over the screen border.
- Use one stable phone lens and orientation, deliberate movement, and consistent lighting. Test exposure/focus before filming. Capture phone and screen at compatible frame rates where available, but retain timestamps rather than assuming nominal frame counts match.
- Use a harmless demo workspace and avoid notifications or private documents on the captured displays.
- Render and review the entire transition: pinned screen, halfway expansion, readable hold, return. Judge readability at phone viewing size and check foreground edges frame by frame where necessary.

No full reshoot or custom recorder is required to prove this effect. Existing camera footage stays available as narration and establishing footage; newly captured screen inserts must not be misrepresented as exact records of an earlier take.

## Recording and synchronization

Record each Mac/display needed for the demonstration locally, alongside the phone. The lead Mac's screen capture does not include the other Mac through Universal Control. Start with built-in recording on the second Mac so it does not need Vibe Controller or a new helper installed.

Use a visible per-display sync slate while the phone can see that display, with an identifiable change recorded both by the phone and that display's screen capture. Give takes and slates unique IDs. Repeat a slate at the end to measure drift. If using shared audio as an additional reference, record an actual common audible cue; a phone clap cannot synchronize a screen capture that contains no microphone audio.

For each source, retain its original presentation timestamps and map it to the phone timeline using measured slate offsets and end-of-take drift checks. Starting recordings at approximately the same time, or comparing separate machines' wall clocks, is not frame-accurate synchronization.

Button-event logs provide candidate markers for presses and actions. They do not establish the exact frame of a visible app response or replace geometric screen tracking. Verify screenshot arrival, dictation appearance, and remote handoff against the real screen frames. Keep real response latency intact. At 30 fps a frame is roughly 33 ms; do not claim finer visual precision than the capture supports.

## Proposed Vibe Controller support: opt-in Demo Capture

Recommendation: do not build a separate full recording app for this launch. First prove the shot with existing recorders. If useful, add a small developer-only Demo Capture mode to Vibe Controller in two increments.

### Increment 1: event log and sync slates

- Explicit Start/Stop, visible active indicator, chosen output folder, unique take/session ID. Disabled by default; developer-only is fine, covert recording is not.
- Observe existing real-time input without replacing its cursor/action handlers. Record button down/up, trigger values, sampled stick positions, modifier state, and separately the resolved action dispatch/result status where available.
- Stamp events with a monotonic host clock at a documented point. Log event receipt separately from action dispatch, including duplicate suppression/cancellation as appropriate. Current `Date()` snapshots are not a calibrated media clock.
- Export a small JSONL event stream and session manifest. Record the mapping/profile identity needed to interpret controls; do not assume RT always means dictation for every profile.
- Do not log arbitrary keyboard input, clipboard contents, dictation text, or screen contents as event metadata. Local-only storage; no uploads.
- Convert events to reviewable Resolve timeline markers after synchronization. Markers suggest cue locations; editorial response timing is verified visually.

### Increment 2: optional integrated lead-Mac recorder

Only if it saves meaningful setup work, add selected-display capture using Apple's ScreenCaptureKit, with explicit macOS capture approval and optional audio choices. Keep screen video and event metadata separate so the screen stays clean for compositing.

Store capture readiness/first-frame information, original media presentation timestamps, their calibrated relationship to the input host clock, resolution/color metadata, source display identity, and recording discontinuities. Log the actual first recorded sample, not only when the Start button was pressed. Test the mapping; do not assume all timestamp domains share an epoch.

Keep encoder, capture callbacks, and disk writes off the high-priority controller input/action paths. A bounded non-blocking event handoff must report overflow rather than stall the controller; throttle analog telemetry independently while preserving button transitions under normal load. Compare input/action latency with recording on/off, and report any event loss or dropped video frames. An encoder failure must never interrupt Universal Control or leave controls held.

No new networking or remote recorder agent in the first version. The other Mac's native recording is aligned by slates. Local input logs cannot reveal the remote foreground app or guarantee when its UI responded.

## Current source evidence

- `Sources/VibeController/Services/ControllerInputRelay.swift`: separates real-time motion, action edges, and coalesced UI telemetry; UI cadence is approximately 15 Hz, so it is not the recording timing source.
- `Sources/VibeController/Services/ControllerManager.swift`: snapshot already contains buttons, analog trigger values, sticks, and a wall-clock update date.
- `Sources/VibeController/App/AppModel.swift`: existing real-time callbacks are already assigned to cursor/action engines; a recording observer must not overwrite them.
- `Sources/VibeController/Services/ActionEngine.swift`: resolves modifier-dependent mappings and executes native actions on a dedicated queue. Logging must distinguish physical input, suppression, and actual dispatch.

## References

- [Blackmagic: Fusion screen replacement, tracking, masks, and 3D compositing](https://www.blackmagicdesign.com/products/davinciresolve/fusion)
- [Blackmagic: Magic Mask and manual cleanup in advanced VFX](https://documents.blackmagicdesign.com/UserManuals/DaVinci-Resolve-20-Advanced-Visual-Effects.pdf)
- [Apple: ScreenCaptureKit capture sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)
- [Apple: screen-frame display time](https://developer.apple.com/documentation/screencapturekit/scstreamframeinfo/displaytime)

Next checkpoint: record and composite one proof shot, then approve the effect before expanding the shoot.
