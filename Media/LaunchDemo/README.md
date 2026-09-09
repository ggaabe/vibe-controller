# Vibe Controller launch demo

Source: `/Users/gabrielgarrett/Downloads/IMG_2958.MOV` (camera original; do not modify).

Editable Resolve project: **Vibe Controller - X Launch Demo**.

The repository contains the filming plans and automation source. Local `.drp`
projects, `review/` captures/logs, and `exports/` videos are excluded from Git:
this unfinished footage still needs the screen-content/privacy review noted
below, and the large review videos exceed GitHub's regular file-size limit.
Those paths are local inputs/outputs, not files downloaded with a clone.

## Editorial direction

- Optimize for audience retention on X, using the actual recorded demonstration.
- Keep the visible connection between controller presses and computer behavior.
- Remove false starts, repeated explanations, and unnecessary waiting without misrepresenting response speed.
- Preserve clear speech and natural pauses. Do not manufacture sentences from unfinished retakes.
- Use a 1920 x 1080, 29.97 fps SDR Rec.709 delivery, with H.264/AAC MP4 exports.
- Preserve the original recording timeline; build revisions as separate timelines.

## Local automation

Resolve Studio 21.1.0.14 was verified running with **Local** external scripting and **Allow safe** automatic scripted actions. Neither setting was broadened.

The community `davinci-resolve-mcp` package, version 2.213.3, is installed in:

`/Users/gabrielgarrett/Library/Application Support/davinci-resolve-mcp`

It is registered as `davinci-resolve` in the local Codex MCP configuration. The previous configuration was backed up as `~/.codex/config.toml.before-resolve-20260908`.

`tools/resolve_mcp.py` is a stdio MCP client for this edit. It invokes the installed server through the MCP protocol, so an already-running Codex session can work without restarting the app. It does not directly modify Resolve's database.

Transcription and footage analysis run locally. The source has not been uploaded to an external editing service. Publishing to X is not part of this task.

## Speech review — 2026-09-08

- Watch: `exports/vibe-controller-speech-review.mp4` (about 92 seconds).
- Editable project backup: `Vibe Controller - Speech Review.drp`.
- Current timeline: **02 - Launch Cut - Speech Review**. The complete source remains in **01 - Original Recording**.
- Nine native source sections are reordered to open with the premise, bring Universal Control forward, and finish with a real dictated request submitted to Codex. The hesitant outro and redundant explanation are omitted.
- `review/editorial-plan.json` holds the semantic choices; `review/cut-placements.json` holds verified native timeline placements.
- Source timecodes are nominal 30 fps; the delivery timeline is 30000/1001 fps. Action footage plays at real time; no response-speed tricks are used.
- iPhone HLG is transformed through DaVinci Wide Gamut/Intermediate to SDR Rec.709 Gamma 2.4. This fixes the incorrect initial HDR conversion, but it cannot recover details already overexposed by the camera.
- Resolve voice isolation is enabled at 35. `tools/finish_review.py` adds 6 ms audio cut-edge fades and a two-pass loudness treatment to the delivery copy only. This final loudness pass is not baked into the editable Resolve source clips.
- Delivery measured **-16.00 LUFS integrated**, **-1.48 dBTP** after AAC encoding. Full video/audio decoding passed; 2755 video frames at 1920 x 1080, H.264/AAC.
- The exported `.drp` passed archive integrity checking. It references the original source in Downloads; keep that file in place or relink it when moving the project.

This is a **speech/pacing review, not the finished launch video**. Captions, selective punch-ins, button callouts, closing treatment, and a final screen-content/privacy pass remain after the speech cut is reviewed.

Camera-original SHA-256: `83564261c7ec69383871e38f56abccae59b66fa6b84d0c77e82a7eff680dece2`.
