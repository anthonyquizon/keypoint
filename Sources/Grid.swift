import CoreGraphics

/// The keyboard-shaped grid laid over a region: 10 × 4 even cells.
struct Grid: Equatable {
    let rect: CGRect
    /// Absolute x of each column edge (`columnCount + 1` values, minX…maxX).
    let columnEdges: [CGFloat]
    /// Absolute y of each row edge (`rowCount + 1` values, minY…maxY).
    let rowEdges: [CGFloat]
    /// What was actually selected: where the cursor goes and where Space
    /// clicks. The centre of `rect` unless `legible` grew the grid around it.
    private(set) var focus: CGPoint
    /// How far the cells are slid (arrows), wrapping around every `period`: a cell
    /// pushed off one side comes back in on the other. Kept within 0..<period.
    let offset: CGPoint
    /// Cell size as a multiple of a cell that fills `rect` (`+` / `−` zoom). Under 1
    /// the 40 cells make a smaller box that slides and wraps around all of `rect`;
    /// over 1 the box is bigger than `rect`, and the cells past its edges are out
    /// of view until they're slid in.
    let scale: CGFloat

    /// Most `−` zooms out to: one cell the size of `rect` along its shorter count.
    static let maxScale = CGFloat(min(KeyLayout.columnCount, KeyLayout.rowCount))

    init(rect: CGRect, offset: CGPoint = .zero, scale: CGFloat = 1) {
        self.rect = rect
        self.scale = scale
        let p = CGSize(width: rect.width * max(1, scale), height: rect.height * max(1, scale))
        self.offset = CGPoint(x: Grid.wrap(offset.x, p.width), y: Grid.wrap(offset.y, p.height))
        focus = CGPoint(x: rect.midX, y: rect.midY)
        columnEdges = Grid.edges(count: KeyLayout.columnCount, from: rect.minX, length: rect.width)
        rowEdges = Grid.edges(count: KeyLayout.rowCount, from: rect.minY, length: rect.height)
    }

    /// A cell's size unzoomed: `rect` split 10 × 4.
    var fullCellSize: CGSize {
        CGSize(width: rect.width / CGFloat(KeyLayout.columnCount),
               height: rect.height / CGFloat(KeyLayout.rowCount))
    }

    var cellSize: CGSize {
        CGSize(width: fullCellSize.width * scale, height: fullCellSize.height * scale)
    }

    /// How often the grid repeats: `rect`, or the box once it's bigger than that.
    var period: CGSize {
        CGSize(width: rect.width * max(1, scale), height: rect.height * max(1, scale))
    }

    /// The 40 live cells together, slid and before wrapping (may run past `rect`).
    var box: CGRect {
        CGRect(x: rect.minX + offset.x, y: rect.minY + offset.y,
               width: cellSize.width * CGFloat(KeyLayout.columnCount),
               height: cellSize.height * CGFloat(KeyLayout.rowCount))
    }

    /// Zoomed in: every cell of the keyboard's copies tiled edge to edge round the
    /// live box (the live copy itself left out), wherever they're on screen. They're
    /// only drawn, faded; keys pick from the live box.
    var copies: [(row: Int, col: Int, rect: CGRect)] {
        guard scale < 1 else { return [] }
        let b = box, c = cellSize
        let iLo = Int(((rect.minX - b.maxX) / b.width).rounded(.down)), iHi = Int(((rect.maxX - b.minX) / b.width).rounded(.up))
        let jLo = Int(((rect.minY - b.maxY) / b.height).rounded(.down)), jHi = Int(((rect.maxY - b.minY) / b.height).rounded(.up))
        var out: [(row: Int, col: Int, rect: CGRect)] = []
        for i in iLo...iHi {
            for j in jLo...jHi where i != 0 || j != 0 {
                let x0 = b.minX + CGFloat(i) * b.width, y0 = b.minY + CGFloat(j) * b.height
                for row in 0..<KeyLayout.rowCount {
                    for col in 0..<KeyLayout.columnCount {
                        let r = CGRect(x: x0 + CGFloat(col) * c.width, y: y0 + CGFloat(row) * c.height,
                                       width: c.width, height: c.height)
                        if r.intersects(rect) { out.append((row, col, r)) }
                    }
                }
            }
        }
        return out
    }

    /// Where the grid lines fall, tiled across all of `rect` (its own edges left out),
    /// so the grid reads as endless around the live box.
    var lineXs: [CGFloat] { Grid.tiled(from: rect.minX, size: rect.width, offset: offset.x, step: cellSize.width) }
    var lineYs: [CGFloat] { Grid.tiled(from: rect.minY, size: rect.height, offset: offset.y, step: cellSize.height) }

    /// A key's cell. On a slid grid a cell can straddle the seam and come in two
    /// (or four) pieces; this is the piece the key picks (see `mainPiece`). Nil if
    /// it's out of view (zoomed out past the screen).
    func cell(row: Int, col: Int) -> CGRect? {
        mainPiece(of: virtualCell(row: row, col: col), home: unslidCell(row: row, col: col))
    }

    /// The key's cell before any slide.
    private func unslidCell(row: Int, col: Int) -> CGRect {
        let c = cellSize
        return CGRect(x: rect.minX + CGFloat(col) * c.width, y: rect.minY + CGFloat(row) * c.height,
                      width: c.width, height: c.height)
    }

    /// The key's cell slid by `offset`, before wrapping (it may run past the region).
    func virtualCell(row: Int, col: Int) -> CGRect {
        unslidCell(row: row, col: col).offsetBy(dx: offset.x, dy: offset.y)
    }

    /// `r` (in slid, unwrapped space, at most a `period` long) wrapped back round
    /// every `period` and cut to `rect`: the pieces of it in view, up to four.
    func pieces(of r: CGRect) -> [CGRect] {
        func axis(_ lo: CGFloat, _ len: CGFloat, _ start: CGFloat, _ size: CGFloat,
                  _ period: CGFloat) -> [(CGFloat, CGFloat)] {
            let a = start + Grid.wrap(lo - start, period), end = start + period
            let spans = a + len <= end + 0.5 ? [(a, len)] : [(a, end - a), (start, a + len - end)]
            // Cut to what's in view.
            return spans.compactMap { (lo, len) in
                let l = max(lo, start), h = min(lo + len, start + size)
                return h - l > 0.5 ? (l, h - l) : nil
            }
        }
        let p = period
        var out: [CGRect] = []
        for (x, w) in axis(r.minX, r.width, rect.minX, rect.width, p.width) {
            for (y, h) in axis(r.minY, r.height, rect.minY, rect.height, p.height) {
                out.append(CGRect(x: x, y: y, width: w, height: h))
            }
        }
        return out
    }

    /// The piece of `r` a key picks: the biggest, or on a tie the one nearest
    /// `home` (where the key sits unslid), so a half-slid Q stays on the left.
    private func mainPiece(of r: CGRect, home: CGRect) -> CGRect? {
        func dist(_ p: CGRect) -> CGFloat { hypot(p.midX - home.midX, p.midY - home.midY) }
        return pieces(of: r).min {
            let a = $0.width * $0.height, b = $1.width * $1.height
            return abs(a - b) > 0.5 ? a > b : dist($0) < dist($1)
        }
    }

    /// What one key press selects: that key's cell, halved once per arrow
    /// pressed before it, in order (↑ E = top half of E, ↑ ← E = its top-left
    /// quarter, ↑ ↓ E = the second quarter from the top).
    func selection(row: Int, col: Int, arrows: [Direction] = []) -> CGRect? {
        mainPiece(of: virtualSelection(row: row, col: col, arrows: arrows),
                  home: unslidCell(row: row, col: col))
    }

    /// `selection` before wrapping: always the full size (for "does it click?").
    func virtualSelection(row: Int, col: Int, arrows: [Direction] = []) -> CGRect {
        arrows.reduce(virtualCell(row: row, col: col)) { Grid.half(of: $0, toward: $1) }
    }

    /// Most arrows per axis before a key (4 = a sixteenth of the cell).
    static let maxHalvings = 4

    /// A selection this thin (≤ `size` points either way) is clicked at its
    /// centre at once: e.g. ↑ ↑ ↑ ↑ narrows a cell to a strip one line tall.
    static func isClickSize(_ r: CGRect, size: CGFloat) -> Bool {
        r.width <= size || r.height <= size
    }

    /// `arrows` with `direction` pushed on, or nil if its axis is already at `maxHalvings`.
    static func push(_ direction: Direction, onto arrows: [Direction]) -> [Direction]? {
        let sameAxis = arrows.filter { $0.isVertical == direction.isVertical }.count
        return sameAxis < maxHalvings ? arrows + [direction] : nil
    }

    /// `arrows` with their shaded slot moved one slot toward `direction` (⇧ + arrow):
    /// ↑ ↑ (top quarter) nudged down is ↑ ↓ (the 2nd quarter). Each arrow on that
    /// axis keeps its place in the order. Nil if that axis has no arrows, or the
    /// slot is already at that edge of the cell.
    static func nudge(_ arrows: [Direction], toward direction: Direction) -> [Direction]? {
        let vertical = direction.isVertical
        let places = arrows.indices.filter { arrows[$0].isVertical == vertical }
        guard !places.isEmpty else { return nil }
        let n = places.count
        // Slot index (0 = top / left) the halvings land in, as bits, first arrow highest.
        let k = places.reduce(0) { $0 * 2 + (arrows[$1] == .down || arrows[$1] == .right ? 1 : 0) }
        let moved = k + (direction == .down || direction == .right ? 1 : -1)
        guard moved >= 0, moved < 1 << n else { return nil }
        var out = arrows
        for (i, place) in places.enumerated() {
            let high = (moved >> (n - 1 - i)) & 1 == 1
            out[place] = vertical ? (high ? .down : .up) : (high ? .right : .left)
        }
        return out
    }

    /// Where `arrows` land within a cell, for the hint bar: e.g. "top quarter",
    /// "2nd quarter from top · left half". Empty for no arrows.
    static func describe(_ arrows: [Direction]) -> String {
        func axis(_ steps: [Direction], first: String, last: String) -> String? {
            guard !steps.isEmpty else { return nil }
            let n = steps.count, slots = 1 << n
            // Index of the slot (0 = top / left) the halvings land in.
            let k = steps.reduce(0) { $0 * 2 + ($1 == .down || $1 == .right ? 1 : 0) }
            let size = ["half", "quarter", "eighth", "sixteenth"][n - 1]
            if k == 0 { return "\(first) \(size)" }
            if k == slots - 1 { return "\(last) \(size)" }
            let d = (k + 1) % 10
            let suffix = (11...13).contains(k + 1) || d == 0 || d > 3 ? "th" : ["st", "nd", "rd"][d - 1]
            return "\(k + 1)\(suffix) \(size) from \(first)"
        }
        return [axis(arrows.filter(\.isVertical), first: "top", last: "bottom"),
                axis(arrows.filter { !$0.isVertical }, first: "left", last: "right")]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// This grid, grown around its centre (kept inside `bounds`) so every cell
    /// is at least `minCell` and every label fits. `focus` stays put.
    func legible(minCell: CGSize, within bounds: CGRect) -> Grid {
        func fit(lo: CGFloat, len: CGFloat, count: Int, min: CGFloat,
                 boundsLo: CGFloat, boundsLen: CGFloat) -> (lo: CGFloat, len: CGFloat) {
            guard len / CGFloat(count) < min else { return (lo, len) }
            let newLen = Swift.min(min * CGFloat(count), boundsLen)
            let centre = lo + len / 2
            return (Swift.max(boundsLo, Swift.min(centre - newLen / 2, boundsLo + boundsLen - newLen)), newLen)
        }
        let x = fit(lo: rect.minX, len: rect.width, count: KeyLayout.columnCount,
                    min: minCell.width, boundsLo: bounds.minX, boundsLen: bounds.width)
        let y = fit(lo: rect.minY, len: rect.height, count: KeyLayout.rowCount,
                    min: minCell.height, boundsLo: bounds.minY, boundsLen: bounds.height)
        var g = Grid(rect: CGRect(x: x.lo, y: y.lo, width: x.len, height: y.len))
        g.focus = focus
        return g
    }

    /// This grid slid `fraction` of a cell toward `direction` (an arrow on a
    /// zoomed-in level), stopping at the edge of `bounds`. `focus` moves with it. Nil if
    /// it can't move that way (already at that edge, e.g. the whole screen).
    func shifted(toward direction: Direction, within bounds: CGRect, fraction: CGFloat = 1) -> Grid? {
        let step = CGSize(width: cellSize.width * fraction, height: cellSize.height * fraction)
        var dx: CGFloat = 0, dy: CGFloat = 0
        switch direction {
        case .up:    dy = max(-step.height, bounds.minY - rect.minY)
        case .down:  dy = min(step.height, bounds.maxY - rect.maxY)
        case .left:  dx = max(-step.width, bounds.minX - rect.minX)
        case .right: dx = min(step.width, bounds.maxX - rect.maxX)
        }
        guard abs(dx) > 0.5 || abs(dy) > 0.5 else { return nil }
        var g = Grid(rect: rect.offsetBy(dx: dx, dy: dy), offset: offset, scale: scale)
        g.focus = CGPoint(x: focus.x + dx, y: focus.y + dy)
        return g
    }

    /// The cells slid `step` toward `direction`, wrapping: what goes off one side
    /// comes back in on the other (an arrow, where the grid fills the screen).
    func slid(toward direction: Direction, by step: CGSize) -> Grid {
        let half = step
        var o = offset
        switch direction {
        case .up:    o.y -= half.height
        case .down:  o.y += half.height
        case .left:  o.x -= half.width
        case .right: o.x += half.width
        }
        return Grid(rect: rect, offset: o, scale: scale)
    }

    /// The cells scaled by `factor` (`+` / `−`: under 1 zooms in) around the live
    /// box's centre, or around `key`'s cell (⇧ + a key), the grid still wrapping.
    /// Nil if nothing would change, the cells would get under `minCell`, or past `maxScale`.
    func zoomed(by factor: CGFloat, minCell: CGSize, around key: (row: Int, col: Int)? = nil) -> Grid? {
        var next = min(Grid.maxScale, scale * factor)
        if abs(next - 1) < 1e-6 { next = 1 }   // land back on exactly unzoomed
        guard abs(next - scale) > 1e-6 else { return nil }
        let full = fullCellSize
        guard full.width * next >= minCell.width - 0.01, full.height * next >= minCell.height - 0.01 else { return nil }
        // Zoom around a point that stays put: the screen's centre while the box
        // covers the screen, otherwise the box's own centre. `u` is where that
        // point sits inside the box; it scales with the cells.
        let p = period, b = box
        let anchor: CGPoint, u: CGPoint
        if let key {
            // That key's cell centre stays put (where it is on screen, wrapped).
            let c = cellSize
            u = CGPoint(x: (CGFloat(key.col) + 0.5) * c.width, y: (CGFloat(key.row) + 0.5) * c.height)
            anchor = CGPoint(x: rect.minX + Grid.wrap(b.minX + u.x - rect.minX, p.width),
                             y: rect.minY + Grid.wrap(b.minY + u.y - rect.minY, p.height))
        } else if scale >= 1 {
            anchor = CGPoint(x: rect.midX, y: rect.midY)
            u = CGPoint(x: Grid.wrap(anchor.x - b.minX, p.width), y: Grid.wrap(anchor.y - b.minY, p.height))
        } else {
            u = CGPoint(x: b.width / 2, y: b.height / 2)
            anchor = CGPoint(x: rect.minX + Grid.wrap(b.midX - rect.minX, p.width),
                             y: rect.minY + Grid.wrap(b.midY - rect.minY, p.height))
        }
        let k = next / scale
        let o = CGPoint(x: anchor.x - u.x * k - rect.minX, y: anchor.y - u.y * k - rect.minY)
        return Grid(rect: rect, offset: o, scale: next)
    }

    /// An arrow key's direction.
    enum Direction: Equatable {
        case up, down, left, right
        var isVertical: Bool { self == .up || self == .down }
        var symbol: String {
            switch self {
            case .up: return "↑"
            case .down: return "↓"
            case .left: return "←"
            case .right: return "→"
            }
        }
    }

    /// The half of `rect` toward `direction` (view space: up = smaller y).
    /// An arrow then a key (↑ E) selects that half of the key's cell.
    static func half(of rect: CGRect, toward direction: Direction) -> CGRect {
        let w = rect.width / 2, h = rect.height / 2
        switch direction {
        case .up:    return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h)
        case .down:  return CGRect(x: rect.minX, y: rect.minY + h, width: rect.width, height: h)
        case .left:  return CGRect(x: rect.minX, y: rect.minY, width: w, height: rect.height)
        case .right: return CGRect(x: rect.minX + w, y: rect.minY, width: w, height: rect.height)
        }
    }

    /// Drag end points widened so the characters under both of them are
    /// selected. Text selection snaps each end to the nearest gap between
    /// characters, so a point on the right half of the first character would
    /// start after it, and one on the left half of the last would end before
    /// it. Each end moves `nudge` points outward along the reading order:
    /// a forward drag (later line, or the same line and to the right; lines
    /// count as the same within `sameLine` points) moves the start left and
    /// the end right; a backward drag the opposite.
    static func inclusiveDrag(from start: CGPoint, to end: CGPoint, nudge: CGFloat,
                              sameLine: CGFloat = 6) -> (from: CGPoint, to: CGPoint) {
        let dy = end.y - start.y
        let forward = abs(dy) <= sameLine ? end.x >= start.x : dy > 0
        let d = forward ? nudge : -nudge
        return (CGPoint(x: start.x - d, y: start.y), CGPoint(x: end.x + d, y: end.y))
    }

    private static func edges(count n: Int, from start: CGFloat, length: CGFloat) -> [CGFloat] {
        (0...n).map { start + length * CGFloat($0) / CGFloat(n) }
    }

    /// Lines every `step` from `from + offset`, wrapped into `from`'s span of `size`.
    private static func tiled(from: CGFloat, size: CGFloat, offset: CGFloat, step: CGFloat) -> [CGFloat] {
        guard step > 0.5 else { return [] }
        let first = from + wrap(offset, step)
        return stride(from: first, to: from + size - 0.5, by: step).filter { $0 - from > 0.5 }
    }

    /// `v` wrapped into 0..<size (rounding off float drift near size).
    private static func wrap(_ v: CGFloat, _ size: CGFloat) -> CGFloat {
        guard size > 0 else { return 0 }
        let w = v.truncatingRemainder(dividingBy: size)
        let r = w < 0 ? w + size : w
        return size - r < 0.01 ? 0 : r
    }
}
