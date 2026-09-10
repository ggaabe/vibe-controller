# Vibe Controller

<p align="center">
  <img src="Resources/AppIcon.png" alt="Vibe Controller app icon" width="180">
</p>

Vibe Controller is a native macOS app that turns an Xbox or PlayStation game controller into a desktop input device. Use the analog sticks as primary and precision cursors, map controller buttons to mouse actions or keyboard shortcuts, scroll and switch Spaces with the D-pad, and move seamlessly between nearby Macs with macOS Universal Control.

The app automatically presents an Xbox or PlayStation-style live controller map, with native button names and a mappable DualSense/DualShock touchpad click. It also includes per-control and per-app remapping, adjustable cursor response, importable and exportable JSON profiles, input diagnostics, native Universal Control handoff, and an experimental network companion mode for Macs that cannot use Universal Control.

## Download

Signed and Apple-notarized Apple-silicon builds are published on the [GitHub Releases page](https://github.com/ggaabe/vibe-controller/releases). Download the `.dmg`, open it, and drag **Vibe Controller** to **Applications**. The support installer is already inside the app; the separate `.pkg` release asset is provided for repair or managed deployment. The app guides you through Accessibility and its one-time Virtual Hardware Support installation on first launch.

Installed release builds check GitHub once per day and also provide a persistent **Check for Updates** button in the app footer. When a newer signed release is available, choose **Update Now** to download it, verify its published SHA-256 checksum, require the same Developer ID and bundle identity as the running app, replace the app at the same path, and relaunch automatically. Keeping the same signed identity and path preserves macOS privacy approvals. Development builds can check releases but open the release page instead of replacing their deliberately separate app identity.

If the Releases page does not have a build yet, use the source instructions below. Development builds are intentionally kept separate from public downloads so users never receive an unnotarized artifact by mistake.

## Requirements

- macOS 14 or newer
- An Apple-silicon Mac for the packaged release
- An Xbox-compatible, PlayStation DualSense, or PlayStation DualShock 4 controller connected over Bluetooth or USB
- Accessibility permission so Vibe Controller can move the pointer and send input
- Swift 6.2 or a compatible Xcode toolchain when building from source
- Universal Control configured in macOS when controlling another Mac natively
- The one-time **Virtual Hardware Support** install on the lead Mac for seamless Universal Control handoff
- Local-network permission on both Macs only when using the optional companion mode

## Build and run

Clone the repository and run the tests:

```sh
git clone https://github.com/ggaabe/vibe-controller.git
cd vibe-controller
swift build
swift test
```

For normal macOS permission behavior, build and launch the signed development app bundle:

```sh
VIBE_CONTROLLER_SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" ./Scripts/package_app.sh
open "dist/Vibe Controller Dev.app"
```

`package_app.sh` now performs the complete build: it compiles the app and bridge, downloads and verifies the pinned driver when needed, creates Virtual Hardware Support, embeds that installer and the third-party notice, and signs the app. It refuses to produce an app without the driver package. Both Vibe executables must use the same signing identity; set `VIBE_CONTROLLER_SIGNING_IDENTITY` to the exact value shown by `security find-identity -v -p codesigning`.

Local builds are deliberately named **Vibe Controller Dev**, use `com.vibe-controller.app.dev`, and keep profiles under `~/Library/Application Support/Vibe Controller Dev/`. Public builds remain **Vibe Controller** with `com.vibe-controller.app`. This separation lets contributors test permissions and profiles without replacing or modifying the installed public app.

## First-run setup

1. Connect the controller over Bluetooth or USB and open Vibe Controller.
2. The app checks setup automatically and requests Accessibility. Approve Vibe Controller in **System Settings → Privacy & Security → Accessibility**. If an upgraded copy already appears enabled but the app still reports that access is missing, remove the old row with **−**, reopen Vibe Controller, and enable the newly added row.
3. The bundled **Virtual Hardware Support** installer opens automatically. Approve its one-time administrator prompt.
4. Vibe Controller requests Driver Extension activation and keeps Step 3 visible at the top of its window. Choose **Open Driver Settings**, open **Extensions**, find **.Karabiner‑VirtualHIDDevice‑Manager Driver Extension**, click **Show Detail**, and enable **Provides additional functionality for system drivers**.
5. Return to Vibe Controller. It polls each gate and advances on its own; the Universal Control panel finishes at **Native handoff — Virtual mouse and keyboard are active**.
6. Confirm that the header reports the controller as connected, then move the sticks and press buttons while watching the live diagnostics and blue controller-map highlights.
7. Click any control on the map to change its action or shortcut, and adjust cursor response in the Cursor panel as desired.

The app requests each missing step only once per launch so it does not trap users in repeated system dialogs. A persistent setup banner stays above the scrollable controller workspace until every gate is complete, so **Open Accessibility Settings**, **Open Installer**, **Open Driver Settings**, and **Check Again** remain reachable at every supported window size. Returning from System Settings refreshes the current permission and repeats any still-pending instructions. macOS intentionally requires a person to approve Accessibility, the administrator install, and the Driver Extension; the app can detect and open those gates but cannot silently bypass Touch ID or the account password.

Profiles are saved locally at `~/Library/Application Support/Vibe Controller/profiles.json`. Open **Manage Profile** in the footer, then use **Import Profile** or **Export Profile** to move an individual profile between Macs.

### Customize your controller

The controller workspace uses original, resolution-independent Xbox and PlayStation SVG artwork with visible bumpers and triggers. The layout follows your connected controller; use the **Xbox / PlayStation** menu above the illustration to preview either design without changing your profile.

Use **Color** beside the layout selector to choose Original, Graphite, White, Blue, Pink, or Green. Shell colors are remembered separately for Xbox and PlayStation, including after restarting the app. This changes only the illustration: button colors, live input highlights, mappings, and profiles stay unchanged. **Original** restores the layout's stock finish.

- Action labels appear around the controller by default, with lines connecting them to each button. Click a label or physical button to remap it. **Show labels** remembers your preference; when labels are hidden, hover over a button to inspect its action below the map. Click the stick itself for **L3 / R3**; use the **Left Stick / Right Stick** controls below the artwork to change its cursor role.
- Live input moves the thumbstick caps, fills and depresses triggers in proportion to their pull, and lights up pressed buttons. Short taps remain visible briefly without extending their mapped action. Feedback works with labels on or off; display interpolation does not affect the real-time cursor or HID loop.
- **Xbox Share** (the upload-shaped button below Home) has a mapping editor: click the icon or its **Share** label, or find it in **Bindings**. Fresh installs use Gabe's saved slash shortcut; existing profiles without a Share mapping remain unassigned. On the tested Xbox Series X|S USB connection, Apple's normal driver truncates the report before Share, and [Apple's optional Share-button input](https://developer.apple.com/documentation/gamecontroller/gcxboxgamepad/buttonshare) does not deliver its presses. Public builds show **Share unavailable on this USB connection** without asking for more permissions. Saved Share mappings and modifier overrides remain intact for supported connections. Experimental Full USB capture is limited to Dev builds while reliability is tested. Other buttons and native Universal Control do not require Full USB. Older Xbox controllers without a physical Share button cannot generate this input. PlayStation Share/Create remains the existing **Create** control.
  See [USB investigation and verification status](docs/XBOX-USB-LAB.md) for the captured evidence and current limitations.
- Choose **Bindings** to search all buttons and assigned actions in a readable list.
- Use **App** to edit system-wide settings or an app-specific override. Apps without an override inherit **All Apps**.
- Select a modifier layer or hold its controller button to update the visible action labels and highlight its overrides. In the artwork-only view, modifier shortcuts appear as chips below the map.
- Cursor speed, precision, dead zone and flick boost live in the preferences sidebar. Diagnostics and advanced connection options stay collapsed until needed.

## Universal Control between Macs

Vibe Controller sends relative motion, mouse buttons, scrolling, and keyboard shortcuts through a DriverKit virtual mouse and keyboard. macOS recognizes them as hardware devices, so Universal Control keeps forwarding their reports after the pointer crosses onto another Mac. Cursor-warp and synthetic-event APIs can reach Universal Control's edge, but macOS stops routing those events after handoff; the virtual devices are what make continued motion possible.

Only the lead, controller-connected Mac needs Vibe Controller for this mode. The second Mac does not need the app, the companion receiver, or local-network permission.

1. Set up Universal Control on both Macs using [Apple's instructions](https://support.apple.com/en-us/102459). The Macs should already let the lead Mac's trackpad move through the chosen display edge.
2. Complete the automatic three-step setup shown in Vibe Controller. This installs the open-source [Karabiner DriverKit VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice) and Vibe Controller's signed bridge, then requests the required macOS approvals.
3. Wait for the Universal Control panel to show a green **Native handoff** status.
4. Connect the Xbox or PlayStation controller to the lead Mac. USB is recommended: supported Microsoft Xbox, Sony DualSense, and Sony DualShock 4 USB devices use a direct HID reader that remains active while Universal Control owns the pointer on the second Mac.
5. Leave the recommended native handoff active; fresh installs select it automatically. Move the primary stick through the same left or right edge used by Universal Control. Keep holding the stick and the pointer will continue across the second Mac.
6. Click, scroll, dictate, capture a screenshot, or start an LT drag after the pointer arrives on the second Mac. Those mapped actions follow the Universal Control pointer target.
7. Push back through the corresponding edge to return to the lead Mac.

The installed bridge runs with elevated privileges because the virtual-HID daemon accepts only root clients. It accepts commands only through a pipe inherited from the same-team signed production or explicitly separated development app; unrelated local processes are rejected. The older IOHIDSystem route remains available as a local-pointer fallback but is not presented as successful cross-Mac control.

The app falls back to Apple's Game Controller framework for Bluetooth controllers and other compatible gamepads. Direct USB input is preferred for the cleanest cross-Mac handoff because it is read on the lead Mac independently of Universal Control's active pointer target.

### What Virtual Hardware Support installs

Yes—the HID component is required. Universal Control stops forwarding ordinary synthetic cursor events after the handoff, while a virtual hardware mouse continues like a trackpad. The bundled support package contains:

- The unmodified, signed, and Apple-notarized **Karabiner-DriverKit-VirtualHIDDevice 8.2.0** package, pinned by SHA-256.
- Vibe Controller's small signed bridge, installed setuid-root because the Karabiner daemon accepts only root clients. The bridge rejects callers unless its parent is the same-team signed production app (`com.vibe-controller.app`) or explicitly separated development app (`com.vibe-controller.app.dev`).
- No software for the second Mac; all support lives on the lead Mac.

`THIRD_PARTY_NOTICES.md` is embedded in every packaged app. The source repository does not commit the third-party binary: the packaging script downloads it from the tagged upstream release, verifies its exact checksum and Apple notarization, and then embeds it in the app's Resources directory.

Public downloads are built by the tag-driven release workflow, which requires Developer ID Application and Installer certificates, notarizes the installer, app, and DMG, validates them with Gatekeeper, and publishes SHA-256 checksums. See [RELEASING.md](RELEASING.md) for credential setup and release steps. Local source builds can use an Apple Development identity and an unsigned outer installer, but macOS will still show the expected administrator approval.

## Gabe's Defaults profile

Fresh installs start with **Gabe's Defaults**, containing Gabe's current saved configuration:

The complete saved configuration is also available as an [importable JSON profile](Profiles/GAPE.json) (the existing GAPE filename is retained). A fresh-install test checks that the bundled defaults exactly match this snapshot, including per-action vibration, modifier layers, and app overrides. Updating the app does not overwrite or rename an existing saved profile.

PlayStation controllers use the same physical-position mappings: Cross/Circle/Square/Triangle correspond to A/B/X/Y, L1/R1/L2/R2 correspond to LB/RB/LT/RT, Create corresponds to View, Options corresponds to Menu, and PS corresponds to Home. The PlayStation touchpad click is also available as an additional remappable control.

| Control | Default action | Notes |
| --- | --- | --- |
| Left stick | Primary cursor | Approximately 2228 px/s |
| Right stick | Precision cursor | Approximately 566 px/s |
| LT | Left mouse hold | Hold while moving the cursor to drag |
| LB | Escape / modifier | Tap for `Esc`; hold with a D-pad direction to cross the matching Universal Control edge |
| RT | Voice dictation | Holds the `Fn` key; configure macOS Dictation to use the Fn shortcut if needed |
| RB | Right click | Standard secondary click |
| A / Cross | Left click | Standard primary click; left-stick movement stays available while held |
| B | Area screenshot to clipboard | Sends `⌃⇧⌘4`; drag over an area, then paste the screenshot |
| X | TextSniper OCR capture | Sends `⇧⌘2`; drag over text to OCR it into the clipboard |
| Y | Paste | Sends `⌘V` |
| D-pad up/down | Scroll | Repeats while held |
| D-pad left/right | Switch Space | Moves one macOS Space left or right |
| L3 | Return | Sends the Return key |
| R3 | Delete | Sends backward Delete |
| View | Copy | Sends `⌘C` |
| Menu | New tab | Sends `⌘T` |
| Home | Close tab or window | Sends `⌘W`; disable any competing Home-button action in macOS Game Controller settings |
| Share (Xbox Series) | Type `/` | Requires a transport that exposes Share; full USB is experimental |

Holding a scroll control sends one step immediately, waits the configured repeat delay (350 ms by default), then continues at the configured interval (80 ms by default). Native scrolling runs on its own input queue, including through Universal Control, and temporarily prevents App Nap while held. Releasing the button or disconnecting the controller stops the repeat without waiting for the UI. Your repeat timings and mappings are preserved.

Native button actions also run on a dedicated high-priority queue: keyboard shortcuts, dictation trigger presses/releases, clicks, drags, and edge crossings do not wait for the controller-map UI to render. Modifier layers and app-specific overrides use the same mapping resolver. Configuration changes invalidate queued old actions, and disconnecting or disabling input releases held keys. The optional network-companion routing remains separate from native Universal Control.

The cursor profile enables acceleration with a `0.12` dead zone, `1.8` response curve, `0.5` smoothing, neutral axis multipliers, and flick boost disabled. The experimental A / Cross + left-stick zoom gesture is disabled by default, and its toggle is hidden for now. Explicit values in existing imported profiles are preserved.

### Recommended OCR companion

The X-button workflow expects [TextSniper](https://textsniper.app/) or an equivalent screen-OCR utility listening for `⇧⌘2`. TextSniper lets you drag over any visible text, recognizes the selection, and puts the editable OCR result directly on the clipboard. It is a separate paid app and is recommended if you want the default OCR workflow; you can instead install another OCR tool and remap X to its capture shortcut.

### Voice dictation and area screenshots

- **Voice dictation:** RT sends and holds `Fn`. Enable Dictation in macOS Keyboard settings and select an Fn-based Dictation shortcut, or remap RT to the shortcut you prefer.
- **Area-select screenshot:** B sends `⌃⇧⌘4`, macOS's selection screenshot shortcut with Control added so the result goes to the clipboard instead of a file. Drag the area and paste with Y or `⌘V`.
- **OCR area selection:** X sends `⇧⌘2`, TextSniper's standard Capture Text shortcut. Drag the text area; the OCR result is copied automatically, and Y pastes it.

## Remapping controls

Click a button, trigger, stick-click control, or D-pad direction on the controller map. Choose an action type and trigger behavior, then save it. Supported actions include:

- Keyboard shortcuts
- Left, right, middle, and double click
- Left-button drag
- Vertical and horizontal scrolling
- Space switching
- One-tap Universal Control edge crossing
- Primary/precision cursor-speed toggling

Stick roles are configured separately by clicking either stick. Shortcut assignments and cursor settings are persisted automatically.

### Developer-only full USB input (Xbox Series)

**Public releases do not offer or package Full USB capture.** It remains
experimental because sessions can time out and switching back can leave
vibration silent until the controller is unplugged and reconnected. The normal
USB/Bluetooth input paths, vibration settings, and native Universal Control
remain available. Full USB is not part of the normal installation process.

The following instructions are only for the signed **Vibe Controller Dev**
bundle (`com.vibe-controller.app.dev`). Public builds also reject session
startup internally and omit the exclusive-USB helper and libusb dependency.

In the scrolling preferences sidebar, choose **Full USB input → Set up Full USB**.
Approve the signed helper in **System Settings → General → Login Items & Extensions**
(look for Vibe Controller Dev). Return to the app and choose
**Enable full USB**. Approval is saved by macOS; later sessions do not launch a
new administrator password prompt. No password is stored by the app.
The app temporarily takes exclusive
ownership of one Xbox Series USB controller (`045e:0b12`), reads full input
including Share, and routes vibration through that same session. Your existing
button, modifier, cursor, and app-specific mappings are retained. Native
handoff still uses the same virtual mouse/keyboard output; nothing needs to be
installed on the other Macs.

This option is experimental and off on each launch. Other apps cannot use the
controller while it is enabled. Keep a trackpad available when testing. Choose
**Stop full USB** to return it to macOS; app quit, sleep, connection loss, and a
missing app heartbeat also end the session. A registered, signed background helper
runs on the lead Mac, on demand; registration alone does not capture the controller.
After stopping Full USB, **Remove USB Helper** unregisters it without changing
your mappings or Universal Control support. macOS may require approval again if
you revoke the helper, switch app identities, or reinstall it. The USB library,
source, and license are bundled with the app.

**Recovery caveat:** if normal USB vibration is silent after switching back,
unplug and reconnect the controller. Driver restoration alone has not reliably
restored physical rumble in testing. Full-session hardware verification is still
in progress; see the [USB lab notes](docs/XBOX-USB-LAB.md).

### Share button setup

In public builds, an affected Xbox connection shows an informational **Share unavailable on this USB connection** notice in the controller map, Bindings, and Share editor. There is no Full USB activation button or automatic permission prompt. You can still edit and save Share shortcuts; the app does not delete them just because the current connection omits Share.

In **Vibe Controller Dev only**, the notice can offer **Enable Full USB** and explain the exclusive session before helper approval. **Edit Without Enabling** keeps the editor usable without taking over the controller. Working Share transports, PlayStation Create, and legacy Xbox controllers do not receive this notice. Physical Share presses cannot open a prompt when macOS omits those events entirely.

### Optional controller vibration

Every button editor includes a **Vibration pattern** picker and **Test vibration** button. Choose None, Soft tap, Double tap, Thump, Left pulse, Right pulse, or Grab & release. Previewing a pattern never runs its keyboard or mouse command. Patterns are saved with the mapping, including modifier layers and app overrides; **Use Default / Use All Apps** restores the inherited action and its feedback together.

The **Vibration** section in the preferences sidebar has a master **Haptic feedback** switch, strength slider, test button, and optional connection pulse. Fresh installs use Gabe's saved preferences: **enabled, 50% strength, connection pulse on**. These preferences are remembered separately on each Mac; upgrading preserves an explicit mute or other saved preference. **Use suggested patterns** applies the recommendations to the current profile and enables feedback without changing any shortcut or cursor setting:

| Action | Suggested vibration |
| --- | --- |
| Cross Edge Left / Right | Left / Right pulse, falling back to the controller's default motors if needed |
| Cross Edge Up / Down | Thump |
| Tap LB or RB alone | Soft tap when released and its default action runs |
| LT drag | Grab & release: a start tap and lighter end tap |
| B area screenshot / RT Fn dictation | Soft tap |
| X TextSniper capture | Double tap |
| Ordinary click, paste, typing, cursor movement, and scrolling | None |

Holding a modifier by itself is silent until its default action runs on release. If you use a combination such as **RB + Y** or **LB + D-pad Up**, only the resolved combination's vibration plays; releasing the modifier does not also play its default feedback. A combination configured with no vibration stays silent. Held actions can still play their own Grab & release end pulse when they end.

The bundled Gabe's Defaults profile includes these patterns plus Gabe's custom **Home → Thump** and **L3 → Soft tap** choices. **Use suggested patterns** deliberately replaces custom feedback with the suggestions above. Existing profiles without per-button vibration settings stay silent for those buttons. Recommendations follow the configured action, so remapped buttons do not receive misleading feedback just because of their physical label. The connection pulse indicates that a haptic-capable controller connected—not that all system permissions are approved.

For the tested Xbox Series X|S USB model (`045e:0b12`), the app automatically sends native motor commands through Apple's existing USB HID driver. This works without installing another driver, detaching the controller, or requesting administrator access. The direct path is selected only when exactly one matching USB controller is present. Other controller connections use Apple's Game Controller / Core Haptics API; reported API support does not guarantee physical vibration, so use **Test vibration** to verify your connection. Unsupported hardware keeps working without vibration.

Vibration runs on the lead Mac independently of virtual mouse/keyboard output. Pulses are finite, run on a separate queue, and acknowledge command dispatch—not screenshot/OCR completion, active dictation, or successful arrival on another Mac. Held/repeating actions do not continuously rumble. Disabling input, disconnecting, or changing mappings cancels pending feedback. No AI-task completion or remote-app notifications are inferred from Universal Control.

### App-specific shortcuts

Use the **App** picker above the controller map to edit shortcuts for **All Apps** or for one application. Choose **Add App** to select a currently running app, browse for an installed `.app`, or install the bundled **Codex Starter** mappings. App-specific mappings are sparse overrides: any control you do not change automatically uses its **All Apps** action, including modifier-layer actions.

Inside a control editor, **Use All Apps** removes that one app override. The **App Settings** menu can **Reset to All Apps** to clear every override for the selected app, remove the app from the picker entirely, or restore the Codex starter set. Saving **None** is different from removing an override: it intentionally disables that control only in the selected app.

The Codex / ChatGPT starter intentionally keeps only the broadly useful chat-navigation actions. Every other control inherits its **All Apps** action:

| Control | Codex action |
| --- | --- |
| Menu / Options | New chat (`⌘N`) |
| LB / L1 or RB / R1 + Menu / Options | Next chat needing attention (`⌥⌘A`) |
| LB / L1 or RB / R1 + View / Create (the All Apps copy button) | Fork chat (`⌥⇧⌘F`) |

Codex exposes Fork chat as an assignable command but does not ship a default keyboard chord for it. When this starter is active and Codex is installed, Vibe Controller non-destructively adds `Command+Alt+Shift+F` for Codex's `forkThread` command in `~/.codex/keybindings.json`. Existing Codex shortcuts are preserved. On another Mac controlled through Universal Control, add the same Fork chat shortcut in Codex's **Settings → Keyboard shortcuts**; Vibe Controller itself still does not need to be installed there.

Vibe Controller detects the frontmost application on the lead Mac and switches these mappings automatically. Keyboard output still follows the Universal Control pointer to another Mac, but Universal Control does not report that other Mac's frontmost app back to the lead Mac. Without a companion app on the second Mac, remote shortcuts therefore use whichever app scope is active on the lead Mac; **All Apps** remains the predictable fallback.

### Modifier layers

Modifier layers let one controller button expose a second set of actions without replacing its normal tap action. In **Controller Map**, choose **Add Modifier**, select a control such as LB, and then switch the Layer picker to **LB held**. Click any other control to save an override for that combination.

- Hold any configured modifier on the controller to preview that layer live on the map. Release it to return to the layer you were editing.
- Tap the modifier by itself to run its normal Default action.
- Hold the modifier and press a control with an override to run the alternate action.
- Controls without an override continue using their Default action.
- Choose **Use Default** in an override editor to remove that override.
- Saving **None** as an override intentionally suppresses that control while the modifier is held.

Modifier combinations are resolved on the controller-connected Mac before the resulting mouse or keyboard input is sent. They therefore continue to work through native Universal Control without installing Vibe Controller on the other Macs.

For example, add an **LB** modifier layer and map **LB + D-pad Left/Right/Up/Down** to the matching **Cross Edge** actions. Each action sends a brief, fast virtual-mouse sweep through the chosen Universal Control edge; the other Mac does not need Vibe Controller installed.

Gabe's Defaults ships with the current modifier setup already configured:

| Combination | Action |
| --- | --- |
| LB + X / Square | Type a period (`.`) |
| LB + Y / Triangle | Type a Space |
| LB + Share (Xbox Series) | Send Shift-2 (`@` on a US keyboard) |
| RB + Share (Xbox Series) | Send Shift-4 (`$` on a US keyboard) |
| RB / R1 + Y / Triangle | Send Control-V (alternate paste / app-specific command) |
| RB / R1 + Menu / Options | Press Tab (for CLI queueing or navigation); plain Menu remains Command-T |
| LB / L1 or RB / R1 + L3 | Press Shift + Return (insert a newline in supported apps) |
| LB + RB / R1 | Press Left Command + Right Command |
| LB + D-pad direction | Cross the matching Universal Control edge |
| RB / R1 + D-pad direction | Cross the matching Universal Control edge |

These are **All Apps** defaults; explicit app-specific mappings still take precedence. For example, the Codex starter keeps RB + Menu assigned to the next chat needing attention. Existing saved profiles are preserved when updating; the new defaults apply to fresh installs or a profile reset.

## Optional two-Mac companion mode

Companion mode can forward cursor motion, clicks, scrolling, shortcuts, and Space-switch actions over the local network. It is an advanced fallback for Macs that cannot use native Universal Control; most two-Mac setups should use the Universal Control instructions above.

1. Run Vibe Controller on both Macs and expand **Universal Control → Advanced connection mode**.
2. Set one Mac to **Receiver Mac**.
3. Set the controller-connected Mac to **Controller Mac**.
4. Choose the handoff edge and receiver, then connect.
5. Push the cursor through that screen edge to hand control to the receiver. Move through the corresponding return edge to come back.

Both Macs need Accessibility and local-network permission. The Companion panel shows peer/build metadata and handoff diagnostics; **Force Handoff** and **Return Local** are available for testing.

## Utilities and experiments

- `ControllerProbe` prints controller input for low-level diagnostics.
- `VirtualHIDExperiment` and `Experiments/VirtualHID` contain exploratory input-routing work.
- `VibeVirtualHIDBridge` is the minimal privileged bridge used by the DriverKit virtual mouse and keyboard.
- `Scripts/check_virtual_hid_provisioning.sh` checks the local signing and provisioning prerequisites for that experiment.
- `Scripts/fetch_virtual_hid_driver.sh` downloads and verifies the pinned, notarized third-party driver package.
- `Scripts/package_virtual_hid_support.sh` creates the combined one-time support installer.
- `Scripts/build_release.sh` validates the complete DMG and installer release path; public mode also signs, notarizes, and checks Gatekeeper acceptance.

## Development

### Demo capture for filming

Hold **Option (⌥)** while opening the **Vibe Controller** macOS app menu to reveal **Demo Capture…**. It records selected local displays and a separate timestamped controller/action log for editing product demos. Recording is explicit, local and video-only; the other Mac must be recorded separately. See the [capture guide](docs/DEMO-CAPTURE.md) and [launch demo filming script](docs/LAUNCH-DEMO-SCRIPT.md).

Select both the laptop and its external monitor to create an optional **follow-cursor review movie** after recording. Separate full-resolution movies are retained. The panel shows storage usage, flags takes over 14 days old for manual review, requires 5 GB free to start and attempts to stop/save below 2 GB. It never automatically deletes your footage.

Run the complete test suite with:

```sh
swift test
```

The app is implemented in SwiftUI and uses Apple's GameController, CoreGraphics, ApplicationServices, and Network frameworks.
