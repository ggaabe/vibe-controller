# Virtual HID Experiment

Goal: determine whether Vibe Controller can present itself as a real pointing device strongly enough for macOS to
treat it like hardware, rather than as a stream of synthetic Quartz events.

## Why this exists

The original app used Accessibility plus absolute Core Graphics cursor positioning. That worked locally but could not
push through a Universal Control display edge. This lab tested public and private virtual-device routes and ultimately
identified the relative IOHIDSystem path now used by the app.

## Working hypothesis

If macOS accepts a `CoreHID` virtual mouse device and routes it through the normal pointer stack, we may get:

- more hardware-like pointer semantics
- better interaction with system features than plain CGEvent synthesis
- a route that is closer to Magic Trackpad behavior

The successful path has now been verified through a live Universal Control handoff between two Macs.

## Current scaffold

- `swift run VirtualHIDExperiment --status`
  Reports whether the current SDK/runtime can even reach the CoreHID path.
- `swift run VirtualHIDExperiment --descriptor`
  Dumps the boot-mouse HID report descriptor used for the first experiment.
- `swift run VirtualHIDExperiment --create`
  Attempts to instantiate a `CoreHID.HIDVirtualDevice`.
- `swift run VirtualHIDExperiment --demo-motion`
  Attempts to instantiate a `CoreHID.HIDVirtualDevice` and dispatch a few relative-motion reports.
- `swift run VirtualHIDExperiment --iokit-create`
  Attempts the lower-level `IOHIDUserDeviceCreateWithProperties` route directly.
- `swift run VirtualHIDExperiment --iokit-demo-motion`
  Attempts the lower-level route and, if creation succeeds, dispatches a few relative-motion reports.
- `swift run VirtualHIDExperiment --event-system-move --dx 12 --repeat 10`
  Tests private `IOHIDEventSystemClientDispatchEvent`. On a normally signed app, WindowServer rejects this without
  `com.apple.private.hid.client.event-dispatch`.
- `swift run VirtualHIDExperiment --iohid-post-move --dx 12 --repeat 10 --hid-manager-event`
  Posts relative IOHIDSystem motion through the HID-manager path used by the app.
- `swift run VirtualHIDExperiment --iohid-post-click`, `--iohid-post-key`, and `--iohid-post-scroll`
  Exercise the equivalent button, keyboard, and wheel paths.
- `swift run VirtualHIDExperiment --iohid-drag-move`
  Verifies that one persistent IOHIDSystem connection preserves left-button state while relative motion is posted.
- `./Scripts/check_virtual_hid_provisioning.sh`
  Inspects installed signing identities and provisioning profiles for the required virtual HID entitlement.
- `./Scripts/package_virtual_hid_lab.sh`
  Bundles the experiment as `dist/Virtual HID Lab.app` and signs it with the requested virtual HID entitlement.

## Current findings

- The local SDK and runtime both expose `CoreHID.HIDVirtualDevice`.
- Both the `CoreHID.HIDVirtualDevice` path and the lower-level `IOHIDUserDeviceCreateWithProperties` path currently fail to instantiate a virtual mouse on this machine.
- System logs show `IOServiceOpen:0xe00002c2`, which maps to `kIOReturnBadArgument`.
- Apple’s `IOHIDUserDevice.h` header explicitly says the entitlement `com.apple.developer.hid.virtual.device` is required to create a virtual HID device.
- This Mac currently has no installed provisioning profile that grants `com.apple.developer.hid.virtual.device`.
- The private event-system dispatcher reaches WindowServer, but WindowServer rejects it without the private
  `com.apple.private.hid.client.event-dispatch` entitlement.
- `IOHIDPostEvent` with `kIOHIDSetRelativeCursorPosition | kIOHIDPostHIDManagerEvent` succeeds from the normally
  signed app and enters IOHIDSystem's relative pointing-device pipeline.
- That relative HID-manager path triggers Universal Control's hot zone, transfers pointing ownership to the second
  Mac, and continues moving, clicking, typing, and scrolling on the target Mac.

## Result

The app now keeps one IOHIDSystem parameter connection open and posts relative pointer, button, keyboard, and scroll
events through it. The public CoreHID virtual-device route remains useful research for a future entitlement-bearing
distribution, but it is no longer required for Universal Control support.

## Constraints

- `IOHIDPostEvent` is an older, deprecated IOKit API. It works on the tested macOS release but should be reverified on
  new major macOS versions.
- Public CoreHID virtual devices still require Apple's restricted virtual-device entitlement.
- The private event-system route is retained only as a diagnostic and is not used by the app.
