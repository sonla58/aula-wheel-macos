<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/keyboard-dark.svg">
    <img alt="AULA F75 keyboard with its volume knob highlighted" src="docs/images/keyboard-light.svg" width="760">
  </picture>
</p>

# AulaWheel

Turn the volume knob of the **AULA F75** into a scroll wheel, a media scrubber and a volume dial on macOS.

<p align="center"><img alt="AulaWheel HUD: mode picker and mode banners" src="docs/images/hud.svg" width="760"></p>

## What it does

| Mode | Rotate | Press |
|---|---|---|
| **Volume** | Volume up / down (⌥ fine steps) | Mute |
| **Scroll** | Scroll the window under the pointer (⇧ horizontal, ⌥ slow, ⌘ zoom) | Change speed: slow / medium / fast |
| **Media** | Seek in the focused player (⇧ 3× further) | Play / pause |

- **Double press** opens the mode picker. Rotate to choose a mode, then press.
- **Long press** still switches the knob between Volume and RGB, as on the keyboard itself.
- A small HUD below the menu bar shows each change.
- **F10, F11 and F12** keep working as mute and volume keys.

## Install

```sh
git clone https://github.com/sonla58/aula-wheel-macos.git
cd aula-wheel-macos
scripts/build-app.sh --install
```

On first launch a setup window walks you through allowing **Accessibility** and **Input Monitoring** (a small guide sits next to System Settings and shows what to turn on), connecting the keyboard, and trying each knob gesture. Reopen it any time with **Setup Guide…** in the menu bar.

Requires macOS 14 or later (the Liquid Glass HUD needs macOS 26) and Xcode 16 or later.

## Customize

Choose **Open Config File** in the menu bar. The file is `~/Library/Application Support/AulaWheel/config.json`, and it reloads when you save it. You can change any mode, gesture, modifier binding, scroll speed or timing there.

## Limitations

- Only tested over Bluetooth. The 2.4 GHz dongle and a cable are untested.
- While the knob is in RGB mode, the keyboard handles it itself and AulaWheel can't use it.
- A very quick F11 or F12 tap right after turning the knob may be read as the knob.
- There is no LED or lighting-profile control yet.
- If the app crashes, the knob and F10–F12 do nothing until you reopen it or reconnect the keyboard.

## License

[MIT](LICENSE). Not affiliated with AULA.
