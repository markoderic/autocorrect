# Input recovery — 0.3.18

October 21, 2026. Runtime starting point: `298963b`; task starting point: `8ff983a`.

## Report and evidence

The owner reported corrections stopping across several apps while AutoCorrect remained enabled in the menu bar. Before restarting, the installed 0.3.17 process had been running since October 19. A one-second sample showed a responsive main run loop and approximately 55 MiB physical footprint. The live process's tap was enabled according to `CGGetEventTapList`; Secure Input was off, both permissions were granted, and automatic mode was enabled. These observations do **not** identify the original intermittent trigger. A separate `--diagnostics` invocation tests a new listener, not the running application's listener.

Code inspection found concrete recovery gaps: timeout notices re-enabled the tap without invalidating old typing/edit state; no periodic health check or sleep/session lifecycle recovery existed; a stored Ready status could outlive usable keyboard access. The fix covers those failure paths. It does not establish that a permanently disabled tap caused this particular report.

## Changes

- Validate the Mach port, run-loop source and enabled flag before declaring the listener running; clean up partial starts.
- Process system interruption notices before inspecting event markers. Discard old word/caret/edit evidence immediately and recreate the listener outside its callback. Delayed edit completions cannot revive obsolete Undo or block fresh words.
- Retry a disabled or unavailable listener on app activation, menu access and a five-second timer with one-second tolerance. A healthy check does not clear typing, Undo or suggestions and does not restart the listener.
- Suspend for sleep/inactive sessions and reconnect on wake/session activation. Track sleep and inactive-session state independently so one resume signal cannot override the other suspension.
- Honor the user's paused preference and denied permissions. Pause while macOS Secure Input is active, show the reason and resume after it ends. Do not change permissions or bypass Secure Input.
- Give input-access status priority over ordinary correction messages, including after focus changes.

The timer reads permission/Secure Input flags and listener state only. It does not read editor text, run spelling analysis, post test keys, store typing history or use a network service. Rechecks are coalescible and are not a hard five-second deadline while macOS schedules the app.

Apple documents [event-tap disable/re-enable notices](https://developer.apple.com/documentation/coregraphics/cgevent/tapenable(tap:enable:)) and [workspace session activation notifications](https://developer.apple.com/documentation/appkit/nsworkspace/sessiondidbecomeactivenotification). Workspace session activation is distinct from a guarantee of every screen-unlock event; the periodic check provides an additional recovery path.

## Validation

- `InputSessionTests`: 13 passing tests injecting listener loss, failed/false-success starts, repeated healthy checks, permission loss/restoration, Secure Input, pause preference, both sleep/session ordering combinations, stale enabled tap on wake, interruption and late edit completion. The real correction engine accepts fresh words after an interrupted in-flight edit and retains Undo during healthy checks.
- Full local Swift suite: 392 executed, 388 passed, four existing opt-in audit skips, zero failures on macOS 27.0.1. This includes the initial-letter/unfinished-word regression suite.
- Release-script suite: six passing tests.
- Universal arm64/x86_64 release build and strict signature validation passed. Intel execution is not tested.
- Installed 0.3.18 with the existing Apple Development identity. Rollback: `/Applications/AutoCorrect.previous-20261021-135925.app`. Installed executable SHA-256: `6e3bec5cfcec0fc70ad9452c75ed189ec58aabdf5bd1fcc3aefb0abe333a29ac`.
- Normal startup with tracing off; Settings shows Ready and both permissions Allowed. Diagnostics reports both permissions, listener creation, supported layout and login enabled. Owner replied that correction works again in response to the requested Claude/second-app test, and reported a separate `its` → `t’s` text-loss symptom plus missed `woks`/`helo` corrections. Investigate that new report separately; it is not an all-app or long-duration pass.

These deterministic fault tests do not reproduce a two-day intermittent failure or prove long-term recovery across every host. The exact original trigger and sustained wake/typing/resource behavior remain acceptance checks.

## Distribution

The public release remains the previously notarized 0.3.16. The October 21 notarization preflight still reports `No Keychain password item found for profile: AutoCorrect-notary`. No 0.3.18 Apple submission, public upload or replacement of the notarized archive occurred. The locally installed development build is separate from the public download.
