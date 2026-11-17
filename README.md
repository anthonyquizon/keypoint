# Keypoint

Keyboard-driven mouse clicks for macOS. Tap **⌘** and a grid shaped like your keyboard
appears over the screen; pick a spot with a few key presses and Keypoint clicks there.

## How it works

The screen is split into a 10×4 grid matching the physical keys:

```
1 2 3 4 5 6 7 8 9 0
Q W E R T Y U I O P
A S D F G H J K L ;
Z X C V B N M , . /
```

Each level takes **two key presses**:

- **Two different keys** → zoom into the box between their centres (e.g. `A` then `L`).
- **The same key twice** → zoom into that key's cell (e.g. `F` then `F`).

The grid then redraws inside the selected box. On the last level (2 by default), the
second press **clicks** — at the midpoint between the two keys.

If you select a wide box (e.g. `A` + `L`), its grid cells would be much bigger than
normal, so an extra level is added automatically to keep the click precise. The hint
bar shows whether the next pair *zooms* or *clicks*.

If a selection is so small its cells couldn't fit their labels, the grid grows around it
(to an 18pt minimum cell) and the cursor stays on what you selected.

| Key | Action |
|---|---|
| tap `⌘` | show / hide the grid |
| double-tap `⌘` | click where the mouse already is (hold `⇧` to right-click) |
| triple-tap `⌘` | double-click there (selects a word) — a 4th tap makes it a triple-click |
| hold `⇧` on any press | right-click instead of left-click |
| a key, then tap `⌘` | click the centre of that key's cell (e.g. `E` `⌘` instead of `E` `E`) |
| a key, then an arrow | that half of the key's cell (e.g. `E` `↑` = top half of `E`): clicks its centre on the last level, zooms into it before that |
| `Space` / `Return` | click now at the current box (or pending key) |
| `⌫` | undo the pending key, or go back a level |
| `Esc` | cancel |

Keys are matched by physical position, so the grid works the same on Dvorak, Colemak,
etc. Only keyboard events are intercepted — mouse, trackpad and tablet input pass through
untouched.

## Build & run

Requires macOS 13+ and the Xcode command-line tools.

```sh
./build.sh run
```

On first launch, grant **Accessibility** access in System Settings → Privacy & Security →
Accessibility. The menu bar icon shows *"Active — tap ⌘ to show grid"* once it's ready.

### Keeping the permission across rebuilds

Ad-hoc signed builds lose the Accessibility grant every rebuild (`build.sh` resets it so
you get a fresh prompt). To avoid this, create a self-signed certificate once in
Keychain Access (Certificate Assistant → Create a Certificate → type **Code Signing**)
named **Keypoint Dev** — `build.sh` uses it automatically when it's in your keychain.

To sign with a different certificate, or force ad-hoc signing:

```sh
CODESIGN_ID="<certificate name>" ./build.sh run
CODESIGN_ID=- ./build.sh run
```

### Tests

```sh
./build.sh test
```

Runs the grid maths tests in `Tests/` (plain assertions compiled with `swiftc`; no Xcode
project needed).

## Settings

```sh
defaults write local.keypoint levels -int 2   # levels for a normal click (default 2)
```

Takes effect the next time the grid opens.

## Project layout

- `Sources/KeyLayout.swift` — grid keys and key codes
- `Sources/KeyTap.swift` — global key hook (⌘-tap detection, swallowing keys while active)
- `Sources/Grid.swift` — grid maths: cells, click-vs-zoom, minimum cell size, arrow halves
- `Sources/Overlay.swift` — selection logic, clicking, drawing the grid
- `Sources/main.swift` — menu bar item and permission handling
- `Tests/GridTests.swift` — tests for `Grid` (`./build.sh test`)
- `build.sh` — compiles and signs `build/Keypoint.app`, or runs the tests

## License

MIT — see [LICENSE](LICENSE).
