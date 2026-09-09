# Demo Capture

Hold **Option (⌥)** and click **Vibe Controller** in the macOS menu bar. Choose **Demo Capture…**. You can also hold Option after opening the menu. This is a filming utility, not an always-on recorder.

1. Start the phone recording first; keep the laptop bezels and your hands/controller in frame.
2. Choose the local displays to record and an output folder. Only displays attached to this Mac are listed. Select both the laptop and its external monitor to use **Follow cursor across selected displays**.
3. Grant Screen Recording access if asked, then press **Record**. The app checks permission again; macOS may require a relaunch after the first grant.
4. A two-second **START** slate appears after every selected stream has delivered a frame. Film it. The panel then gets out of the way.
5. Use **● REC** in the menu bar to reopen the controls. **Add Marker** creates an editorial cue without covering the screen. **Sync Slate** creates another visible reference; **End Slate** gives you an end-of-take drift check.
6. Film the END slate, then press **Stop & Save**. Do not stop the phone before the slate. **Show Take** reveals the folder. Normal Quit waits for videos and logs to finish saving.

While a capture is active, its app-menu item remains visible without Option. Closing the panel does **not** stop recording; the persistent menu-bar indicator brings it back.

## Files

By default takes go to `~/Movies/Vibe Controller Demo Captures/<timestamp>-<unique ID>/`.

- `display-<id>.mov`: one clean SDR H.264 video per display, with the cursor, up to 4K and 60 fps. Aspect ratio is preserved. Frames can be variable-rate on an unchanged screen; the quiet tail is retained until Stop.
- `events.jsonl`: controller states, accepted resolved mappings, editorial markers and video timing anchors. JSON Lines is for scripts/tools, not a native Resolve import format.
- `session.json`: capture status, clock origin, per-display offsets, resolution, encoded/dropped frames, event counts and errors.
- `READ-ME.txt`: timing and editing instructions that travel with the take.
- `follow-plan.json` (when following): editable cut decisions, source offsets and the review movie's session origin.
- `follow-cursor.mp4` (when following and export succeeds): an additional 1920×1080 review movie, up to 30 fps, switching among the recorded displays. Unchanged images may be held instead of encoded repeatedly. Original display movies are never replaced.

`complete` means finalization succeeded. `incomplete` means inspect the errors; some footage may still be usable. `recording-not-finalized` means the process did not complete finalization (for example, after a crash). Do not discard partial files automatically.

## Follow cursor on the lead Mac

The follow option is on by default but only takes effect with at least two explicitly selected displays. It observes actual pointer position at about 30 Hz on a separate queue; joystick movement, trackpad movement and LB/RB + D-pad jumps all use the same detector. A crossing must remain on the new display for about 120 ms. Once confirmed, the cut is placed at the first observation of that crossing, avoiding both border flicker and an extra confirmation delay in the edit.

During recording, the panel names the display being followed. **After Stop & Save**, it builds the review movie; it does not stop/restart individual display recordings or discard the inactive display. Screens are fitted into the review canvas without cropping. `display_changed` events and the separate edit plan preserve the switch timing for further editing.

Only the time covered by every source is included in the review movie, avoiding black gaps while a stream starts or stops. `follow-plan.json.sessionOrigin` tells you where review time zero lies in the capture session. Check `followExportNote` if the extra export was skipped/cancelled. A low-space or failed review export does not change the status of already-saved original recordings. Quitting waits for original video finalization, but skips/cancels the optional review export.

An unselected display or an unknown/remote pointer position does not select a new capture source. Universal Control may leave the local pointer position at an edge; this feature cannot infer the remote Mac's screen or app and retains the last local source.

## Disk space and cleanup

The panel shows recognized take count, allocated size, current-take size while recording, free space, and an estimated recording rate. At the current encoder limit, two large displays can target roughly **600 MB per minute**, plus the review movie. Actual usage varies with resolution and content.

- At least **5 GB free** is required before starting. An unavailable space reading blocks a new take.
- Free space is checked about every two seconds during capture. Below **2 GB**, or if the destination can no longer be checked, the app attempts to stop and finalize the take. This is a safety margin, not a guarantee against sudden disk disconnection or competing writes.
- Review export has its own space budget and cancellation check. If it cannot safely finish, originals and the edit plan remain available.
- Takes older than **14 days** are flagged when you open/refresh Demo Capture. **Review Older Takes in Finder** selects them for your review. The currently recording take, unrelated folders, symlinked folders and phone footage outside these recognized capture sessions are not included.
- **No automatic deletion or background cleanup runs.** Back up your original footage or final edit before removing takes. Moving files to Trash does not free disk space until Trash is emptied.

For a filming session, keep takes short, review the result, and remove obvious false starts after you know the good take is intact. The storage reminder is in-app, not a scheduled notification.

## What the timing means

Events use the host monotonic Core Media clock. Stream presentation timestamps are explicitly converted from each `SCStream.synchronizationClock`, and each movie starts at its first encoded frame. For a local display:

`video time = event.time − display.firstFrameSessionTime`

An input state, an accepted mapping and the visible result are different moments. The log does not claim to measure OS or remote response time. Resolved actions are logged once per activation, not every held-repeat tick. A modifier's solo action is resolved on release. Analog telemetry is capped at 60 Hz; discrete button/trigger edges bypass that throttle. A bounded queue reports overflow instead of waiting for disk I/O on the controller path.

These clocks do **not** synchronize the phone or the other Mac. Align the visible slates in both recordings and check end-of-take drift. Slate metadata records when a slate was requested; use its actual visible frame for final alignment.

## Privacy and multi-Mac scope

Recording is local, opt-in and video-only. No microphone/system audio capture, clipboard reads, global keyboard logging or uploads are added. Screen pixels can still include private information: close sensitive windows and enable Do Not Disturb before recording. Use the phone's narration audio; your dictation microphone remains available to its existing app.

Universal Control does not return the other Mac's screen or foreground-app identity. Record that Mac locally (its built-in recorder is sufficient), and film distinct start/end visual cues on it. Nothing new is installed on the other Mac by this feature.

The automatic follow-cursor review is not the final product film. Tracked screen replacement, floating panels, hand/controller isolation and speech editing still happen in Resolve/Fusion using the [Launch demo script](LAUNCH-DEMO-SCRIPT.md).

## Testing

`swift test --filter DemoCaptureTests` covers menu visibility rules, trigger/button edge preservation, bounded storage backlog, session isolation, accepted modifier mappings, input latency under blocked storage/main thread, video dimensions, encoder finalization/decoding and a static-screen tail. Synthetic video tests do not record the desktop or request permissions. Real screen permission and multi-display behavior must also be checked on the installed app.

`swift test --filter DemoFollowTests` adds vertical/negative-coordinate jumps, border flicker, mirrored/unselected displays, clock-aligned cut plans, storage thresholds, scoped read-only inventory, low-space export protection, aspect fitting, and a real exported two-source movie. It decodes the result and seeks into the last held frame to check that the correct source is visible, then compares original file bytes to verify preservation.

`swift test --filter DemoCaptureAppMenuTests` drives actual `NSMenu` root tracking notifications with injected Option state. It covers Option before opening, pressing/releasing Option while the menu tracks, SwiftUI menu replacement, duplicate prevention, unrelated popup isolation and timer teardown. AppKit sends tracking notifications from the **main menu bar**, not the app-name submenu; filtering on the submenu prevented the command from appearing. These tests do not synthesize system input or start recording.

API references: [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos), [stream synchronization clock](https://developer.apple.com/documentation/screencapturekit/scstream/synchronizationclock), [frame display time](https://developer.apple.com/documentation/screencapturekit/scstreamframeinfo/displaytime).

## Interface review

### Discoverability and safe recording state

| Before | After |
| --- | --- |
| No capture entry point | Native app-menu command revealed by Option, without adding clutter to the controller map. |
| No capture controls or consent context | A dedicated scrollable panel with display selection, take name, folder chooser, permission explanation and explicit Record. |
| No way to see or end a hidden recording | Active app-menu command and persistent REC indicator reopen the panel; Stop & Save finalizes, and normal Quit waits. |
| No filming cues | START/SYNC/END slates and unobtrusive editorial markers; the panel hides after recording starts. |
| No capture progress or recovery feedback | Tabular elapsed timer, preparing/saving states, visible errors and Show Take. |
| No capture-specific recording or metadata workflow | Separate display movies, a bounded event journal, clock anchors, finalization tests, this guide and the filming script. |
| Separate movies only | Follow-cursor toggle, current-source label, stable crossing log, edit plan and automatic 1080p review export. |
| No storage visibility or cleanup cues | Tabular size/free-space information, rate estimate, 14-day review banner and Finder links; no automatic deletion. |
| No disk-space guard | Start/capture/export safety margins; failed optional exports leave original footage alone. |
| No derivative export progress | Visible progress and quit-aware cancellation for the extra review copy. |
| Quiet-tail finalization could omit the last hold frame if the encoder was busy | Bounded asynchronous readiness wait, explicit final-frame duration and end-frame regression checks. |
| Option reveal listened to the app submenu, so opening the real macOS menu did not refresh it | Listen to the main menu bar's tracking notifications; check Option on open and while tracking, restore the item after a menu rebuild, and stop polling when that same menu closes. Five notification-level regression tests cover this lifecycle. |
