import CoreGraphics

/// The keyboard-shaped grid laid over a region: 10 × 4 even cells. Arrows shift the
/// keys across it, and it wraps: a key pushed past one edge comes back on the other.
struct Grid: Equatable {
    let rect: CGRect
    /// How far the keys are shifted, in cells (x right, y down), wrapped to within
    /// one grid's width / height.
    private(set) var offset = CGVector.zero
    /// What was actually selected: where the cursor goes and where Space
    /// clicks. The centre of `rect` unless `legible` grew the grid around it,
    /// or ⇧ + a key moved the mouse to that key.
    var focus: CGPoint

    init(rect: CGRect) {
        self.rect = rect
        focus = CGPoint(x: rect.midX, y: rect.midY)
    }

    var cellSize: CGSize {
        CGSize(width: rect.width / CGFloat(KeyLayout.columnCount),
               height: rect.height / CGFloat(KeyLayout.rowCount))
    }

    /// A key's cell, shifted by `offset` and wrapped so its centre is inside `rect`
    /// (that's where its key clicks). Shifted far enough, it hangs over an edge of
    /// `rect`; that part shows on the opposite side (see `tiles`).
    func cell(row: Int, col: Int) -> CGRect {
        let s = cellSize
        let x = Grid.wrap(CGFloat(col) + 0.5 + offset.dx, KeyLayout.columnCount) - 0.5
        let y = Grid.wrap(CGFloat(row) + 0.5 + offset.dy, KeyLayout.rowCount) - 0.5
        return CGRect(x: rect.minX + x * s.width, y: rect.minY + y * s.height,
                      width: s.width, height: s.height)
    }

    /// `r` and its copies one grid's width / height away, where they overlap `rect`:
    /// a cell hanging over one edge also shows on the other.
    func tiles(of r: CGRect) -> [CGRect] {
        [-rect.width, 0, rect.width].flatMap { dx in
            [-rect.height, 0, rect.height].map { dy in r.offsetBy(dx: dx, dy: dy) }
        }.filter { !$0.intersection(rect).isEmpty }
    }

    /// x of each line between columns inside `rect`, left to right (one that lands on
    /// its edge isn't included).
    var columnLines: [CGFloat] {
        Grid.lines(KeyLayout.columnCount, offset: offset.dx, from: rect.minX, step: cellSize.width)
    }

    /// y of each line between rows inside `rect`, top to bottom.
    var rowLines: [CGFloat] {
        Grid.lines(KeyLayout.rowCount, offset: offset.dy, from: rect.minY, step: cellSize.height)
    }

    /// This grid with its keys moved `cells` cells toward `direction`, wrapping round.
    func shifted(_ direction: Direction, by cells: CGFloat) -> Grid {
        var g = self
        switch direction {
        case .up:    g.offset.dy = Grid.wrap(offset.dy - cells, KeyLayout.rowCount)
        case .down:  g.offset.dy = Grid.wrap(offset.dy + cells, KeyLayout.rowCount)
        case .left:  g.offset.dx = Grid.wrap(offset.dx - cells, KeyLayout.columnCount)
        case .right: g.offset.dx = Grid.wrap(offset.dx + cells, KeyLayout.columnCount)
        }
        return g
    }

    /// This grid with its keys back in place.
    var unshifted: Grid {
        var g = self
        g.offset = .zero
        return g
    }

    /// A selection this thin (≤ `size` points either way) is clicked at its
    /// centre at once instead of zooming another level.
    static func isClickSize(_ r: CGRect, size: CGFloat) -> Bool {
        r.width <= size || r.height <= size
    }

    /// This grid, grown around its centre so every cell is at least `minCell` and
    /// every label fits, and moved inside `bounds` (a key that hung over the edge of
    /// the screen comes back onto it). `focus` stays put.
    func legible(minCell: CGSize, within bounds: CGRect) -> Grid {
        func fit(lo: CGFloat, len: CGFloat, count: Int, min: CGFloat,
                 boundsLo: CGFloat, boundsLen: CGFloat) -> (lo: CGFloat, len: CGFloat) {
            let newLen = Swift.min(Swift.max(len, min * CGFloat(count)), boundsLen)
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

    /// An arrow key's direction (view space: up = smaller y).
    enum Direction: Equatable {
        case up, down, left, right
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

    /// Where the `n` lines before each column (or row) land, `offset` cells along and
    /// wrapped, leaving out one on the region's edge.
    private static func lines(_ n: Int, offset: CGFloat, from start: CGFloat, step: CGFloat) -> [CGFloat] {
        (0..<n).map { wrap(CGFloat($0) + offset, n) }.filter { $0 > 0 }.sorted().map { start + $0 * step }
    }

    /// `v` wrapped into 0..<n.
    private static func wrap(_ v: CGFloat, _ n: Int) -> CGFloat {
        let r = v.truncatingRemainder(dividingBy: CGFloat(n))
        return r < 0 ? r + CGFloat(n) : r
    }
}
