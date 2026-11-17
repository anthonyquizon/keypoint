import CoreGraphics
import Foundation

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

    /// The box spanning the centres of two keys' cells (the same key twice =
    /// that key's cell). On an axis where both keys match, the box takes that
    /// row's / column's full extent.
    func span(from a: (row: Int, col: Int), to b: (row: Int, col: Int)) -> CGRect {
        func range(_ e: [CGFloat], _ p: Int, _ q: Int) -> (lo: CGFloat, hi: CGFloat) {
            if p == q { return (e[p], e[p + 1]) }
            func centre(_ i: Int) -> CGFloat { (e[i] + e[i + 1]) / 2 }
            return (centre(min(p, q)), centre(max(p, q)))
        }
        let x = range(columnEdges, a.col, b.col), y = range(rowEdges, a.row, b.row)
        return CGRect(x: x.lo, y: y.lo, width: x.hi - x.lo, height: y.hi - y.lo)
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

    /// The next pair on this grid clicks (rather than zooming another level)
    /// when its cells are no bigger than a normal last-level cell — screen ÷
    /// (10ⁿ, 4ⁿ) for n = `levels` — with `slack` tolerance. Selecting a wide
    /// span (e.g. A + L) makes the cells bigger than that, so another level is
    /// added.
    ///
    /// Size is compared by cell diagonal (≈ worst-case distance from the aimed
    /// point), so a wide-but-short cell can still count as precise enough.
    func isFinal(screen: CGSize, levels: Int, slack: CGFloat) -> Bool {
        let base = Grid.lastLevelCell(screen: screen, levels: levels)
        return hypot(cellSize.width, cellSize.height) <= hypot(base.width, base.height) * slack
    }

    /// A normal last-level cell: screen ÷ (10ⁿ, 4ⁿ) for n = `levels`.
    static func lastLevelCell(screen: CGSize, levels: Int) -> CGSize {
        let n = Double(levels)
        return CGSize(width: screen.width / CGFloat(pow(Double(KeyLayout.columnCount), n)),
                      height: screen.height / CGFloat(pow(Double(KeyLayout.rowCount), n)))
    }

    /// An arrow key's direction.
    enum Direction: Equatable { case up, down, left, right }

    /// The half of `rect` toward `direction` (view space: up = smaller y).
    /// A key then an arrow (E ↑) selects that half of the key's cell.
    static func half(of rect: CGRect, toward direction: Direction) -> CGRect {
        let w = rect.width / 2, h = rect.height / 2
        switch direction {
        case .up:    return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h)
        case .down:  return CGRect(x: rect.minX, y: rect.minY + h, width: rect.width, height: h)
        case .left:  return CGRect(x: rect.minX, y: rect.minY, width: w, height: rect.height)
        case .right: return CGRect(x: rect.minX + w, y: rect.minY, width: w, height: rect.height)
        }
    }

    private static func edges(count n: Int, from start: CGFloat, length: CGFloat) -> [CGFloat] {
        (0...n).map { start + length * CGFloat($0) / CGFloat(n) }
    }
}
