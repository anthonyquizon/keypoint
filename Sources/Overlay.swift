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
    private var shiftUsed = false

    /// Number of levels before the click fires for normal-sized selections.
    /// Change with:  defaults write local.keypoint levels -int 3
    var maxLevels: Int {
        let v = UserDefaults.standard.integer(forKey: "levels")
        return v > 0 ? v : 2
    }

    /// Lean the next grid toward the second key of a pair (A then B → small
    /// cells near B): ratio of largest to smallest cell. Off (1) by default.
    /// Try:  defaults write local.keypoint skew -float 3
    var skew: CGFloat {
        let v = UserDefaults.standard.double(forKey: "skew")
        return v > 1 ? CGFloat(v) : 1
    }

    /// How much bigger than a normal last-level cell a grid cell may be and
    /// still count as the last level.
    private let finalSlack: CGFloat = 1.5

    /// Smallest grid cell (points): enough for the smallest key label (8pt
    /// with its pill). Grids that would be finer grow to this instead.
    private let minCellSize = CGSize(width: 18, height: 18)

    /// A cell is fine enough to click in when it's no bigger than a normal
    /// last-level cell — screen ÷ (10ⁿ, 4ⁿ) for n = `maxLevels`, with
    /// `finalSlack` tolerance. Selecting a wide span (e.g. A + L), or a big
    /// cell at the coarse end of a leaning grid, fails this, so that pair
    /// zooms one more level instead of clicking.
    ///
    /// Size is compared by cell diagonal (≈ worst-case distance from the aimed
    /// point), so a wide-but-short cell can still count as precise enough.
    ///
    /// On a leaning grid the diagonal alone is too forgiving: last-level cells
    /// are tall and narrow, so a visibly wide bail-out cell can still pass. So
    /// a cell also zooms when it's clearly bigger than an even cell of this
    /// grid on some axis (`evenTolerance`) *and* bigger than a normal
    /// last-level cell on that axis — the second part stops the extra level
    /// (and anything deeper) from drilling down again.
    private func isClickable(_ cell: CGSize, in grid: Grid) -> Bool {
        grid.isClickable(cell, screen: view.bounds.size, levels: maxLevels, slack: finalSlack)
    }

    /// Some pair on this grid would click (its finest cells are small enough).
    private func isFinalLevel(_ grid: Grid) -> Bool {
        isClickable(grid.smallestCell, in: grid)
    }

    /// Every pair on this grid would click (its coarsest cells are small enough).
    private func isFullyFinal(_ grid: Grid) -> Bool {
        isClickable(grid.largestCell, in: grid)
    }

    /// A pair clicks only if both keys' cells are fine enough; otherwise it
    /// drills down another level.
    private func pairClicks(_ a: (row: Int, col: Int), _ b: (row: Int, col: Int)) -> Bool {
        isClickable(grid.cell(row: a.row, col: a.col).size, in: grid)
            && isClickable(grid.cell(row: b.row, col: b.col).size, in: grid)
    }

    func toggle() { isActive ? cancel() : show() }

    /// Overlay is open but nothing has been selected yet.
    var isPristine: Bool { isActive && history.isEmpty && pending == nil }

    /// Hide the overlay and click wherever the cursor currently is.
    func clickAtMouse(right: Bool) {
        cancel()
        guard let point = CGEvent(source: nil)?.location else { return }
        lastClick = (point, right, 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            Mouse.click(at: point, right: right)
        }
    }

    /// Last click made by `clickAtMouse`, so further ⌘ taps can turn it into a
    /// double- or triple-click.
    private var lastClick: (point: CGPoint, right: Bool, count: Int)?

    /// Click again at the last spot as the next click of a multi-click
    /// (2 = double-click, 3 = triple-click). Returns false if there's nothing
    /// to repeat (no previous click, it was a right-click, or already triple).
    func repeatLastClick() -> Bool {
        guard let last = lastClick, !last.right, last.count < 3 else { return false }
        let count = last.count + 1
        lastClick = (last.point, false, count)
        Mouse.click(at: last.point, right: false, count: count)
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
        shiftUsed = false
        refresh(shiftDown: NSEvent.modifierFlags.contains(.shift))

        win.orderFrontRegardless()
        isActive = true
    }

    func cancel() {
        clearPending()
        guard isActive else { return }
        isActive = false
        window?.orderOut(nil)
    }

    func shiftChanged(_ down: Bool) {
        refresh(shiftDown: down)
    }

    /// First key of the current pair, waiting for its partner.
    private var pending: (row: Int, col: Int)?

    func handleKey(_ code: CGKeyCode, flags: CGEventFlags) {
        let shift = flags.contains(.maskShift)
        if shift { shiftUsed = true }

        switch code {
        case KeyLayout.escape:
            clearPending()
            cancel()
        case KeyLayout.delete:
            if pending != nil { clearPending(); refresh(shiftDown: shift); return }
            if let prev = history.popLast() {
                grid = prev
                moveCursor(to: global(grid.focus))
                refresh(shiftDown: shift)
            } else {
                cancel()
            }
        case KeyLayout.space, KeyLayout.returnKey:
            // Click right now at the centre of the current region.
            // (If one key of a pair is pending, click that key's cell.)
            if let p = pending {
                clearPending()
                history.append(grid)
                grid = Grid(rect: grid.span(from: p, to: p))
            }
            finish(rightClick: shiftUsed)
        default:
            guard let pos = KeyLayout.position(of: code) else {
                NSSound.beep()
                return
            }
            if let first = pending {
                // Second key of the pair: zoom into the box between them
                // (same key twice = that key's cell).
                clearPending()
                select(from: first, to: pos, shift: shift)
            } else {
                pending = pos
                refresh(shiftDown: shift)
            }
        }
    }

    private func clearPending() {
        pending = nil
    }

    /// Zoom into the box spanning the centres of two keys (the same key twice =
    /// that key's cell). Any axis thinner than one cell is padded to one cell,
    /// centred on the line between the keys. Order matters when `skew` is on:
    /// the next grid leans toward `b`.
    private func select(from a: (row: Int, col: Int), to b: (row: Int, col: Int), shift: Bool) {
        let wasFinal = pairClicks(a, b)
        history.append(grid)
        grid = Grid(rect: grid.span(from: a, to: b),
                    leanX: .toward(b.col, from: a.col),
                    leanY: .toward(b.row, from: a.row),
                    skew: skew)

        if wasFinal {
            finish(rightClick: shiftUsed)
        } else {
            // Too small to label every cell? Grow it (around the selection) until it isn't.
            grid = grid.legible(minCell: minCellSize, within: view.bounds)
            moveCursor(to: global(grid.focus))
            refresh(shiftDown: shift || shiftUsed)
        }
    }

    // MARK: - Private

    private func refresh(shiftDown: Bool) {
        view.grid = grid
        view.level = history.count
        view.isFinal = isFinalLevel(grid)
        view.isMixed = isFinalLevel(grid) && !isFullyFinal(grid)
        view.rightClick = shiftDown || shiftUsed
        view.pending = pending
        view.needsDisplay = true
    }

    private func finish(rightClick: Bool) {
        let point = global(grid.focus)
        cancel()
        // Let the overlay disappear and the tap callback return before clicking.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            Mouse.click(at: point, right: rightClick)
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
    static func move(to p: CGPoint) {
        let e = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                        mouseCursorPosition: p, mouseButton: .left)
        e?.flags = []
        e?.post(tap: .cghidEventTap)
    }

    /// `count` is the click number within a multi-click (1 = single,
    /// 2 = second click of a double-click, 3 = triple-click).
    static func click(at p: CGPoint, right: Bool, count: Int = 1) {
        move(to: p)
        let (downType, upType, button): (CGEventType, CGEventType, CGMouseButton) = right
            ? (.rightMouseDown, .rightMouseUp, .right)
            : (.leftMouseDown, .leftMouseUp, .left)
        let down = CGEvent(mouseEventSource: nil, mouseType: downType,
                           mouseCursorPosition: p, mouseButton: button)
        let up = CGEvent(mouseEventSource: nil, mouseType: upType,
                         mouseCursorPosition: p, mouseButton: button)
        // Clear modifiers so a still-held Shift doesn't turn this into a shift-click.
        down?.flags = []
        up?.flags = []
        down?.setIntegerValueField(.mouseEventClickState, value: Int64(count))
        up?.setIntegerValueField(.mouseEventClickState, value: Int64(count))
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

/// Draws the keyboard-shaped grid over the current region.
final class GridView: NSView {
    var grid = Grid(rect: .zero)
    var level = 0
    var isFinal = false
    /// Final level, but the grid's coarse cells still zoom.
    var isMixed = false
    var rightClick = false
    var pending: (row: Int, col: Int)?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let region = grid.rect

        // Dim everything outside the active region.
        let outside = NSBezierPath(rect: bounds)
        outside.appendRect(region)
        outside.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(level == 0 ? 0.0 : 0.45).setFill()
        outside.fill()

        NSColor.black.withAlphaComponent(0.18).setFill()
        region.fill()

        // Home row tint (A S D F … ;) so you can orient quickly.
        NSColor.systemBlue.withAlphaComponent(0.10).setFill()
        let home = grid.cell(row: KeyLayout.homeRow, col: 0)
        CGRect(x: region.minX, y: home.minY, width: region.width, height: home.height).fill()

        // First key of the pair, waiting for its partner.
        if let p = pending {
            (rightClick ? NSColor.systemRed : NSColor.systemYellow).withAlphaComponent(0.35).setFill()
            grid.cell(row: p.row, col: p.col).fill()
        }

        // Grid lines.
        let lines = NSBezierPath()
        for x in grid.columnEdges.dropFirst().dropLast() {
            lines.move(to: CGPoint(x: x, y: region.minY))
            lines.line(to: CGPoint(x: x, y: region.maxY))
        }
        for y in grid.rowEdges.dropFirst().dropLast() {
            lines.move(to: CGPoint(x: region.minX, y: y))
            lines.line(to: CGPoint(x: region.maxX, y: y))
        }
        lines.lineWidth = 1
        NSColor.white.withAlphaComponent(0.35).setStroke()
        lines.stroke()

        // Region border.
        let border = NSBezierPath(rect: region.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = level == 0 ? 0 : 2
        (rightClick ? NSColor.systemRed : NSColor.systemBlue).setStroke()
        if level > 0 { border.stroke() }

        // Key labels, sized per cell so a leaning grid's small end still fits.
        let pill = (rightClick ? NSColor.systemRed : NSColor.black).withAlphaComponent(0.6)

        for (r, row) in KeyLayout.rows.enumerated() {
            for (c, key) in row.enumerated() {
                let cell = grid.cell(row: r, col: c)
                let fontSize = max(8, min(42, min(cell.width, cell.height) * 0.4))
                let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
                let text = NSAttributedString(string: key.label, attributes: attrs)
                let size = text.size()
                let pad = max(2, fontSize * 0.25)
                let box = CGRect(x: cell.midX - size.width / 2 - pad,
                                 y: cell.midY - size.height / 2 - pad / 2,
                                 width: size.width + pad * 2,
                                 height: size.height + pad)
                pill.setFill()
                NSBezierPath(roundedRect: box, xRadius: pad, yRadius: pad).fill()
                text.draw(at: CGPoint(x: box.minX + pad, y: box.minY + pad / 2))
            }
        }

        drawHint()
    }

    private func drawHint() {
        let mode = rightClick ? "RIGHT CLICK" : "left click"
        let stage = !isFinal ? "next pair zooms"
            : isMixed ? "next pair clicks (large cells zoom)" : "next pair clicks"
        let s = "Level \(level + 1) · \(stage) · \(mode) · 2 keys = between them (same key twice = that key) · ⇧ right-click · space click here · ⌫ back · esc cancel"
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
