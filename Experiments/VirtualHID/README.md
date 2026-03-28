# Virtual HID Experiment

Goal: determine whether Vibe Controller can present itself as a real pointing device strongly enough for macOS to
treat it like hardware, rather than as a stream of synthetic Quartz events.

## Why this exists

The current app uses Accessibility plus Core Graphics event posting. That works locally, but it does not make Vibe
Controller a true hardware-like mouse in the eyes of the OS. The experiment here is aimed at the public virtual-device
route instead.

## Working hypothesis

If macOS accepts a `CoreHID` virtual mouse device and routes it through the normal pointer stack, we may get:

- more hardware-like pointer semantics
- better interaction with system features than plain CGEvent synthesis
- a route that is closer to Magic Trackpad behavior

This is not yet proof that it will participate in Universal Control edge handoff. That remains unproven.

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

## Next steps

1. Confirm whether a properly provisioned entitlement-bearing binary changes the `IOServiceOpen` failure.
2. If virtual device creation can be made to succeed, re-run the relative-motion test and confirm whether the local cursor moves without CGEvent synthesis.
3. If local motion works, test whether macOS treats the virtual mouse like a real pointing device at display edges.
4. Only after local device creation works should Universal Control edge handoff be tested.

## Constraints

- This route depends on Apple SDK availability and runtime support.
- It may require additional entitlements or packaging beyond the current app bundle.
- Even if local pointer movement works, Universal Control compatibility is still an open question.
