import AppKit
import CoreGraphics

/// Owns the overlay window and the selection state machine.
final class OverlayController {
    private(set) var isActive = false

    private var window: NSWindow?
    private let view = GridView()
    private var screen: NSScreen?

    /// Current grid; its rect is the region in view coordinates (top-left origin).
    private var grid = Grid(rect: .zero)
    private var region: CGRect { grid.rect }
    private var history: [Grid] = []
    /// Mode chosen so far this pick (Tab cycles right / middle; ⌃ highlight).
    private var choice = ModeChoice()

    /// Highlight mode (tap ⌃, or hold it on a press): the first pick sets where a drag starts, the
    /// second where it ends, then Keypoint drags between them.
    private var dragMode: Bool { choice.mode == .highlight }
    /// Where the drag starts (view coordinates), once picked.
    private var dragStart: CGPoint?

    /// Number of key presses (levels) before the click fires.
    /// 1 (the default) = no drilling down: arrows narrow the pick, a key clicks.
    /// Change with:  defaults write local.keypoint levels -int 2
    var maxLevels: Int {
        let v = UserDefaults.standard.integer(forKey: "levels")
        return v > 0 ? v : 1
    }

    /// How far (points) each end of a highlight moves outward so the characters
    /// under the start and end are included. About half a character.
    /// Change with:  defaults write local.keypoint highlightNudge -float 4
    var highlightNudge: CGFloat {
        let v = UserDefaults.standard.object(forKey: "highlightNudge") as? Double
        return CGFloat(v ?? 4)
    }

    /// Smallest grid cell (points): enough for the smallest key label (8pt
    /// with its pill). Grids that would be finer grow to this instead.
    private let minCellSize = CGSize(width: 18, height: 18)

    /// The next key press clicks rather than zooming.
    private var isFinalLevel: Bool { history.count + 1 >= maxLevels }

    /// A key's selection at most this many points either way clicks at once
    /// instead of zooming (so a few arrows can finish a pick early).
    /// Change with:  defaults write local.keypoint clickSize -float 80
    var clickSize: CGFloat {
        let v = UserDefaults.standard.object(forKey: "clickSize") as? Double
        return CGFloat(v ?? 40)
    }

    /// The next key clicks: the last level, or its cells are small enough.
    /// (Cells are all the same size before wrapping, so any one tells.)
    private var nextKeyClicks: Bool {
        isFinalLevel || Grid.isClickSize(grid.virtualCell(row: 0, col: 0), size: clickSize)
    }

    /// Button a click would use now: the Tab-chosen one, or middle with ⌥ held.
    var currentButton: Mouse.Button { choice.current(held: held).button }

    /// Modifiers held right now, from the last flags-changed event.
    private var held: CGEventFlags = []

    /// Click right now at the centre of the current region (or set / finish a
    /// highlight). `button` overrides the chosen one.
    func clickNow(button: Mouse.Button? = nil) {
        guard isActive else { return }
        clearMoves()
        finish(button: button)
    }

    /// Hide the overlay and click wherever the cursor currently is.
    func clickAtMouse(button: Mouse.Button) {
        cancel()
        guard let point = CGEvent(source: nil)?.location else { return }
        lastClick = (point, button, 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            Mouse.click(at: point, button: button)
        }
    }

    /// Last click made by `clickAtMouse`, so further ⌘ taps can turn it into a
    /// double- or triple-click.
    private var lastClick: (point: CGPoint, button: Mouse.Button, count: Int)?

    /// Click again at the last spot as the next click of a multi-click
    /// (2 = double-click, 3 = triple-click). Returns false if there's nothing
    /// to repeat (no previous click, it wasn't a left-click, or already triple).
    func repeatLastClick() -> Bool {
        guard let last = lastClick, last.button == .left, last.count < 3 else { return false }
        let count = last.count + 1
        lastClick = (last.point, .left, count)
        Mouse.click(at: last.point, button: .left, count: count)
        return true
    }

    func show() {
        let mouse = NSEvent.mouseLocation
        guard let scr = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.main else { return }
        screen = scr

        let win = window ?? makeWindow()
        win.setFrame(scr.frame, display: false)
        view.frame = CGRect(origin: .zero, size: scr.frame.size)

        grid = Grid(rect: view.bounds)
        history = []
        clearMoves()
        choice = ModeChoice()
        held = CGEventSource.flagsState(.combinedSessionState)
        dragStart = nil
        refresh()

        win.orderFrontRegardless()
        isActive = true
    }

    func cancel() {
        clearMoves()
        choice = ModeChoice()
        dragStart = nil
        guard isActive else { return }
        isActive = false
        window?.orderOut(nil)
    }

    func modifiersChanged(_ flags: CGEventFlags) {
        held = flags
        refresh()
    }

    /// A lone tap of ⌃: switch to its mode, or back to left-click if it's already on.
    func modeTapped(_ mode: ClickMode) {
        guard isActive else { return }
        choice.tapped(mode)
        modeChanged()
        refresh()
    }

    /// Leaving highlight mode drops a picked start.
    private func modeChanged() {
        if !dragMode { dragStart = nil }
    }

    /// Grids before each slide or zoom on this level, so ⌫ undoes them.
    private var moves: [Grid] = []

    /// Smallest cell `+` zooms in to: about the smallest label that fits.
    private let minZoomCell = CGSize(width: 12, height: 12)

    func handleKey(_ code: CGKeyCode, flags: CGEventFlags) {
        // ⌃ / ⌥ held on a press switches to its mode, overriding the current one.
        choice.keyPressed(flags: flags)
        modeChanged()

        switch code {
        case KeyLayout.escape:
            clearMoves()
            cancel()
        case KeyLayout.delete:
            if let prev = moves.popLast() {
                // Undo the last slide or zoom.
                grid = prev
                if !history.isEmpty { moveCursor(to: global(grid.focus)) }
                refresh()
                return
            }
            if let prev = history.popLast() {
                clearMoves()
                grid = prev
                moveCursor(to: global(grid.focus))
                refresh()
            } else if let start = dragStart {
                // Back from picking the end to picking the start.
                dragStart = nil
                moveCursor(to: global(start))
                refresh()
            } else {
                cancel()
            }
        case KeyLayout.space:
            // Middle-click right now at the centre of the current region.
            clickNow(button: .middle)
        case KeyLayout.returnKey:
            // Right-click right now at the centre of the current region.
            clickNow(button: .right)
        case KeyLayout.tab:
            // Cycle the button: left → right → middle → left.
            choice.cycle()
            modeChanged()
            refresh()
        case _ where KeyLayout.zoomIn.contains(code) || KeyLayout.zoomOut.contains(code):
            // + / −: make the cells smaller or bigger, a step at a time. The grid keeps
            // wrapping: zoomed in, the 40 cells are a box that slides round the screen;
            // zoomed out past the screen, cells off its edges slide into view. ⌫ undoes a zoom.
            let factor: CGFloat = KeyLayout.zoomIn.contains(code) ? 0.8 : 1.25
            guard let next = grid.zoomed(by: factor, minCell: minZoomCell) else {
                NSSound.beep()   // as far as it goes
                return
            }
            moves.append(grid)
            grid = next
            if !history.isEmpty { moveCursor(to: global(grid.focus)) }
            refresh()
        case _ where KeyLayout.arrows[code] != nil:
            // An arrow slides the grid that way; ⇧ + arrow slides it a quarter as far,
            // to line a cell's centre up with the target. Along an axis where the grid
            // spans the screen its cells slide (half a cell, ⇧ an eighth), wrapping:
            // what goes off one side comes in on the other. Along one it doesn't (zoomed
            // in), the box moves (a cell, ⇧ a quarter), stopping at the screen edge.
            guard let dir = KeyLayout.arrows[code] else { return }
            let fine = flags.contains(.maskShift)
            let top = history.isEmpty
            let spans = dir.isVertical ? grid.rect.height >= view.bounds.height - 0.5
                                       : grid.rect.width >= view.bounds.width - 0.5
            // Steps follow the zoom: half a cell, ⇧ an eighth, of the cells as they are now.
            let cells = grid.cellSize, part: CGFloat = fine ? 8 : 2
            let step = CGSize(width: cells.width / part, height: cells.height / part)
            guard let next = spans ? grid.slid(toward: dir, by: step)
                                   : grid.shifted(toward: dir, within: view.bounds, fraction: fine ? 0.25 : 1) else {
                NSSound.beep()   // already at that edge
                return
            }
            moves.append(grid)
            grid = next
            if !top { moveCursor(to: global(grid.focus)) }   // the top level leaves the mouse alone
            refresh()
        default:
            guard let pos = KeyLayout.position(of: code) else {
                NSSound.beep()
                return
            }
            if flags.contains(.maskShift) {
                // ⇧ + a key: zoom in a step, keeping that key's cell where it is.
                guard grid.cell(row: pos.row, col: pos.col) != nil,
                      let next = grid.zoomed(by: 0.8, minCell: minZoomCell, around: (pos.row, pos.col)) else {
                    NSSound.beep()   // out of view, or as far in as it goes
                    return
                }
                moves.append(grid)
                grid = next
                if !history.isEmpty { moveCursor(to: global(grid.focus)) }
                refresh()
                return
            }
            guard let cell = grid.cell(row: pos.row, col: pos.col) else {
                NSSound.beep()   // that key's cell is out of view (zoomed out past the screen)
                return
            }
            enter(Grid(rect: cell))
        }
    }

    private func clearMoves() {
        moves = []
    }

    /// Move to `next`: click at its focus on the last level, otherwise zoom into it.
    private func enter(_ next: Grid) {
        let clicks = isFinalLevel || Grid.isClickSize(next.rect, size: clickSize)
        history.append(grid)
        clearMoves()   // each level's ⌫ undoes its own slides
        grid = next

        if clicks {
            finish()
        } else {
            // Too small to label every cell? Grow it (around the selection) until it isn't.
            grid = grid.legible(minCell: minCellSize, within: view.bounds)
            moveCursor(to: global(grid.focus))
            refresh()
        }
    }

    // MARK: - Private

    /// Redraw. A ⌃ / ⌥ held right now shows its mode over the chosen one.
    private func refresh() {
        view.grid = grid
        view.level = history.count
        view.isFinal = nextKeyClicks
        let shown = choice.current(held: held)
        view.button = shown.button
        view.dragMode = shown == .highlight
        view.dragStart = dragStart
        view.needsDisplay = true
    }

    private func finish(button override: Mouse.Button? = nil) {
        if dragMode {
            guard let start = dragStart else {
                // Start picked: begin again from the whole screen to pick the end.
                dragStart = grid.focus
                grid = Grid(rect: view.bounds)
                history = []
                clearMoves()
                refresh()
                return
            }
            let (from, to) = Grid.inclusiveDrag(from: global(start), to: global(grid.focus),
                                                nudge: highlightNudge)
            cancel()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                Mouse.drag(from: from, to: to)
            }
            return
        }
        let point = global(grid.focus)
        let button = override ?? choice.mode.button
        cancel()
        // Let the overlay disappear and the tap callback return before clicking.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            Mouse.click(at: point, button: button)
        }
    }

    private func moveCursor(to point: CGPoint) {
        Mouse.move(to: point)
    }

    /// A view-space point, converted to global CG (top-left) coordinates.
    private func global(_ p: CGPoint) -> CGPoint {
        guard let screen, let primary = NSScreen.screens.first else { return .zero }
        let f = screen.frame
        let topInGlobal = primary.frame.height - f.maxY
        return CGPoint(x: f.minX + p.x, y: topInGlobal + p.y)
    }

    private func makeWindow() -> NSWindow {
        let win = NSWindow(contentRect: .zero, styleMask: .borderless,
                           backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        win.ignoresMouseEvents = true
        win.level = .screenSaver
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        win.contentView = view
        window = win
        return win
    }
}

enum Mouse {
    typealias Button = MouseButton

    /// Source for our synthetic events. With a nil source macOS suppresses
    /// real pointer input (e.g. a Wacom pen) for ~0.25s after each posted
    /// event, so the pen feels captured; this source suppresses nothing.
    private static let source: CGEventSource? = {
        let s = CGEventSource(stateID: .combinedSessionState)
        s?.localEventsSuppressionInterval = 0
        s?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval)
        s?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateRemoteMouseDrag)
        return s
    }()

    static func move(to p: CGPoint) {
        let e = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                        mouseCursorPosition: p, mouseButton: .left)
        e?.flags = []
        e?.post(tap: .cghidEventTap)
    }

    /// `count` is the click number within a multi-click (1 = single,
    /// 2 = second click of a double-click, 3 = triple-click).
    static func click(at p: CGPoint, button: Button, count: Int = 1) {
        move(to: p)
        let (downType, upType, cgButton): (CGEventType, CGEventType, CGMouseButton) = switch button {
        case .left: (.leftMouseDown, .leftMouseUp, .left)
        case .right: (.rightMouseDown, .rightMouseUp, .right)
        case .middle: (.otherMouseDown, .otherMouseUp, .center)
        }
        post(downType, at: p, button: cgButton, clickState: count)
        post(upType, at: p, button: cgButton, clickState: count)
    }

    /// Left-drag from `a` to `b`: press, a short pause, a run of drag events
    /// along the way (drag-and-drop and box-select need to see movement), release.
    static func drag(from a: CGPoint, to b: CGPoint) {
        move(to: a)
        post(.leftMouseDown, at: a, button: .left, clickState: 1)
        let steps = 20, pause = 0.05, step = 0.01
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            DispatchQueue.main.asyncAfter(deadline: .now() + pause + Double(i) * step) {
                post(.leftMouseDragged, at: p, button: .left, clickState: 1)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + pause * 2 + Double(steps) * step) {
            post(.leftMouseUp, at: b, button: .left, clickState: 1)
        }
    }

    private static func post(_ type: CGEventType, at p: CGPoint, button: CGMouseButton, clickState: Int) {
        let e = CGEvent(mouseEventSource: source, mouseType: type,
                        mouseCursorPosition: p, mouseButton: button)
        // Clear modifiers so a still-held ⇧ or ⌃ doesn't make this a shift- or ⌃-click.
        e?.flags = []
        e?.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
        e?.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.rawValue))
        e?.post(tap: .cghidEventTap)
    }
}

/// Draws the keyboard-shaped grid over the current region.
final class GridView: NSView {
    var grid = Grid(rect: .zero)
    var level = 0
    var isFinal = false
    var button = Mouse.Button.left
    var dragMode = false
    var dragStart: CGPoint?

    /// Accent for the current mode: green highlight, red right-click, purple middle, blue click.
    private var accent: NSColor {
        modeTint ?? .systemBlue
    }

    /// Tint for a non-left mode (highlight, right or middle click); nil for a plain left click.
    private var modeTint: NSColor? {
        if dragMode { return .systemGreen }
        switch button {
        case .left: return nil
        case .right: return .systemRed
        case .middle: return .systemPurple
        }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let region = grid.rect
        // The live cells: one box, or its pieces where it wraps round the edges.
        let live = grid.pieces(of: grid.box)
        let liveArea = live.reduce(0) { $0 + $1.width * $1.height }
        let whole = liveArea >= bounds.width * bounds.height - 1

        // Dim everything outside the live cells (drilled or zoomed in).
        let outside = NSBezierPath(rect: bounds)
        for piece in live { outside.appendRect(piece) }
        outside.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(whole ? 0.0 : 0.45).setFill()
        outside.fill()

        NSColor.black.withAlphaComponent(0.18).setFill()
        live.forEach { $0.fill() }

        // Home row tint (A S D F … ;) so you can orient quickly.
        NSColor.systemBlue.withAlphaComponent(0.10).setFill()
        let home = grid.virtualCell(row: KeyLayout.homeRow, col: 0)
        let box = grid.box
        for piece in grid.pieces(of: CGRect(x: box.minX, y: home.minY, width: box.width, height: home.height)) {
            piece.fill()
        }

        // Grid lines, tiled across the whole region so the grid reads as endless.
        let lines = NSBezierPath()
        for x in grid.lineXs {
            lines.move(to: CGPoint(x: x, y: region.minY))
            lines.line(to: CGPoint(x: x, y: region.maxY))
        }
        for y in grid.lineYs {
            lines.move(to: CGPoint(x: region.minX, y: y))
            lines.line(to: CGPoint(x: region.maxX, y: y))
        }
        lines.lineWidth = 1
        NSColor.white.withAlphaComponent(0.35).setStroke()
        lines.stroke()

        // Region border.
        if !whole {
            accent.setStroke()
            for piece in live {
                let border = NSBezierPath(rect: piece.insetBy(dx: 0.5, dy: 0.5))
                border.lineWidth = 2
                border.stroke()
            }
        }

        // Zoomed in: faded copies of the keyboard tiled round the live box, so the
        // grid reads as endless. Only the bright box's keys click; these just orient.
        let copies = grid.copies
        if !copies.isEmpty {
            NSGraphicsContext.saveGraphicsState()
            let notLive = NSBezierPath(rect: bounds)
            for piece in live { notLive.appendRect(piece) }
            notLive.windingRule = .evenOdd
            notLive.addClip()
            for copy in copies {
                drawLabel(KeyLayout.rows[copy.row][copy.col].label, in: copy.rect, faded: true)
            }
            NSGraphicsContext.restoreGraphicsState()
        }

        // Key labels.
        for (r, row) in KeyLayout.rows.enumerated() {
            for (c, key) in row.enumerated() {
                guard let cell = grid.cell(row: r, col: c) else { continue }
                drawLabel(key.label, in: cell, faded: false)
            }
        }

        // Highlight start, once picked.
        if let p = dragStart {
            let ring = NSBezierPath(ovalIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18))
            ring.lineWidth = 3
            NSColor.white.setStroke()
            ring.stroke()
            NSColor.systemGreen.setFill()
            NSBezierPath(ovalIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)).fill()
        }

        drawHint()
    }

    /// A key label in a pill at the centre of `cell`; `faded` for the copies round the live box.
    private func drawLabel(_ label: String, in cell: CGRect, faded: Bool) {
        let fontSize = max(8, min(42, min(cell.width, cell.height) * 0.4))
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor.white.withAlphaComponent(faded ? 0.4 : 1),
        ]
        let text = NSAttributedString(string: label, attributes: attrs)
        let size = text.size()
        let pad = max(2, fontSize * 0.25)
        let pillRect = CGRect(x: cell.midX - size.width / 2 - pad,
                              y: cell.midY - size.height / 2 - pad / 2,
                              width: size.width + pad * 2,
                              height: size.height + pad)
        (modeTint ?? .black).withAlphaComponent(faded ? 0.3 : 0.6).setFill()
        NSBezierPath(roundedRect: pillRect, xRadius: pad, yRadius: pad).fill()
        text.draw(at: CGPoint(x: pillRect.minX + pad, y: pillRect.minY + pad / 2))
    }

    private func drawHint() {
        let mode = dragMode ? (dragStart == nil ? "HIGHLIGHT · pick start" : "HIGHLIGHT · pick end")
            : button == .right ? "RIGHT CLICK" : button == .middle ? "MIDDLE CLICK" : "left click"
        let action = !dragMode ? "clicks" : dragStart == nil ? "sets start" : "highlights"
        let stage = isFinal ? "next key \(action)" : "next key zooms"
        let s = "Level \(level + 1) · \(stage) · \(mode) · key = its cell · arrows slide the grid (⇧ finer) · + − zoom · ⇧ key zoom in there · ⇥ cycle right / middle / left · ⌥ middle (hold) · ⌃ highlight (hold or tap) · ⌘ click here · space middle · ⏎ right · ⌫ back · esc cancel"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let text = NSAttributedString(string: s, attributes: attrs)
        let size = text.size()
        let box = CGRect(x: bounds.midX - size.width / 2 - 10, y: bounds.maxY - size.height - 24,
                         width: size.width + 20, height: size.height + 10)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
        text.draw(at: CGPoint(x: box.minX + 10, y: box.minY + 5))
    }
}
