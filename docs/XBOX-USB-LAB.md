# Xbox Series USB: Share input and vibration

Verified on 2026-09-09 with a physical Xbox Series controller (`045e:0b12`,
`bcdDevice=0509`) connected by USB to macOS 26.5.2. These findings are specific
to this device/firmware/OS combination; they are not a compatibility guarantee.

## Vibration: integrated into the development app

Apple's Core Haptics interface reported supported localities and successful
playback, but the user felt no vibration. Native USB motor output through the
existing Apple HID driver worked, first in a probe and then with the app's
normal two-pulse preview at the saved 50% strength. The user confirmed both.

The important distinction is the API's HID report ID (`1`) versus the first
byte of the native 13-byte GIP buffer (`0x09`). The app uses finite hardware
durations, explicit stop commands, a dedicated output queue, and cancellation
on mute/disconnect. This output path does not capture the USB device or require
another driver installation. See `XboxUSBHapticsTransport.swift`.

## Share: raw USB capture evidence

Apple's `XboxSeriesXGamepad` HID descriptor advertises `MaxInputReportSize=19`.
The normal app therefore receives a 19-byte report whose GIP header announces
a 44-byte payload. Its missing extension bytes contain Share. Apple's optional
Game Controller Share input also produced no events during the earlier test.

With the user's explicit approval, a temporary root-authorized libusb capture
claimed the physical controller's interface 0. It read only interrupt endpoint
`0x82` (64-byte maximum), after one input wake command through endpoint `0x02`.
No audio endpoints, firmware commands, persistent driver changes, or generated
mouse/keyboard actions were involved.

The 30.112-second run received 45 packets, including 33 full 48-byte input
reports. Share appeared at **zero-based byte 22, bit 0**, matching the existing
app parser. The requested physical sequence was captured exactly:

| Gesture | Down (seconds) | Up (seconds) |
| --- | --- | --- |
| Share tap 1 | 9.652 | 9.788 |
| Share tap 2 | 10.300 | 10.436 |
| Share tap 3 | 11.020 | 11.164 |
| Share hold | 12.188 | 14.076 |

A separate A press followed at 14.947 seconds (byte 4, bit 4). Real Share,
release, and A packets are regression fixtures in `XboxShareButtonTests.swift`.
The tests also demonstrate why truncating the same Share packet to 19 bytes
loses that button.

Both interface release and Apple-driver restoration returned success. Registry
inspection confirmed Apple's driver attached again, and the running app
returned to `Ready`, `USB • Direct HID`, `Direct USB vibration is ready`, and
`Universal Control ready`. No persistent privileged helper was installed or
enabled. This proves raw detection, not end-to-end Share shortcuts in the app.

## Repeating the diagnostic

Only run after the user approves the temporary input interruption and
administrator prompt. Keep a trackpad available; reconnect the USB cable if
automatic restoration fails. macOS captures the entire controller device,
even though this probe reads only its gamepad interface.

```sh
clang -Wall -Wextra -Werror -I/opt/homebrew/include/libusb-1.0 \
  Scripts/capture_xbox_usb.c /opt/homebrew/lib/libusb-1.0.a \
  -framework IOKit -framework CoreFoundation -framework Security \
  -o /tmp/vibe-xbox-usb-capture
sudo /tmp/vibe-xbox-usb-capture --capture-30-seconds
```

The program refuses non-root execution, ambiguous/multiple controllers, and
unexpected endpoints. It explicitly releases the interface before restoring
the driver, uses finite read/write timeouts, and stops capture after 30 seconds
(driver reattachment can take additional time). It never enables libusb's
automatic driver-detach option. It is an experiment, not packaged app code.

## Experimental full USB session

The development app now includes an explicit **Full USB input → Enable full USB**
action in the scrolling preferences sidebar. It is **off on every launch**, not a
new default and not a replacement for Native handoff. It is currently restricted
to exactly one Xbox Series USB device (`045e:0b12`) with the validated gamepad
interface/endpoints. PlayStation, Bluetooth, multiple Xbox devices, and other
Xbox product IDs continue to use the existing input paths.

macOS requests administrator authorization for each session. The bundled,
signed `VibeXboxUSBSession` process authenticates the connected app's code
signature and Team ID; the app verifies the root helper in the other direction.
The private local socket accepts only heartbeat, bounded motor pulse, and stop
commands. No persistent helper/daemon, driver replacement, firmware update, or
network listener is installed. The complete libusb 1.0.30 library and its
corresponding source/license are bundled; Homebrew is not required for users or
packaging. Packaging fetches a SHA-256-pinned source archive and builds for
arm64/macOS 14 rather than copying a newer-OS Homebrew bottle.

Full USB reports use the same `ControllerInputRelay` and existing shortcut and
virtual mouse/keyboard engines. Apple HID/GC callbacks cannot override full USB
input while it is active. Share uses the existing per-profile mappings, including
modifier layers. Haptics use the captured USB output endpoint without requiring
an Apple `GCController` object. Every pulse is finite (at most one second per
command), with explicit stop/cancellation. Input/USB work stays off the UI queue.

**Stop full USB**, app quit, sleep, lost socket, or a three-second missing app
heartbeat stops motors and releases the interface before attempting to restore
Apple's driver. The app releases held controller actions when the session ends.
After a disconnect, reconnect the cable and explicitly enable another session;
there is no silent recapture or automatic administrator prompt.

### Known recovery limitation

After the original capture experiment, Apple input recovered and HID motor writes
returned success, **but the user felt no vibration**. Fresh handles and stronger
pulses did not fix it. A physical unplug/replug restored vibration, confirmed by
the user. Driver reattachment/API success therefore does **not** prove physical
rumble recovery. The UI warns to reconnect if ordinary USB vibration is silent
after leaving full USB. Do not claim seamless software recovery until separately
verified on real hardware.

Dev 0.5.3 build 13 is packaged, signed, and locally running. Its nested helper
identity and library dependencies are verified; both helper and bundled library
target macOS 14. The saved user profile is byte-for-byte unchanged. The first
administrator prompt timed out without starting a capture; normal input and
the existing haptics transport recovered automatically. No USB helper remained
running. Non-root standalone invocation is refused before any device access.
The automated suite executed 230 tests: 229 passed, one skipped, zero failures.

The full session's end-to-end hardware verification is pending. Automated tests
cover full-report parsing, source priority against late Apple callbacks, held-input
release/fresh fallback, partial/coalesced/malformed protocol frames, bounded
rumble commands, independent USB haptics, and cancellation/restoration routing.
Actual Share actions, physical vibration, and cross-Mac use must also be tested.

References: [libusb macOS capture requirements](https://github.com/libusb/libusb/wiki/FAQ#how-can-i-run-libusb-applications-under-macos-if-there-is-already-a-kernel-extension-installed-for-the-device-and-claim-exclusive-access),
[libusb 1.0.30 capture/restore implementation](https://github.com/libusb/libusb/blob/v1.0.30/libusb/os/darwin_usb.c),
[Linux xpad GIP initialization](https://github.com/torvalds/linux/blob/master/drivers/input/joystick/xpad.c).
