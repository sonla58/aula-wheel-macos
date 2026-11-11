# AulaWheel

A macOS menu-bar app that extends the AULA F75's volume knob, so the user can read, scroll and control media without leaving the keyboard.

## Product DNA

The app sits in the path of every keystroke. Trust comes before features. In order of priority:

1. **Typing is sacred.** Never add latency to, drop or change ordinary keys.
2. **Never leave the keyboard worse than it is without the app.** Any change we make to the device or the system exists only while we are actively handling it. Quitting, crashing, disabling, sleeping, reconnecting or losing a permission must all leave the keyboard working natively.
3. **When unsure, fall back to native.** A knob that only does what the keyboard does by itself is acceptable. A knob that does nothing, or does the wrong thing, is not.
4. **The keyboard's own functions keep their meaning.** One example: F10–F12 share codes with the knob, and must still control volume.
5. **Stay out of the way.** Never take focus while the user is working. A window appears only when the user asks for one, or when something needs their action, such as first-run setup or a missing permission. Defaults are opinionated, and every new option has a cost.
6. **Be honest about state.** If something doesn't work (no permission, keyboard not found, a bad setting), say so plainly and say what fixes it. Never fail silently.

Work only with what the hardware already sends. Features the firmware owns, such as its own mode switching and lighting, are observed, not taken over.

## How to reason

- **Hardware behaviour is measured, not assumed.** When something is unknown, say so and design to tolerate it. Don't fill the gap with a plausible guess.
- **Name what the tests can't prove.** Real input interception, OS permissions, posted events, wireless timing and UI cannot be proven by unit tests. They are unverified until tried on the device. Say so whenever you claim something works.
- **For any change that touches input or system state, walk every exit and failure path.** Ask what state the user is left in.
- **Time comes from the hardware's event timestamps, not from when we happen to handle the event.**

## How to code

- **Keep decision logic pure and testable** (time passed in, no OS calls), apart from the thin layer that talks to the OS. Today the logic lives in `AulaWheelCore`. Behaviour changes start with a test there.
- **The hot input path does the minimum and never waits on UI or other slow work.** Enabling and disabling must not re-enter themselves.
- **Only touch what we own:** our own entries in shared device or system settings, and only the inputs we handle.
- **User settings are forgiving to read and strict to accept.** Missing values get defaults. Invalid input never replaces a working state and is always reported.
- **Prefer the smallest change that keeps the promises above** over new options or abstraction.

`swift test` runs the core tests. `scripts/build-app.sh` builds the signed app.
