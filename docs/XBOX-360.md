# Wired Xbox 360 input

## Scope and setup

- Genuine Microsoft wired Xbox 360 controller, USB vendor/product `045e:028e`.
- macOS 15 Sequoia or later is required for Apple's built-in wired Xbox support. The app's general macOS 14 minimum is not a promise of native wired 360 support on macOS 14.
- Connect its USB-A cable directly, or use a data-capable USB-A-to-USB-C adapter/hub. No legacy 360Controller kernel extension, Full USB capture, or additional input driver is installed by this feature.
- Complete Vibe Controller's normal permissions and Virtual Hardware Support setup for output/Universal Control. This controller input change does not replace or bypass that setup.
- Existing profiles, cursor settings, app-specific overrides, and LB/RB modifier layers remain unchanged.

| Xbox 360 control | Vibe Controller mapping slot |
| --- | --- |
| A / B / X / Y | A / B / X / Y |
| Start / Back / Guide | Menu / View / Home |
| LB / RB / LT / RT | LB / RB / LT / RT |
| Left/right stick and stick press | Left/right stick and L3/R3 |
| D-pad | D-pad |

There is no physical Share button on the 360. Do not expect Share mappings to fire.

Wireless Xbox 360 receivers, wireless controllers connected by Play & Charge cable, original Xbox controllers, legacy kernel-driver report formats, and third-party 360-style devices are not validated by this addition. Other Apple-supported gamepads retain the GameController fallback when the direct reader cannot decode input.

## Implementation

`Xbox360USBReportParser` decodes the 20-byte wired packet: type `0`, length `20`, button bits at offsets 2–3, independent 8-bit triggers at 4–5, and four signed little-endian stick axes at 6–13. Positive Y is up, matching the app's GameController and newer Xbox paths. The existing trigger activation threshold is preserved. Guide press/release is part of every standard 360 report, not the separate timed Guide packet used by newer controllers.

The decoder also accepts the exact 19-byte form with the report-ID byte omitted. Wrong packet types, lengths, report IDs, truncated packets, and status packets are rejected. The newer Xbox GIP decoder remains separate.

The direct reader takes ownership only after a valid standard input report, never just because a Microsoft USB device was discovered. One active physical device owns the direct stream; unrelated devices cannot overwrite or disconnect its state. Active unplug clears held state and restores the cached GameController fallback. Reports are still handled on the dedicated input queue, independent of the remote Universal Control pointer target.

Protocol references (packet facts, not vendored source):

- [SDL wired Xbox 360 decoder](https://github.com/libsdl-org/SDL/blob/main/src/joystick/hidapi/SDL_hidapi_xbox360.c)
- [Linux xpad wired Xbox 360 decoder](https://github.com/torvalds/linux/blob/master/drivers/input/joystick/xpad.c)
- [SDL's native macOS 15 wired-controller investigation](https://github.com/libsdl-org/SDL/issues/11002)

## Verification

Clean release-checkout verification on 2026-11-15: the full Swift test suite executed 281 tests with zero failures and one opt-in published-release staging test skipped. The optimized app build also passed. These automated results do not represent physical-controller certification.

Automated coverage in `Xbox360ControllerTests` and `ControllerInputRelayTests` includes all digital buttons individually, trigger independence/thresholds, signed axis extremes and direction, diagonals, stripped-ID packets, invalid packets, first-valid-report ownership, device isolation, release/unplug behavior, and motion/action routing while the framework fallback reports another state.

```sh
swift test --filter 'Xbox360ControllerTests|XboxUSBReportParserTests|XboxShareButtonTests|PlayStationControllerTests|ControllerInputRelayTests'
swift test
```

**Hardware verification is still pending.** No physical Xbox 360 controller was available during implementation. Automated packet injection is not proof of macOS discovery, Guide interception, rumble, or seamless two-Mac handoff with this hardware.

Before advertising hardware-verified support:

1. On macOS 15 or later, plug in the wired controller and confirm USB `045e:028e` in System Information and detection in macOS Game Controllers.
2. Confirm Vibe Controller reports `USB • Direct HID` after the first input packet. Move both sticks, pull each trigger, press all buttons including Start/Back/Guide and L3/R3, and check live input and release behavior.
3. Exercise the existing profile: cursor/precision motion, click/drag, scroll hold, dictation, screenshot, copy/paste, Enter/Backspace, and both modifier layers. Check Guide does not trigger a conflicting system gesture.
4. Continue motion, drag, and shortcuts after crossing Universal Control to another Mac; test return and modifier + D-pad cross-edge actions. No app is required on the receiving Mac for native Universal Control.
5. Unplug/replug during a held button, trigger, and stick. Confirm input releases and reconnects without restarting. With two controllers attached, unplugging the inactive one must not interrupt the active input.
6. Recheck Xbox Series and PlayStation USB input. Rumble is optional and uses existing capability detection; this change adds no 360-specific rumble transport.
