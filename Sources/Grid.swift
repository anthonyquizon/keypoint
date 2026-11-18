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

    init(rect: CGRect) {
        self.rect = rect
        focus = CGPoint(x: rect.midX, y: rect.midY)
        columnEdges = Grid.edges(count: KeyLayout.columnCount, from: rect.minX, length: rect.width)
        rowEdges = Grid.edges(count: KeyLayout.rowCount, from: rect.minY, length: rect.height)
    }

    var cellSize: CGSize {
        CGSize(width: rect.width / CGFloat(KeyLayout.columnCount),
               height: rect.height / CGFloat(KeyLayout.rowCount))
    }

    func cell(row: Int, col: Int) -> CGRect {
        CGRect(x: columnEdges[col], y: rowEdges[row],
               width: columnEdges[col + 1] - columnEdges[col],
               height: rowEdges[row + 1] - rowEdges[row])
    }

    /// What one key press selects: that key's cell, or — if an arrow was
    /// pressed first — the half of it toward the arrow (↑ E = top half of E).
    /// The same arrow `depth` times halves again each time (↑ ↑ E = top quarter).
    func selection(row: Int, col: Int, half direction: Direction? = nil, depth: Int = 1) -> CGRect {
        var c = cell(row: row, col: col)
        guard let direction else { return c }
        for _ in 0..<max(1, depth) { c = Grid.half(of: c, toward: direction) }
        return c
    }

    /// Most times one arrow can be repeated before a key (3 = an eighth).
    static let maxHalvings = 3

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

    /// An arrow key's direction.
    enum Direction: Equatable { case up, down, left, right }

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
}
