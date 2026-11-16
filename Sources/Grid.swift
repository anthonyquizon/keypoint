import CoreGraphics
import Foundation

/// The keyboard-shaped grid laid over a region: where each column and row
/// starts and ends. Normally even; after a directional pair (A then B) it can
/// lean toward B — cells shrink geometrically toward B's end, so precision
/// goes where you said the target is, while the far cells stay as a bail-out.
struct Grid: Equatable {
    /// Which end of an axis gets the small cells.
    enum Lean: Equatable {
        case none
        /// Toward column 0 / row 0.
        case low
        /// Toward the last column / row.
        case high

        /// The lean for a pair pressed `first` then `second` along one axis.
        static func toward(_ second: Int, from first: Int) -> Lean {
            second > first ? .high : second < first ? .low : .none
        }
    }

    let rect: CGRect
    /// Absolute x of each column edge (`columnCount + 1` values, minX…maxX).
    let columnEdges: [CGFloat]
    /// Absolute y of each row edge (`rowCount + 1` values, minY…maxY).
    let rowEdges: [CGFloat]
    let leanX: Lean, leanY: Lean, skew: CGFloat
    /// What was actually selected: where the cursor goes and where Space
    /// clicks. The centre of `rect` unless `legible` grew the grid around it.
    private(set) var focus: CGPoint

    /// - Parameter skew: largest ÷ smallest cell along a leaning axis (1 = even).
    init(rect: CGRect, leanX: Lean = .none, leanY: Lean = .none, skew: CGFloat = 1) {
        // Normalise so equal-looking grids compare equal.
        self.leanX = skew > 1 ? leanX : .none
        self.leanY = skew > 1 ? leanY : .none
        self.skew = self.leanX == .none && self.leanY == .none ? 1 : skew
        self.rect = rect
        focus = CGPoint(x: rect.midX, y: rect.midY)
        columnEdges = Grid.edges(count: KeyLayout.columnCount, from: rect.minX,
                                 length: rect.width, lean: self.leanX, skew: self.skew)
        rowEdges = Grid.edges(count: KeyLayout.rowCount, from: rect.minY,
                              length: rect.height, lean: self.leanY, skew: self.skew)
    }

    /// This grid, made big enough that every cell is at least `minCell` (so
    /// every label fits). Per axis, if the finest cell is too small: first
    /// drop that axis's lean (its fine cells were unreadable anyway); if even
    /// cells are still too small, grow the axis around its centre to exactly
    /// `minCell` per cell, kept inside `bounds`. `focus` stays put.
    ///
    /// An adjusted axis ends up even, so it has no bail-out cells and can't
    /// keep drilling down.
    func legible(minCell: CGSize, within bounds: CGRect) -> Grid {
        func fit(lo: CGFloat, len: CGFloat, count: Int, smallest: CGFloat, lean: Lean, min: CGFloat,
                 boundsLo: CGFloat, boundsLen: CGFloat) -> (lo: CGFloat, len: CGFloat, lean: Lean) {
            guard smallest < min - 1e-9 else { return (lo, len, lean) }
            let even = len / CGFloat(count)
            guard even < min else { return (lo, len, .none) }
            let newLen = Swift.min(min * CGFloat(count), boundsLen)
            let centre = lo + len / 2
            let newLo = Swift.max(boundsLo, Swift.min(centre - newLen / 2, boundsLo + boundsLen - newLen))
            return (newLo, newLen, .none)
        }
        let small = smallestCell
        let x = fit(lo: rect.minX, len: rect.width, count: KeyLayout.columnCount,
                    smallest: small.width, lean: leanX, min: minCell.width,
                    boundsLo: bounds.minX, boundsLen: bounds.width)
        let y = fit(lo: rect.minY, len: rect.height, count: KeyLayout.rowCount,
                    smallest: small.height, lean: leanY, min: minCell.height,
                    boundsLo: bounds.minY, boundsLen: bounds.height)
        var g = Grid(rect: CGRect(x: x.lo, y: y.lo, width: x.len, height: y.len),
                     leanX: x.lean, leanY: y.lean, skew: skew)
        g.focus = focus
        return g
    }

    func cell(row: Int, col: Int) -> CGRect {
        CGRect(x: columnEdges[col], y: rowEdges[row],
               width: columnEdges[col + 1] - columnEdges[col],
               height: rowEdges[row + 1] - rowEdges[row])
    }

    /// Size of the finest cell (narrowest column × shortest row).
    var smallestCell: CGSize {
        CGSize(width: Grid.gaps(columnEdges).min() ?? 0, height: Grid.gaps(rowEdges).min() ?? 0)
    }

    /// Size of the coarsest cell (widest column × tallest row).
    var largestCell: CGSize {
        CGSize(width: Grid.gaps(columnEdges).max() ?? 0, height: Grid.gaps(rowEdges).max() ?? 0)
    }

    /// Whether a cell of this grid is fine enough to click in, rather than
    /// zoom another level. (See `OverlayController.isClickable` for the why.)
    ///
    /// - Parameters:
    ///   - screen: full screen size; with `levels` it sets the normal
    ///     last-level cell, screen ÷ (10ⁿ, 4ⁿ).
    ///   - slack: how much bigger than that a cell may be.
    ///   - evenTolerance: how much bigger than an even cell of this grid a
    ///     leaning cell may be (so cells ≈ even width don't flip-flop).
    func isClickable(_ cell: CGSize, screen: CGSize, levels: Int, slack: CGFloat,
                     evenTolerance: CGFloat = 1.05) -> Bool {
        let n = Double(levels)
        let baseW = screen.width / CGFloat(pow(Double(KeyLayout.columnCount), n))
        let baseH = screen.height / CGFloat(pow(Double(KeyLayout.rowCount), n))
        guard hypot(cell.width, cell.height) <= hypot(baseW, baseH) * slack else { return false }

        let evenW = rect.width / CGFloat(KeyLayout.columnCount)
        let evenH = rect.height / CGFloat(KeyLayout.rowCount)
        // A visibly bigger-than-even cell drills down — unless it's already no
        // bigger than a normal last-level cell (so deeper levels never drill again).
        let wideBailOut = cell.width > evenW * evenTolerance && cell.width > baseW
        let tallBailOut = cell.height > evenH * evenTolerance && cell.height > baseH
        return !wideBailOut && !tallBailOut
    }

    private static func gaps(_ e: [CGFloat]) -> [CGFloat] { zip(e, e.dropFirst()).map { $1 - $0 } }

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

    /// Cell sizes form a geometric series from largest to smallest (ratio
    /// `skew` overall), ordered so the small end is the lean's end.
    private static func edges(count n: Int, from start: CGFloat, length: CGFloat,
                              lean: Lean, skew: CGFloat) -> [CGFloat] {
        var weights = [Double](repeating: 1, count: n)
        if lean != .none, skew > 1, n > 1 {
            let q = pow(Double(skew), 1 / Double(n - 1))
            weights = (0..<n).map { pow(q, -Double($0)) }   // big → small
            if lean == .low { weights.reverse() }
        }
        let total = weights.reduce(0, +)
        var edges = [start], acc = 0.0
        for w in weights {
            acc += w
            edges.append(start + length * CGFloat(acc / total))
        }
        edges[n] = start + length   // no rounding drift at the far edge
        return edges
    }
}
