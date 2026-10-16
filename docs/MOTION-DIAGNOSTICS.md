# Cursor motion timing

The cursor loop targets 120 reports/second on a dedicated user-interactive
queue. Controller input and UI telemetry are separate: a held stick must keep
moving even when its value is unchanged or the main thread is busy.

## Background responsiveness

Joystick movement, its smoothing tail, and cross-edge sweeps hold a scoped
`ProcessInfo` activity with `userInitiatedAllowingIdleSystemSleep` and
`latencyCritical`. Queue priority alone does not prevent process-level App Nap.
The activity starts on input delivery, before waiting for the next timer tick.
Idle time is not integrated into the first movement after the activity starts.

Returning to neutral, disabling input, losing Accessibility access,
disconnecting, suspending motion, and stopping the loop release the activity.
Idle/dead-zone input does not acquire it, and neither display nor system sleep
is blocked. User speed, smoothing, acceleration and shortcut settings are not
changed by this policy.

Apple reference: [Prioritize Work at the App Level](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/PrioritizeWorkAtTheAppLevel.html).

## Inspect a reported stutter

Run this while moving the physical stick continuously for several seconds:

```sh
log stream --style compact --level info \
  --predicate 'subsystem == "com.vibe-controller.app" AND category == "MotionTiming"'
```

While movement continues, a summary is emitted about every two seconds:

- Average output frequency (target approximately 120 Hz).
- Longest output interval in milliseconds (target approximately 8.3 ms).
- Number of intervals longer than 25 ms.

These statistics exclude idle gaps and contain no key presses, app names or
screen contents. They measure submission to the pointer output path, not
display refresh, final driver delivery, Universal Control network latency, or
remote rendering. Healthy app timing alone does not prove the pointer feels
smooth. Compare the lead Mac and remote Mac, and compare a physical trackpad,
before blaming the network or changing Universal Control settings.

`CursorMotionLoopTests` exercise the real timer with a recording output instead
of the HID helper. They emit no system mouse events and check sustained motion
without UI turns, activity lifetime, both sticks, the dead zone, and clean stop
conditions. `CursorMotionActivityTests` check balanced assertions and cadence
aggregation. These tests do not simulate macOS's App Nap heuristics.
