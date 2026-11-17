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
        selectionIsCell()
        selectionWithArrowIsHalf()
        twoKeysReachLastLevelCell()
        legibleLeavesBigGridsAlone()
        legibleGrowsAroundFocus()
        legibleStaysOnScreen()
        arrowHalves()

        print(failures == 0 ? "OK — \(checks) checks passed" : "\(failures) of \(checks) checks failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Cells and selections

    static func evenGrid() {
        let g = Grid(rect: rect)
        check(g.columnEdges == (0...10).map { CGFloat($0) * 100 }, "even column edges")
        check(g.rowEdges == [0, 100, 200, 300, 400], "even row edges")
        check(g.cellSize == CGSize(width: 100, height: 100), "cell size")
        check(g.cell(row: 2, col: 3) == CGRect(x: 300, y: 200, width: 100, height: 100), "cell rect")
    }

    static func offsetRect() {
        let g = Grid(rect: CGRect(x: 200, y: 50, width: 300, height: 80))
        check(g.columnEdges.first == 200 && g.columnEdges.last == 500, "column edges offset")
        check(g.rowEdges.first == 50 && g.rowEdges.last == 130, "row edges offset")
    }

    static func selectionIsCell() {
        let g = Grid(rect: rect)
        for (r, c) in [(0, 0), (2, 5), (3, 9)] {
            check(g.selection(row: r, col: c) == g.cell(row: r, col: c), "key \(r),\(c) = its cell")
        }
    }

    static func selectionWithArrowIsHalf() {
        let g = Grid(rect: rect)
        let e = g.cell(row: 1, col: 2)
        for d: Grid.Direction in [.up, .down, .left, .right] {
            check(g.selection(row: 1, col: 2, half: d) == Grid.half(of: e, toward: d), "\(d) E = that half of E")
        }
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
            let l2 = Grid(rect: top.selection(row: 2, col: 3))
            let target = Grid(rect: l2.selection(row: 2, col: 6))
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

    // MARK: - Arrows

    static func arrowHalves() {
        let c = CGRect(x: 100, y: 200, width: 40, height: 80)
        check(Grid.half(of: c, toward: .up) == CGRect(x: 100, y: 200, width: 40, height: 40), "↑ = top half")
        check(Grid.half(of: c, toward: .down) == CGRect(x: 100, y: 240, width: 40, height: 40), "↓ = bottom half")
        check(Grid.half(of: c, toward: .left) == CGRect(x: 100, y: 200, width: 20, height: 80), "← = left half")
        check(Grid.half(of: c, toward: .right) == CGRect(x: 120, y: 200, width: 20, height: 80), "→ = right half")
        let up = Grid(rect: Grid.half(of: c, toward: .up))
        check(up.focus == CGPoint(x: 120, y: 220), "↑ E clicks a quarter of the way down E")
        check(KeyLayout.arrows[126] == .up && KeyLayout.arrows[123] == .left, "arrow key codes")
    }
}
