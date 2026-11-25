import CoreGraphics

// Plain assertion tests for Grid — no XCTest or package needed.
// Run with:  ./build.sh test

@main
struct GridTests {
    static var failures = 0
    static var checks = 0

    static func check(_ ok: Bool, _ what: String, file: StaticString = #file, line: UInt = #line) {
        checks += 1
        if !ok {
            failures += 1
            print("FAIL \(file):\(line): \(what)")
        }
    }

    static func close(_ a: CGFloat, _ b: CGFloat, _ what: String, eps: CGFloat = 1e-6,
                      file: StaticString = #file, line: UInt = #line) {
        check(abs(a - b) <= eps, "\(what): \(a) ≠ \(b)", file: file, line: line)
    }

    static let rect = CGRect(x: 0, y: 0, width: 1000, height: 400)

    static func main() {
        evenGrid()
        offsetRect()
        twoKeysReachLastLevelCell()
        legibleLeavesBigGridsAlone()
        legibleGrowsAroundFocus()
        legibleStaysOnScreen()
        legibleBringsAWrappedKeyOnScreen()
        inclusiveDragWidensOutward()
        smallPicksClickAtOnce()
        shiftMovesTheKeys()
        shiftWrapsRound()
        slideMovesTheBox()
        slideStopsAtTheEdge()
        buttonTests()
        scrollTests()

        print(failures == 0 ? "OK — \(checks) checks passed" : "\(failures) of \(checks) checks failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Cells and selections

    static func evenGrid() {
        let g = Grid(rect: rect)
        check(g.columnLines == (1...9).map { CGFloat($0) * 100 }, "even column lines")
        check(g.rowLines == [100, 200, 300], "even row lines")
        check(g.cellSize == CGSize(width: 100, height: 100), "cell size")
        check(g.cell(row: 2, col: 3) == CGRect(x: 300, y: 200, width: 100, height: 100), "cell rect")
        check(g.tiles(of: g.cell(row: 0, col: 9)) == [g.cell(row: 0, col: 9)], "an unshifted cell shows once")
    }

    static func offsetRect() {
        let g = Grid(rect: CGRect(x: 200, y: 50, width: 300, height: 80))
        check(g.cell(row: 0, col: 0).minX == 200 && g.cell(row: 0, col: 9).maxX == 500, "columns offset")
        check(g.cell(row: 0, col: 0).minY == 50 && g.cell(row: 3, col: 0).maxY == 130, "rows offset")
        check(g.columnLines.first == 230 && g.rowLines.first == 70, "lines offset")
    }

    // MARK: - Levels

    static let minCell = CGSize(width: 18, height: 18)

    static let screens: [CGSize] = [
        CGSize(width: 1280, height: 800), CGSize(width: 1920, height: 1080),
        CGSize(width: 2240, height: 1260), CGSize(width: 3840, height: 2160),
        CGSize(width: 1080, height: 1920),   // portrait
    ]

    /// Two keys (F then J) land on a screen ÷ (100, 16) cell, and the click
    /// point is its centre. (Before `legible` grows small grids.)
    static func twoKeysReachLastLevelCell() {
        for screen in screens {
            let top = Grid(rect: CGRect(origin: .zero, size: screen))
            let l2 = Grid(rect: top.cell(row: 2, col: 3))
            let target = Grid(rect: l2.cell(row: 2, col: 6))
            close(target.rect.width, screen.width / 100, "\(screen): cell width")
            close(target.rect.height, screen.height / 16, "\(screen): cell height")
            close(target.focus.x, screen.width * (0.3 + 0.065), "\(screen): click x")
        }
    }

    // MARK: - Minimum cell size

    static let bounds = CGRect(x: 0, y: 0, width: 2240, height: 1260)

    static func legibleLeavesBigGridsAlone() {
        let g = Grid(rect: CGRect(x: 0, y: 0, width: 224, height: 315))
        check(g.legible(minCell: minCell, within: bounds) == g, "big enough → unchanged")
    }

    static func legibleGrowsAroundFocus() {
        let r = CGRect(x: 1000, y: 600, width: 50, height: 20)
        let l = Grid(rect: r).legible(minCell: minCell, within: bounds)
        close(l.rect.width, 180, "grown to 10 × 18")
        close(l.rect.height, 72, "grown to 4 × 18")
        close(l.rect.midX, r.midX, "centred on selection (x)")
        close(l.rect.midY, r.midY, "centred on selection (y)")
        check(l.focus == CGPoint(x: r.midX, y: r.midY), "focus unchanged")
    }

    /// Near the menu bar: grows down instead of off-screen, keeps the focus.
    static func legibleStaysOnScreen() {
        let r = CGRect(x: 2230, y: 0, width: 10, height: 6)
        let l = Grid(rect: r).legible(minCell: minCell, within: bounds)
        check(l.rect.minY == 0 && l.rect.maxX == 2240, "pinned to the screen corner")
        close(l.rect.width, 180, "full width still")
        check(l.focus == CGPoint(x: r.midX, y: r.midY), "focus still on the selection")
    }

    /// A key shifted over the screen's edge zooms into the part on screen, and its
    /// centre (where it clicks) stays put.
    static func legibleBringsAWrappedKeyOnScreen() {
        let r = CGRect(x: -96, y: 600, width: 192, height: 270)
        let l = Grid(rect: r).legible(minCell: minCell, within: bounds)
        check(l.rect == CGRect(x: 0, y: 600, width: 192, height: 270), "moved on screen, same size")
        check(l.focus == CGPoint(x: 0, y: 735), "focus still the key's centre")
    }

    static func smallPicksClickAtOnce() {
        check(Grid.isClickSize(CGRect(x: 0, y: 0, width: 20, height: 24), size: 24), "≤ size both ways clicks")
        check(Grid.isClickSize(CGRect(x: 0, y: 0, width: 20, height: 300), size: 24), "narrow enough clicks")
        check(Grid.isClickSize(CGRect(x: 0, y: 0, width: 300, height: 10), size: 24), "short enough clicks")
        check(!Grid.isClickSize(CGRect(x: 0, y: 0, width: 30, height: 30), size: 24), "too big both ways zooms")
    }

    static func inclusiveDragWidensOutward() {
        let a = CGPoint(x: 100, y: 50)
        // Forward on the same line: start moves left, end moves right.
        var r = Grid.inclusiveDrag(from: a, to: CGPoint(x: 200, y: 52), nudge: 4)
        close(r.from.x, 96, "same line forward start"); close(r.to.x, 204, "same line forward end")
        close(r.from.y, 50, "y untouched")
        // Backward on the same line: the opposite.
        r = Grid.inclusiveDrag(from: a, to: CGPoint(x: 20, y: 48), nudge: 4)
        close(r.from.x, 104, "same line backward start"); close(r.to.x, 16, "same line backward end")
        // A later line counts as forward even when the end is further left.
        r = Grid.inclusiveDrag(from: a, to: CGPoint(x: 20, y: 90), nudge: 4)
        close(r.from.x, 96, "next line start"); close(r.to.x, 24, "next line end")
        // An earlier line counts as backward even when the end is further right.
        r = Grid.inclusiveDrag(from: a, to: CGPoint(x: 300, y: 10), nudge: 4)
        close(r.from.x, 104, "previous line start"); close(r.to.x, 296, "previous line end")
    }

    // MARK: - Shifting

    static func shiftMovesTheKeys() {
        let g = Grid(rect: rect)   // cells 100 × 100
        let r = g.shifted(.right, by: 0.25)
        check(r.cell(row: 2, col: 3) == CGRect(x: 325, y: 200, width: 100, height: 100), "→ a quarter = 25pt right")
        check(r.columnLines == (0...9).map { CGFloat($0) * 100 + 25 }, "every line moves; none on the edge")
        check(r.rowLines == g.rowLines, "rows untouched")
        let d = g.shifted(.down, by: 0.5)
        check(d.cell(row: 0, col: 0) == CGRect(x: 0, y: 50, width: 100, height: 100), "↓ a half = 50pt down")
        check(g.shifted(.left, by: 0.125).shifted(.right, by: 0.125) == g, "← then → = back in place")
        check(g.shifted(.up, by: 0.5).shifted(.left, by: 2).unshifted == g, "unshifted = back in place")
        check(g.shifted(.right, by: 10) == g && g.shifted(.up, by: 4) == g, "a whole grid round = no shift")
        check(KeyLayout.arrows[126] == .up && KeyLayout.arrows[123] == .left, "arrow key codes")
    }

    /// A key pushed past one edge comes back on the other, and its centre (where it
    /// clicks) is always inside the region.
    static func shiftWrapsRound() {
        let g = Grid(rect: rect)
        let r = g.shifted(.right, by: 0.75)   // "0": 975…1075, over the right edge
        let zero = r.cell(row: 0, col: 9)
        check(zero == CGRect(x: -25, y: 0, width: 100, height: 100), "past the right edge = back on the left")
        check(r.tiles(of: zero) == [zero, zero.offsetBy(dx: 1000, dy: 0)], "shows on both edges")
        check(r.cell(row: 0, col: 0) == CGRect(x: 75, y: 0, width: 100, height: 100), "1 moves right as usual")
        let up = g.shifted(.up, by: 1)
        check(up.cell(row: 0, col: 0) == CGRect(x: 0, y: 300, width: 100, height: 100), "a row up: the top row wraps to the bottom")
        check(up.cell(row: 1, col: 0) == CGRect(x: 0, y: 0, width: 100, height: 100), "and Q comes to the top")
        for n in 0..<32 {
            let s = g.shifted(.left, by: CGFloat(n) * 0.375).shifted(.down, by: CGFloat(n) * 0.625)
            for row in 0..<KeyLayout.rowCount {
                for col in 0..<KeyLayout.columnCount {
                    let c = s.cell(row: row, col: col)
                    check(rect.contains(CGPoint(x: c.midX, y: c.midY)), "shift \(n): \(row),\(col) centre inside")
                }
            }
        }
    }

    // MARK: - Sliding (drilled down)

    static let box = CGRect(x: 400, y: 100, width: 200, height: 80)

    /// The whole box moves a fraction of its own size, keys and focus with it; the keys
    /// don't shift inside it.
    static func slideMovesTheBox() {
        let g = Grid(rect: box)
        let r = g.slid(.right, by: 0.125, within: rect)
        check(r.rect == box.offsetBy(dx: 25, dy: 0), "→ an eighth of the box = 25pt right")
        check(r.focus == CGPoint(x: 525, y: 140), "focus goes with it")
        check(r.cell(row: 2, col: 3) == g.cell(row: 2, col: 3).offsetBy(dx: 25, dy: 0), "keys go with it")
        check(r.offset == .zero && r.columnLines == g.columnLines.map { $0 + 25 }, "keys not shifted inside it")
        check(g.slid(.down, by: 0.5, within: rect).rect == box.offsetBy(dx: 0, dy: 40), "↓ half the box = 40pt down")
        check(g.slid(.left, by: 0.125, within: rect).slid(.right, by: 0.125, within: rect) == g, "← then → = back in place")
        check(!g.isShifted && r.isShifted, "slid counts as shifted")
        check(r.slid(.up, by: 0.5, within: rect).unshifted == g, "unshifted = back where it was picked")

        var moved = g
        moved.focus = CGPoint(x: 410, y: 110)   // ⇧ + key moved the mouse
        check(moved.slid(.left, by: 0.25, within: rect).focus == CGPoint(x: 360, y: 110), "a moved focus goes with it too")
    }

    /// The box stops at the screen's edge rather than going off it.
    static func slideStopsAtTheEdge() {
        let g = Grid(rect: box)
        var u = g
        for _ in 0..<3 { u = u.slid(.up, by: 0.5, within: rect) }   // 100 → 60 → 20 → 0
        check(u.rect == CGRect(x: 400, y: 0, width: 200, height: 80), "stops at the top")
        check(u.focus == CGPoint(x: 500, y: 40), "focus stops with it")
        check(u.unshifted == g, "and still goes back where it was picked")
        let corner = Grid(rect: CGRect(x: 800, y: 320, width: 200, height: 80))
        check(corner.slid(.right, by: 0.5, within: rect) == corner, "already at the right edge: stays")
        check(corner.slid(.down, by: 0.5, within: rect) == corner, "already at the bottom: stays")
        check(!corner.slid(.right, by: 0.5, within: rect).isShifted, "not moved = not shifted")
    }
}
