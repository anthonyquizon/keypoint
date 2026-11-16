import AppKit
import CoreGraphics

/// Owns the overlay window and the selection state machine.
final class OverlayController {
    private(set) var isActive = false

    private var window: NSWindow?
    private let view = GridView()
    private var screen: NSScreen?

    /// Current region in view coordinates (top-left origin).
    private var region: CGRect = .zero
    private var history: [CGRect] = []
    private var shiftUsed = false

    /// Number of levels before the click fires for normal-sized selections.
    /// Change with:  defaults write local.keypoint levels -int 3
    var maxLevels: Int {
        let v = UserDefaults.standard.integer(forKey: "levels")
        return v > 0 ? v : 2
    }

    /// How much bigger than a normal last-level cell a grid cell may be and
    /// still count as the last level.
    private let finalSlack: CGFloat = 1.5

    /// The level showing `rect` is the last one (next pair clicks) when its grid
    /// cells are no bigger than a normal last-level cell — screen ÷ (10ⁿ, 4ⁿ)
    /// for n = `maxLevels`. Selecting a wide span (e.g. A + L) makes the cells
    /// bigger than that, so another level is added to keep precision.
    private func isFinalLevel(_ rect: CGRect) -> Bool {
        let screen = view.bounds.size
        let n = Double(maxLevels)
        let baseW = screen.width / CGFloat(pow(Double(KeyLayout.columnCount), n))
        let baseH = screen.height / CGFloat(pow(Double(KeyLayout.rowCount), n))
        let cellW = rect.width / CGFloat(KeyLayout.columnCount)
        let cellH = rect.height / CGFloat(KeyLayout.rowCount)
        return cellW <= baseW * finalSlack && cellH <= baseH * finalSlack
    }

    func toggle() { isActive ? cancel() : show() }

    /// Overlay is open but nothing has been selected yet.
    var isPristine: Bool { isActive && history.isEmpty && pending == nil }

    /// Hide the overlay and click wherever the cursor currently is.
    func clickAtMouse(right: Bool) {
        cancel()
        guard let point = CGEvent(source: nil)?.location else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            Mouse.click(at: point, right: right)
        }
    }

    func show() {
        let mouse = NSEvent.mouseLocation
        guard let scr = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.main else { return }
        screen = scr

        let win = window ?? makeWindow()
        win.setFrame(scr.frame, display: false)
        view.frame = CGRect(origin: .zero, size: scr.frame.size)

        region = view.bounds
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
                region = prev
                moveCursor(to: center(of: region))
                refresh(shiftDown: shift)
            } else {
                cancel()
            }
        case KeyLayout.space, KeyLayout.returnKey:
            // Click right now at the centre of the current region.
            // (If one key of a pair is pending, click that key's cell.)
            if let p = pending {
                clearPending()
                history.append(region)
                region = cellRect(from: p, to: p)
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
    /// centred on the line between the keys.
    private func select(from a: (row: Int, col: Int), to b: (row: Int, col: Int), shift: Bool) {
        let sub = cellRect(from: a, to: b)
        let wasFinal = isFinalLevel(region)
        history.append(region)
        region = sub

        if wasFinal {
            finish(rightClick: shiftUsed)
        } else {
            moveCursor(to: center(of: region))
            refresh(shiftDown: shift || shiftUsed)
        }
    }

    private func cellRect(from a: (row: Int, col: Int), to b: (row: Int, col: Int)) -> CGRect {
        func span(_ p: Int, _ q: Int) -> (lo: Double, hi: Double) {
            var lo = Double(min(p, q)) + 0.5, hi = Double(max(p, q)) + 0.5
            if hi - lo < 1 { let mid = (lo + hi) / 2; lo = mid - 0.5; hi = mid + 0.5 }
            return (lo, hi)
        }
        let w = region.width / CGFloat(KeyLayout.columnCount)
        let h = region.height / CGFloat(KeyLayout.rowCount)
        let x = span(a.col, b.col), y = span(a.row, b.row)
        return CGRect(x: region.minX + CGFloat(x.lo) * w,
                      y: region.minY + CGFloat(y.lo) * h,
                      width: CGFloat(x.hi - x.lo) * w,
                      height: CGFloat(y.hi - y.lo) * h)
    }

    // MARK: - Private

    private func refresh(shiftDown: Bool) {
        view.region = region
        view.level = history.count
        view.isFinal = isFinalLevel(region)
        view.rightClick = shiftDown || shiftUsed
        view.pending = pending
        view.needsDisplay = true
    }

    private func finish(rightClick: Bool) {
        let point = center(of: region)
        cancel()
        // Let the overlay disappear and the tap callback return before clicking.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            Mouse.click(at: point, right: rightClick)
        }
    }

    private func moveCursor(to point: CGPoint) {
        Mouse.move(to: point)
    }

    /// Centre of a view-space rect, converted to global CG (top-left) coordinates.
    private func center(of rect: CGRect) -> CGPoint {
        guard let screen, let primary = NSScreen.screens.first else { return .zero }
        let f = screen.frame
        let topInGlobal = primary.frame.height - f.maxY
        return CGPoint(x: f.minX + rect.midX, y: topInGlobal + rect.midY)
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

    static func click(at p: CGPoint, right: Bool) {
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
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

/// Draws the keyboard-shaped grid over the current region.
final class GridView: NSView {
    var region: CGRect = .zero
    var level = 0
    var isFinal = false
    var rightClick = false
    var pending: (row: Int, col: Int)?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // Dim everything outside the active region.
        let outside = NSBezierPath(rect: bounds)
        outside.appendRect(region)
        outside.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(level == 0 ? 0.0 : 0.45).setFill()
        outside.fill()

        NSColor.black.withAlphaComponent(0.18).setFill()
        region.fill()

        let cols = KeyLayout.columnCount, rows = KeyLayout.rowCount
        let cw = region.width / CGFloat(cols)
        let ch = region.height / CGFloat(rows)

        // Home row tint (A S D F … ;) so you can orient quickly.
        NSColor.systemBlue.withAlphaComponent(0.10).setFill()
        CGRect(x: region.minX, y: region.minY + CGFloat(KeyLayout.homeRow) * ch,
               width: region.width, height: ch).fill()

        // First key of the pair, waiting for its partner.
        if let p = pending {
            (rightClick ? NSColor.systemRed : NSColor.systemYellow).withAlphaComponent(0.35).setFill()
            CGRect(x: region.minX + CGFloat(p.col) * cw, y: region.minY + CGFloat(p.row) * ch,
                   width: cw, height: ch).fill()
        }

        // Grid lines.
        let lines = NSBezierPath()
        for c in 1..<cols {
            let x = region.minX + CGFloat(c) * cw
            lines.move(to: CGPoint(x: x, y: region.minY))
            lines.line(to: CGPoint(x: x, y: region.maxY))
        }
        for r in 1..<rows {
            let y = region.minY + CGFloat(r) * ch
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

        // Key labels.
        let fontSize = max(8, min(42, min(cw, ch) * 0.4))
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let pill = (rightClick ? NSColor.systemRed : NSColor.black).withAlphaComponent(0.6)

        for (r, row) in KeyLayout.rows.enumerated() {
            for (c, key) in row.enumerated() {
                let cell = CGRect(x: region.minX + CGFloat(c) * cw,
                                  y: region.minY + CGFloat(r) * ch, width: cw, height: ch)
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
        let stage = isFinal ? "next pair clicks" : "next pair zooms"
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
