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

    /// The scroll anchor (view coordinates), set with ⌥ + a key. While it's set,
    /// each key scrolls by how far that key is from it.
    private var scrollAnchor: CGPoint?

    /// Number of key presses (levels) before the click fires.
    /// Change with:  defaults write local.keypoint levels -int 3
    var maxLevels: Int {
        let v = UserDefaults.standard.integer(forKey: "levels")
        return v > 0 ? v : 2
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

    /// A key's cell at most this many points either way clicks at once
    /// instead of zooming (e.g. with `levels` set to 3).
    /// Change with:  defaults write local.keypoint clickSize -float 80
    var clickSize: CGFloat {
        let v = UserDefaults.standard.object(forKey: "clickSize") as? Double
        return CGFloat(v ?? 40)
    }

    /// Fraction of a cell an arrow shifts the grid; ⇧ + arrow shifts four times as
    /// far (half a cell by default).
    /// Change with:  defaults write local.keypoint shiftStep -float 0.125
    var shiftStep: CGFloat {
        let v = UserDefaults.standard.object(forKey: "shiftStep") as? Double
        return CGFloat(v ?? 0.125)
    }

    /// The next key clicks: the last level, or its cell is small enough.
    /// (Cells are all the same size, so any one tells.)
    private var nextKeyClicks: Bool {
        isFinalLevel || Grid.isClickSize(grid.cell(row: 0, col: 0), size: clickSize)
    }

    /// Button a click would use now: the Tab-chosen one (left for a highlight).
    var currentButton: Mouse.Button { choice.current(held: held).button }

    /// Modifiers held right now, from the last flags-changed event.
    private var held: CGEventFlags = []

    /// Click right now at the centre of the current region (or set / finish a
    /// highlight). `button` overrides the chosen one.
    func clickNow(button: Mouse.Button? = nil) {
        guard isActive else { return }
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
        choice = ModeChoice()
        held = CGEventSource.flagsState(.combinedSessionState)
        dragStart = nil
        scrollAnchor = nil
        refresh()

        win.orderFrontRegardless()
        isActive = true
    }

    func cancel() {
        choice = ModeChoice()
        dragStart = nil
        scrollAnchor = nil
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

    func handleKey(_ code: CGKeyCode, flags: CGEventFlags) {
        // ⌃ held on a press switches to highlight, overriding the current mode.
        choice.keyPressed(flags: flags)
        modeChanged()

        switch code {
        case KeyLayout.escape:
            cancel()
        case KeyLayout.delete:
            if scrollAnchor != nil {
                // Drop the scroll anchor.
                scrollAnchor = nil
                refresh()
            } else if grid.offset != .zero {
                // Put the shifted keys back.
                grid = grid.unshifted
                refresh()
            } else if let prev = history.popLast() {
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
        case _ where KeyLayout.arrows[code] != nil:
            // Arrows shift the grid a step that way (⇧: four steps). It wraps: keys
            // pushed past one edge come back on the other.
            guard let dir = KeyLayout.arrows[code] else { return }
            let steps: CGFloat = flags.contains(.maskShift) ? 4 : 1
            grid = grid.shifted(dir, by: shiftStep * steps)
            refresh()
        default:
            guard let pos = KeyLayout.position(of: code) else {
                NSSound.beep()
                return
            }
            let cell = grid.cell(row: pos.row, col: pos.col)
            let centre = CGPoint(x: cell.midX, y: cell.midY)
            switch KeyAction(flags: flags, clicks: nextKeyClicks, anchored: scrollAnchor != nil) {
            case .zoom:
                enter(Grid(rect: cell))
            case .click:
                // ⌘ + key (or any key on the last level): click its centre without zooming in.
                enter(Grid(rect: cell), now: true)
            case .anchor:
                setAnchor(centre)
            case .scroll:
                scroll(toward: centre)
            case .move:
                // ⇧ + key: just move the mouse to its centre (tap ⌘ to click there).
                grid.focus = centre
                moveCursor(to: global(centre))
                refresh()
            }
        }
    }

    /// ⌥ + key: set the scroll anchor there (or move it). ⌥ + the anchor's own key drops it.
    private func setAnchor(_ point: CGPoint) {
        scrollAnchor = Scroll.anchor(scrollAnchor, pressedAt: point)
        refresh()
    }

    /// A key while anchored: scroll the view under the anchor from it toward `point`, by
    /// as far (what was at `point` ends up at the anchor). The anchor stays, so every
    /// key scrolls again; the anchor's own key does nothing.
    private func scroll(toward point: CGPoint) {
        guard let anchor = scrollAnchor, let delta = Scroll.delta(from: anchor, to: point) else { return }
        Mouse.scroll(at: global(anchor), by: delta)
    }

    /// Move to `next`: click at its focus on the last level (or `now`), otherwise zoom into it.
    private func enter(_ next: Grid, now: Bool = false) {
        let clicks = now || isFinalLevel || Grid.isClickSize(next.rect, size: clickSize)
        history.append(grid)
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

    /// Redraw. A ⌃ held right now shows highlight over the chosen mode, and ⌘ / ⌥ / ⇧
    /// what the next key does.
    private func refresh() {
        view.grid = grid
        view.level = history.count
        view.next = KeyAction(flags: held, clicks: nextKeyClicks, anchored: scrollAnchor != nil)
        let shown = choice.current(held: held)
        view.button = shown.button
        view.dragMode = shown == .highlight
        view.dragStart = dragStart
        view.scrollAnchor = scrollAnchor
        view.needsDisplay = true
    }

    private func finish(button override: Mouse.Button? = nil) {
        if dragMode {
            guard let start = dragStart else {
                // Start picked: begin again from the whole screen to pick the end.
                dragStart = grid.focus
                grid = Grid(rect: view.bounds)
                history = []
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

    /// Scroll whatever is under `p` by `delta` points, the way the view moves (y down:
    /// a positive dy shows what's further down). Sent as a run of small steps, like a swipe.
    static func scroll(at p: CGPoint, by delta: CGVector) {
        move(to: p)
        for (i, wheel) in Scroll.wheelSteps(delta, count: 10).enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i + 1) * 0.01) {
                let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                wheel1: wheel.wheel1, wheel2: wheel.wheel2, wheel3: 0)
                // Clear modifiers so the ⌥ still held doesn't change how the app scrolls.
                e?.flags = []
                e?.location = p
                e?.post(tap: .cghidEventTap)
            }
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
    var next = KeyAction.zoom
    var button = Mouse.Button.left
    var dragMode = false
    var dragStart: CGPoint?
    var scrollAnchor: CGPoint?

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
        // Scrolling: hide the grid so you can see what scrolls. Its keys still work.
        if let p = scrollAnchor {
            drawMark(at: p, color: .systemOrange)
            drawBar("SCROLL · \(stage) · ⌥ key move the anchor · ⌘ key click · ⌫ stop · esc cancel")
            return
        }

        let region = grid.rect

        // Dim everything outside the active region.
        let outside = NSBezierPath(rect: bounds)
        outside.appendRect(region)
        outside.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(level == 0 ? 0.0 : 0.45).setFill()
        outside.fill()

        NSColor.black.withAlphaComponent(0.18).setFill()
        region.fill()

        // The keys, clipped to the region: a key shifted over one edge shows on the other.
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: region).addClip()

        // Home row tint (A S D F … ;) so you can orient quickly.
        NSColor.systemBlue.withAlphaComponent(0.10).setFill()
        let home = grid.cell(row: KeyLayout.homeRow, col: 0)
        for band in grid.tiles(of: CGRect(x: region.minX, y: home.minY, width: region.width, height: home.height)) {
            band.fill()
        }

        // Grid lines.
        let lines = NSBezierPath()
        for x in grid.columnLines {
            lines.move(to: CGPoint(x: x, y: region.minY))
            lines.line(to: CGPoint(x: x, y: region.maxY))
        }
        for y in grid.rowLines {
            lines.move(to: CGPoint(x: region.minX, y: y))
            lines.line(to: CGPoint(x: region.maxX, y: y))
        }
        lines.lineWidth = 1
        NSColor.white.withAlphaComponent(0.35).setStroke()
        lines.stroke()

        // Key labels.
        let pill = (modeTint ?? .black).withAlphaComponent(0.6)

        for (r, row) in KeyLayout.rows.enumerated() {
            for (c, key) in row.enumerated() {
                let cell = grid.cell(row: r, col: c)
                let fontSize = max(8, min(42, min(cell.width, cell.height) * 0.4))
                let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
                let text = NSAttributedString(string: key.label, attributes: attrs)
                let size = text.size()
                let pad = max(2, fontSize * 0.25)
                for tile in grid.tiles(of: cell) {
                    let box = CGRect(x: tile.midX - size.width / 2 - pad,
                                     y: tile.midY - size.height / 2 - pad / 2,
                                     width: size.width + pad * 2,
                                     height: size.height + pad)
                    pill.setFill()
                    NSBezierPath(roundedRect: box, xRadius: pad, yRadius: pad).fill()
                    text.draw(at: CGPoint(x: box.minX + pad, y: box.minY + pad / 2))
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        // Region border.
        let border = NSBezierPath(rect: region.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = level == 0 ? 0 : 2
        accent.setStroke()
        if level > 0 { border.stroke() }

        // Highlight start, once picked, and the scroll anchor, once set.
        if let p = dragStart { drawMark(at: p, color: .systemGreen) }
        if let p = scrollAnchor { drawMark(at: p, color: .systemOrange) }

        drawHint()
    }

    private func drawMark(at p: CGPoint, color: NSColor) {
        let ring = NSBezierPath(ovalIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18))
        ring.lineWidth = 3
        NSColor.white.setStroke()
        ring.stroke()
        color.setFill()
        NSBezierPath(ovalIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)).fill()
    }

    /// What the next key does, for the hint bar.
    private var stage: String {
        let action = !dragMode ? "clicks" : dragStart == nil ? "sets start" : "highlights"
        return switch next {
        case .zoom: "next key zooms"
        case .click: "next key \(action)"
        case .anchor: scrollAnchor == nil ? "next key sets the scroll anchor" : "next key moves the anchor"
        case .scroll: "next key scrolls from the anchor toward it"
        case .move: "next key moves the mouse"
        }
    }

    private func drawHint() {
        let mode = dragMode ? (dragStart == nil ? "HIGHLIGHT · pick start" : "HIGHLIGHT · pick end")
            : button == .right ? "RIGHT CLICK" : button == .middle ? "MIDDLE CLICK" : "left click"
        drawBar("Level \(level + 1) · \(stage) · \(mode) · key = its cell · ⌘ key click it now · ⇧ key move the mouse there · ⌥ key scroll anchor, then keys scroll toward them · arrows shift the grid (⇧ further) · ⇥ cycle right / middle / left · ⌃ highlight (hold or tap) · tap ⌘ click here · space middle · ⏎ right · ⌫ back · esc cancel")
    }

    /// The hint bar along the bottom of the screen.
    private func drawBar(_ s: String) {
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
