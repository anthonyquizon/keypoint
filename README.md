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

Hold a modifier to do something else with the key instead of zooming in:

- **`⌘` + key** clicks that key's centre right away, on any level.
- **`⇧` + key** just moves the mouse there; tap `⌘` to click where it is.
- **`⌃` + key** sets a scroll anchor there (an orange dot) and hides the grid, so you can
  see what scrolls. Its keys still work: from then on **any key** scrolls the view under
  the anchor toward where that key sits on the grid, by how far it is from the anchor:
  with the anchor on `Q`, `Z` scrolls down two rows' worth (what was at `Z` comes up to
  `Q`), and pressing it again scrolls as far again. `⌃` + another key moves the anchor;
  `⌫` (or `⌃` + the anchor's key) drops it and brings the grid back. `⌘` + key still clicks.

For more precision, the **arrows shift the grid** an eighth of a cell that way (`⇧` +
arrow: half a cell). The grid wraps round, so keys pushed off one edge come back on the
other, and every key still clicks its centre. Once you've zoomed in, the arrows **move the
whole box** instead: an eighth of its own size that way (`⇧`: half), keys and mouse with it,
stopping at the screen's edge — handy when what you want sits just across its border. `⌫`
puts the keys (or the box) back (`defaults write local.keypoint shiftStep -float 0.125`
sets the step; `⇧` is four steps).

A key whose cell is small enough (40pt or less either way — `defaults write local.keypoint
clickSize -float 40`) clicks its centre right away instead of zooming another level, e.g.
with `levels` set to 3. The hint bar shows whether the next key *zooms*, *clicks*, *scrolls*
or *moves the mouse*.

To **highlight** (or drag anything), tap `⌥` while the grid is up (or hold it on any press). Your next pick marks
the start instead of clicking; the grid resets to the whole screen, you pick the end, and
Keypoint drags from one to the other — so it also works for drag-and-drop, box-select and
sliders. `⌫` from the top of the end pick goes back to picking the start.

If a selection is so small its cells couldn't fit their labels, the grid grows around it
(to an 18pt minimum cell) and the cursor stays on what you selected.

`Tab` cycles the button: left → right → middle → left. `⌥` highlight works by holding it on
any press or tapping it on its own (tap again for left-click). Whichever you use last
overrides the current mode. Leaving highlight drops a picked start.

| Key | Action |
|---|---|
| tap `⌘` | show the grid |
| tap `⌘` again | click where the mouse already is — so double-tap `⌘` clicks without moving it (with the `Tab`-chosen button) |
| triple-tap `⌘` | double-click there (selects a word) — a 4th tap makes it a triple-click |
| `Tab` | cycle the button: left → right → middle → left |
| tap `⌥` | highlight mode: pick a start, then an end, and Keypoint drags between them (tap again to turn off) |
| hold `⌥` on any press | turn highlight mode on from that press (e.g. `⌥F` `J` sets the start) |
| a key | zoom into its cell (clicks its centre on the last level) |
| `⌘` + key | click that key's centre now, without zooming in |
| `⇧` + key | move the mouse to that key's centre |
| `⌃` + key | set the scroll anchor there and hide the grid; then every key scrolls from the anchor toward that key, by the distance between them |
| arrow | shift the keys an eighth of a cell that way; they wrap round the edges. Zoomed in: move the whole box an eighth of its size |
| `⇧` + arrow | shift the keys half a cell (zoomed in: move the box half its size) |
| `Space` | middle-click now at the centre of the current box |
| `Return` | right-click now at the centre of the current box |
| `⌫` | drop the scroll anchor, put shifted keys (or a moved box) back, or go back a level |
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

Runs the grid maths, key action and scroll tests in `Tests/` (plain assertions compiled with `swiftc`; no Xcode
project needed).

## Settings

```sh
defaults write local.keypoint levels -int 2   # key presses per click (default 2)
defaults write local.keypoint highlightNudge -float 4   # points each highlight end moves outward
defaults write local.keypoint shiftStep -float 0.125    # fraction of a cell an arrow shifts the keys (zoomed in: of the box it moves)
```

Takes effect the next time the grid opens. Highlights widen each end by `highlightNudge`
(about half a character) so the characters under the start and end are included; raise it
for large text, or set it to 0 for exact points.

## Project layout

- `Sources/KeyLayout.swift` — grid keys and key codes
- `Sources/KeyTap.swift` — global key hook (⌘ / ⌥ tap detection, swallowing keys while active)
- `Sources/Grid.swift` — grid maths: cells, shifting and wrapping, sliding the box, minimum cell size
- `Sources/Overlay.swift` — selection logic, clicking, drawing the grid
- `Sources/main.swift` — menu bar item and permission handling
- `Sources/Buttons.swift` — click modes, what a key press does by its modifiers, modifier taps
- `Sources/Scroll.swift` — the scroll anchor, scroll distances and wheel steps
- `Tests/` — tests for `Grid`, `Buttons` and `Scroll` (`./build.sh test`)
- `build.sh` — compiles and signs `build/Keypoint.app`, or runs the tests

## License

MIT — see [LICENSE](LICENSE).
