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
    /// How far the cells are slid (top-level ⇧ + arrow), wrapping around: a cell
    /// pushed off one side comes back in on the other. Kept within 0..<width / height.
    let offset: CGPoint

    init(rect: CGRect, offset: CGPoint = .zero) {
        self.rect = rect
        self.offset = CGPoint(x: Grid.wrap(offset.x, rect.width), y: Grid.wrap(offset.y, rect.height))
        focus = CGPoint(x: rect.midX, y: rect.midY)
        columnEdges = Grid.edges(count: KeyLayout.columnCount, from: rect.minX, length: rect.width)
        rowEdges = Grid.edges(count: KeyLayout.rowCount, from: rect.minY, length: rect.height)
    }

    var cellSize: CGSize {
        CGSize(width: rect.width / CGFloat(KeyLayout.columnCount),
               height: rect.height / CGFloat(KeyLayout.rowCount))
    }

    /// A key's cell. On a slid grid a cell can straddle the seam and come in two
    /// (or four) pieces; this is the piece the key picks (see `mainPiece`).
    func cell(row: Int, col: Int) -> CGRect {
        mainPiece(of: virtualCell(row: row, col: col), home: unslidCell(row: row, col: col))
    }

    /// The key's cell before any slide.
    private func unslidCell(row: Int, col: Int) -> CGRect {
        CGRect(x: columnEdges[col], y: rowEdges[row],
               width: columnEdges[col + 1] - columnEdges[col],
               height: rowEdges[row + 1] - rowEdges[row])
    }

    /// The key's cell slid by `offset`, before wrapping (it may run past the region).
    func virtualCell(row: Int, col: Int) -> CGRect {
        unslidCell(row: row, col: col).offsetBy(dx: offset.x, dy: offset.y)
    }

    /// `r` (in slid, unwrapped space) wrapped back into the region: up to four pieces.
    func pieces(of r: CGRect) -> [CGRect] {
        func axis(_ lo: CGFloat, _ len: CGFloat, _ start: CGFloat, _ size: CGFloat) -> [(CGFloat, CGFloat)] {
            let a = start + Grid.wrap(lo - start, size), end = start + size
            if a + len <= end + 0.5 { return [(a, len)] }
            return [(a, end - a), (start, a + len - end)]
        }
        var out: [CGRect] = []
        for (x, w) in axis(r.minX, r.width, rect.minX, rect.width) {
            for (y, h) in axis(r.minY, r.height, rect.minY, rect.height) {
                out.append(CGRect(x: x, y: y, width: w, height: h))
            }
        }
        return out
    }

    /// The piece of `r` a key picks: the biggest, or on a tie the one nearest
    /// `home` (where the key sits unslid), so a half-slid Q stays on the left.
    private func mainPiece(of r: CGRect, home: CGRect) -> CGRect {
        func dist(_ p: CGRect) -> CGFloat { hypot(p.midX - home.midX, p.midY - home.midY) }
        return pieces(of: r).min {
            let a = $0.width * $0.height, b = $1.width * $1.height
            return abs(a - b) > 0.5 ? a > b : dist($0) < dist($1)
        }!
    }

    /// What one key press selects: that key's cell, halved once per arrow
    /// pressed before it, in order (↑ E = top half of E, ↑ ← E = its top-left
    /// quarter, ↑ ↓ E = the second quarter from the top).
    func selection(row: Int, col: Int, arrows: [Direction] = []) -> CGRect {
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

    /// This grid slid one cell toward `direction` (⇧ + arrow with no arrows
    /// pending), stopping at the edge of `bounds`. `focus` moves with it. Nil if
    /// it can't move that way (already at that edge, e.g. the whole screen).
    func shifted(toward direction: Direction, within bounds: CGRect) -> Grid? {
        let step = cellSize
        var dx: CGFloat = 0, dy: CGFloat = 0
        switch direction {
        case .up:    dy = max(-step.height, bounds.minY - rect.minY)
        case .down:  dy = min(step.height, bounds.maxY - rect.maxY)
        case .left:  dx = max(-step.width, bounds.minX - rect.minX)
        case .right: dx = min(step.width, bounds.maxX - rect.maxX)
        }
        guard abs(dx) > 0.5 || abs(dy) > 0.5 else { return nil }
        var g = Grid(rect: rect.offsetBy(dx: dx, dy: dy))
        g.focus = CGPoint(x: focus.x + dx, y: focus.y + dy)
        return g
    }

    /// The cells slid half a cell toward `direction`, wrapping: what goes off
    /// one side comes back in on the other (top-level ⇧ + arrow, where the grid
    /// fills the screen). Ten slides right is a whole row's turn, back to the start.
    func slid(toward direction: Direction) -> Grid {
        let half = CGSize(width: cellSize.width / 2, height: cellSize.height / 2)
        var o = offset
        switch direction {
        case .up:    o.y -= half.height
        case .down:  o.y += half.height
        case .left:  o.x -= half.width
        case .right: o.x += half.width
        }
        return Grid(rect: rect, offset: o)
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

    /// `v` wrapped into 0..<size (rounding off float drift near size).
    private static func wrap(_ v: CGFloat, _ size: CGFloat) -> CGFloat {
        guard size > 0 else { return 0 }
        let w = v.truncatingRemainder(dividingBy: size)
        let r = w < 0 ? w + size : w
        return size - r < 0.01 ? 0 : r
    }
}
