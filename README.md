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

Press a key to **click** the centre of its cell (e.g. `F`).

For more precision, press **`⇧` + arrows first**: each one halves the next key's cell again,
in order (`⇧↑` `E` = top half of `E`, `⇧↑` `⇧←` `E` = its top-left quarter, `⇧↑` `⇧↑` `E` =
top quarter, `⇧↑` `⇧↓` `E` = the second quarter from the top). Up to four per axis (a
sixteenth); `⌫` undoes the last one.

**Plain arrows move things.** On an axis you've halved, an arrow moves the shaded slot one
slot that way within the cell: `⇧↑` `⇧↑` (top quarter) then `↓` is the 2nd quarter. On an axis
you haven't, it slides the whole grid half a cell that way, wrapping around: what goes off one
side comes back in on the other, so you can keep going. A cell split across the edge is picked
by its bigger piece (on a tie, the piece on the key's own side). Sliding leaves the mouse alone.

Want to drill down instead? `defaults write local.keypoint levels -int 2` makes the first key
zoom into its cell and the second click. There, a plain arrow slides the zoomed box one of its
cells that way (stopping at the screen edge), and if the `⇧` + arrows make a pick small enough
(40pt or less either way — `defaults write local.keypoint clickSize -float 80`), the key clicks
at once instead of zooming. The hint bar shows whether the next key *zooms* or *clicks*.

To **highlight** (or drag anything), tap `⌃` while the grid is up (or hold it on any press). Your next pick marks
the start instead of clicking; the grid resets to the whole screen, you pick the end, and
Keypoint drags from one to the other — so it also works for drag-and-drop, box-select and
sliders. `⌫` from the top of the end pick goes back to picking the start.

If a selection is so small its cells couldn't fit their labels, the grid grows around it
(to an 18pt minimum cell) and the cursor stays on what you selected.

`Tab` cycles the button: left → right → middle → left. `⌃` highlight works by holding it on
any press or tapping it on its own (tap again for left-click), and holding `⌥` on a press
middle-clicks. Whichever you use last overrides the current mode. Leaving highlight drops a
picked start.

| Key | Action |
|---|---|
| tap `⌘` | show the grid |
| tap `⌘` again | click where the mouse already is — so double-tap `⌘` clicks without moving it (with the `Tab`-chosen button; hold `⌥` to middle-click) |
| triple-tap `⌘` | double-click there (selects a word) — a 4th tap makes it a triple-click |
| `Tab` | cycle the button: left → right → middle → left |
| hold `⌥` on any press | middle-click instead of left-click (e.g. open a link in a new tab) |
| arrow | move the shaded slot one slot that way (`⇧↑` `⇧↑` `↓` = 2nd quarter); on an axis not halved, slide the grid half a cell that way, wrapping |
| tap `⌃` | highlight mode: pick a start, then an end, and Keypoint drags between them (tap again to turn off) |
| hold `⌃` on any press | turn highlight mode on from that press (e.g. `⌃F` `J` sets the start) |
| a key | click its cell's centre (with `levels` 2 or more, zoom into it until the last level) |
| `⇧` + arrows, then a key | each halves the key's cell again, in order: `⇧↑` `E` = top half, `⇧↑` `⇧←` `E` = top-left quarter, `⇧↑` `⇧↓` `E` = 2nd quarter from the top (up to a sixteenth per axis) |
| `Space` | middle-click now at the centre of the current box |
| `Return` | right-click now at the centre of the current box |
| `⌫` | undo the last `⇧` + arrow, or go back a level |
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
defaults write local.keypoint levels -int 2   # key presses per click (default 1: arrows narrow, a key clicks)
defaults write local.keypoint highlightNudge -float 4   # points each highlight end moves outward
```

Takes effect the next time the grid opens. Highlights widen each end by `highlightNudge`
(about half a character) so the characters under the start and end are included; raise it
for large text, or set it to 0 for exact points.

## Project layout

- `Sources/KeyLayout.swift` — grid keys and key codes
- `Sources/KeyTap.swift` — global key hook (⌘ / ⌃ tap detection, swallowing keys while active)
- `Sources/Grid.swift` — grid maths: cells, minimum cell size, arrow halves
- `Sources/Overlay.swift` — selection logic, clicking, drawing the grid
- `Sources/main.swift` — menu bar item and permission handling
- `Tests/GridTests.swift` — tests for `Grid` (`./build.sh test`)
- `build.sh` — compiles and signs `build/Keypoint.app`, or runs the tests

## License

MIT — see [LICENSE](LICENSE).
