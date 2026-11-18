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

Each level takes **one key press**: press a key to zoom into its cell (e.g. `F`). The
grid redraws inside that cell, and on the last level (2 by default) the press **clicks**
the cell's centre. So a normal click is two keys: `F` `J`.

For more precision, press an **arrow first**: the next key picks that half of its cell
(e.g. `↑` `E` = top half of `E`). Press the same arrow again to halve it again
(`↑` `↑` `E` = top quarter, `↑` `↑` `↑` `E` = top eighth). The hint bar shows whether the next key *zooms* or
*clicks*.

To **highlight** (or drag anything), tap `⌃` while the grid is up. Your next pick marks
the start instead of clicking; the grid resets to the whole screen, you pick the end, and
Keypoint drags from one to the other — so it also works for drag-and-drop, box-select and
sliders. `⌫` from the top of the end pick goes back to picking the start.

If a selection is so small its cells couldn't fit their labels, the grid grows around it
(to an 18pt minimum cell) and the cursor stays on what you selected.

| Key | Action |
|---|---|
| tap `⌘` | show / hide the grid |
| double-tap `⌘` | click where the mouse already is (hold `⇧` to right-click) |
| triple-tap `⌘` | double-click there (selects a word) — a 4th tap makes it a triple-click |
| hold `⇧` on any press | right-click instead of left-click |
| tap `⌃` | highlight mode: pick a start, then an end, and Keypoint drags between them (tap again to turn off) |
| a key | zoom into its cell (clicks its centre on the last level) |
| an arrow, then a key | that half of the key's cell (e.g. `↑` `E` = top half of `E`); the same arrow again halves it again (`↑` `↑` `E` = top quarter, up to an eighth); a different arrow replaces it |
| `Space` / `Return` | click now at the centre of the current box |
| `⌫` | undo the last arrow press, or go back a level |
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

### Open at login

```sh
./build.sh install
```

This builds the app, copies it to `~/Applications/Keypoint.app` and opens it from there.
Then pick **Open at Login** in the menu bar menu. Install it first: `build/` is wiped on
every rebuild, so a login item pointing there would break.

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
defaults write local.keypoint levels -int 2   # key presses per click (default 2)
defaults write local.keypoint highlightNudge -float 4   # points each highlight end moves outward
```

Takes effect the next time the grid opens. Highlights widen each end by `highlightNudge`
(about half a character) so the characters under the start and end are included; raise it
for large text, or set it to 0 for exact points.

## Project layout

- `Sources/KeyLayout.swift` — grid keys and key codes
- `Sources/KeyTap.swift` — global key hook (⌘-tap detection, swallowing keys while active)
- `Sources/Grid.swift` — grid maths: cells, minimum cell size, arrow halves
- `Sources/Overlay.swift` — selection logic, clicking, drawing the grid
- `Sources/main.swift` — menu bar item and permission handling
- `Tests/GridTests.swift` — tests for `Grid` (`./build.sh test`)
- `build.sh` — compiles and signs `build/Keypoint.app`, or runs the tests

## License

MIT — see [LICENSE](LICENSE).
