# AulaWheel

A small macOS menu bar app that turns the volume knob of the **AULA F75** keyboard into a multi-mode dial: scroll the window under the pointer, seek media, or control volume, with an on-screen HUD and a mode picker.

AULA ships no macOS software for the F75. AulaWheel works only with what the keyboard already sends over Bluetooth, so nothing is flashed to the keyboard.

> AulaWheel is an independent project. It is not affiliated with or endorsed by AULA.

## Features

| Mode | Rotate | Press |
|---|---|---|
| **Volume** | volume up / down (⌥: fine steps) | mute |
| **Scroll** | smooth-scroll the window under the pointer (⇧: horizontal, ⌥: slow, ⌘: zoom) | cycle speed: slow → medium → fast |
| **Media** | ← / → to the focused app to seek (⇧: 3×) | play / pause |

- **Double press** opens the mode picker. Rotate to move, then press to choose, or wait 1.5 s.
- **Long press** still toggles the keyboard's own Volume ↔ RGB knob mode. The HUD shows when the knob switches to driving the LEDs.
- **F10 / F11 / F12** on the keyboard keep working as mute and volume keys.
- The HUD uses Liquid Glass on macOS 26 and later. It appears just below the menu bar, on the screen that has the pointer.
- Every gesture, modifier and mode can be changed in a JSON config file, which reloads when you save it.

## Requirements

- macOS 14 or later (Liquid Glass HUD on macOS 26+).
- AULA F75 connected over **Bluetooth** (vendor ID `0x3554`, product ID `0xFA07`). With the 2.4 GHz dongle or a cable the keyboard may report another product ID; set it in the config.
- Xcode 16 or later to build.

## Install

```sh
git clone <this repository> && cd aula-wheel
scripts/build-app.sh --install
```

The script builds a release `AulaWheel.app`, signs it, copies it to `~/Applications` and launches it.

macOS ties privacy permissions to the code signature. The script signs with `SIGN_IDENTITY` if it is set, or else the first "Apple Development" certificate it finds. If there is neither, it signs ad hoc, and you will need to grant the permissions again after every build.

On first launch, open System Settings → Privacy & Security and allow AulaWheel under:

- **Accessibility**: to intercept the knob and post scroll and key events.
- **Input Monitoring**: to see the keyboard's RGB-mode signal and when the keyboard reconnects.

The menu bar icon shows a warning until both are granted. Quit and reopen the app after granting Input Monitoring.

## Configuration

`~/Library/Application Support/AulaWheel/config.json` is created with the defaults on first launch. **Open Config File** in the menu opens it. Keys you leave out keep their defaults.

Each mode is a list of bindings:

```json
{ "gesture": "rotateCW", "modifiers": ["shift"], "action": { "type": "scroll", "direction": "right" } }
```

- **Gestures:** `rotateCW`, `rotateCCW`, `press`. Double press always opens the mode picker.
- **Modifiers:** `shift`, `control`, `option`, `command`. A binding whose modifiers match exactly wins. Otherwise the binding with no modifiers is used.
- **Actions:**
  - `none`, `mute`
  - `volumeUp` / `volumeDown` (`fine`)
  - `scroll` (`direction`: `up` / `down` / `left` / `right`, `scale`)
  - `key` (`keyCode`, `modifiers`, `repeat`)
  - `mediaPlayPause`, `mediaNext`, `mediaPrevious`
  - `cycleScrollSpeed`

Other settings:

| Key | Default | Meaning |
|---|---|---|
| `scroll.slowPixels` / `mediumPixels` / `fastPixels` | 40 / 100 / 250 | Pixels per detent at each speed |
| `scroll.animationMs` | 120 | Smoothing duration per detent |
| `scroll.accelerationThresholdMs` / `accelerationFullMs` / `maxAcceleration` | 60 / 30 / 3 | Fast spins scroll up to 3× further |
| `scroll.invert` | false | Reverse scroll direction |
| `doublePressWindowMs` | 250 | Max gap between the two presses of a double press. A single press is delayed by this much. |
| `hud.displaySeconds` / `pickerAutoSelectSeconds` | 1.0 / 1.5 | HUD timing |
| `input.knobMaxHoldMs` / `knobBurstMaxHoldMs` / `knobBurstWindowMs` | 60 / 150 / 300 | Telling the knob from F10–F12 (see below) |
| `device.vendorID` / `productID` | 0x3554 / 0xFA07 | Keyboard to attach to |

## How it works

The knob is handled by the keyboard's firmware. These notes were measured on a Bluetooth F75:

- **Volume mode:**
  - Each detent sends Consumer *Volume Up* or *Volume Down* as a press/release pair about 15 ms apart.
  - A knob press sends *Mute*.
  - The long press that switches modes sends nothing.
- **RGB mode:** every knob action sends the same vendor report (ID `0x13`), with no direction information. AulaWheel therefore leaves RGB mode alone and only uses it to show the HUD.
- **F10 / F11 / F12** send exactly the same Consumer codes as the knob.

AulaWheel uses this as follows:

1. While it runs, it adds a per-device `UserKeyMapping` entry that turns those three Consumer codes into F18 / F19 / F20, **for the AULA keyboard only**. Other mappings on the keyboard are left alone, and the entries are removed on quit.
2. An event tap swallows F18 / F19 / F20 and tells the two sources apart by how long the key is held:
   - The knob releases within about 60 ms.
   - A finger holds a key longer.
   - While the knob is turning, the limit rises to 150 ms, because Bluetooth occasionally delays a release mid-spin.
   - Real F-key presses are passed on as the original volume and mute keys.
3. Knob events become gestures (rotate, press, double press), which the current mode turns into actions.

If you ever remap the knob on the keyboard itself, for example to F13–F15 with AULA's Windows software, set `"input": {"source": "functionKeys", "functionKeyCodes": {"rotateCW": 105, "rotateCCW": 107, "press": 113}}`. No remapping or timing detection is needed then.

## Limitations

- Bluetooth only, as measured. Other connection modes are untested.
- The keyboard sends the same signal when entering and leaving RGB mode. The "RGB" HUD therefore appears only after the knob has been used since the app started, and AulaWheel learns that the knob is back in Volume mode on its next use.
- A very quick tap on F11 / F12 (under 150 ms) right after turning the knob counts as a knob event.
- LED effects and profiles are not supported yet.

## Troubleshooting

**The knob or F10–F12 do nothing.** Relaunch AulaWheel, or turn the keyboard off and on. If AulaWheel crashed, its F18–F20 mapping can stay on the keyboard. As a last resort, this command clears *every* key mapping on the keyboard, including any of your own:

```sh
hidutil property --matching '{"VendorID":0x3554,"ProductID":0xFA07}' --set '{"UserKeyMapping":[]}'
```

**Wrong action, or volume changes while scrolling.** Stream the input log and reproduce the problem:

```sh
/usr/bin/log stream --level debug --predicate 'subsystem == "dev.aulawheel.AulaWheel"'
```

## Development

```
Sources/AulaWheelCore   platform-independent logic: config, classifier, gestures, modes, scrolling
Sources/AulaWheel       the app: event tap, HID monitor, key remapping, event posting, HUD, menu
Tests/                  unit tests for AulaWheelCore
```

```sh
swift test            # run the tests
swift build           # debug build of the app executable
scripts/build-app.sh  # build the signed .app into build/
```

The tests cover the core logic. Anything involving the real keyboard, event taps or permissions has to be checked by hand.

## License

[MIT](LICENSE)
