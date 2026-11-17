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
        spanSameKeyIsCell()
        spanUsesCentres()
        spanMatchesOldFormula()
        normalPathIsTwoLevels()
        wideSpanAddsOneLevel()
        moreLevelsSetting()
        legibleLeavesBigGridsAlone()
        legibleGrowsAroundFocus()
        legibleStaysOnScreen()
        arrowHalves()

        print(failures == 0 ? "OK — \(checks) checks passed" : "\(failures) of \(checks) checks failed")
        if failures > 0 { exit(1) }
    }

    // MARK: - Cells and spans

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

    static func spanSameKeyIsCell() {
        let g = Grid(rect: rect)
        for (r, c) in [(0, 0), (2, 5), (3, 9)] {
            check(g.span(from: (r, c), to: (r, c)) == g.cell(row: r, col: c), "same key \(r),\(c) = its cell")
        }
    }

    static func spanUsesCentres() {
        let g = Grid(rect: rect)
        check(g.span(from: (1, 0), to: (1, 9)) == CGRect(x: 50, y: 100, width: 900, height: 100),
              "Q P spans Q's centre to P's, Q-row tall")
        check(g.span(from: (1, 9), to: (1, 0)) == g.span(from: (1, 0), to: (1, 9)), "order doesn't matter")
    }

    /// Every key pair must select the same box as the original formula: span
    /// between cell centres, any axis thinner than a cell padded to one cell.
    static func spanMatchesOldFormula() {
        let g = Grid(rect: rect)
        let cw = rect.width / 10, ch = rect.height / 4
        func old(_ p: Int, _ q: Int) -> (CGFloat, CGFloat) {
            var lo = CGFloat(min(p, q)) + 0.5, hi = CGFloat(max(p, q)) + 0.5
            if hi - lo < 1 { let mid = (lo + hi) / 2; lo = mid - 0.5; hi = mid + 0.5 }
            return (lo, hi)
        }
        var mismatches = 0
        for r1 in 0..<4 { for c1 in 0..<10 { for r2 in 0..<4 { for c2 in 0..<10 {
            let (x0, x1) = old(c1, c2), (y0, y1) = old(r1, r2)
            let want = CGRect(x: x0 * cw, y: y0 * ch, width: (x1 - x0) * cw, height: (y1 - y0) * ch)
            let got = g.span(from: (r1, c1), to: (r2, c2))
            if abs(got.minX - want.minX) > 1e-9 || abs(got.maxX - want.maxX) > 1e-9
                || abs(got.minY - want.minY) > 1e-9 || abs(got.maxY - want.maxY) > 1e-9 {
                mismatches += 1
            }
        }}}}
        check(mismatches == 0, "span matches old formula for all 1600 pairs (\(mismatches) differ)")
    }

    // MARK: - Levels

    static let minCell = CGSize(width: 18, height: 18)

    static let screens: [CGSize] = [
        CGSize(width: 1280, height: 800), CGSize(width: 1440, height: 900),
        CGSize(width: 1512, height: 982), CGSize(width: 1728, height: 1117),
        CGSize(width: 1920, height: 1080), CGSize(width: 2240, height: 1260),
        CGSize(width: 2560, height: 1440), CGSize(width: 3440, height: 1440),
        CGSize(width: 3840, height: 2160), CGSize(width: 6016, height: 3384),
        CGSize(width: 1080, height: 1920),   // portrait
    ]

    /// Zoom like the overlay does: the box between two keys, made legible.
    static func zoom(_ g: Grid, _ a: (Int, Int), _ b: (Int, Int), screen: CGSize) -> Grid {
        Grid(rect: g.span(from: a, to: b)).legible(minCell: minCell, within: CGRect(origin: .zero, size: screen))
    }

    static func isFinal(_ g: Grid, _ screen: CGSize, levels: Int = 2) -> Bool {
        g.isFinal(screen: screen, levels: levels, slack: 1.5)
    }

    /// The normal path — a key twice or two neighbouring keys, then any pair
    /// (A A → A B) — is exactly two levels on every screen: level 1 zooms,
    /// level 2 clicks.
    static func normalPathIsTwoLevels() {
        let firstPairs: [((Int, Int), (Int, Int))] = [
            ((2, 0), (2, 0)),   // A A
            ((2, 3), (2, 3)),   // F F
            ((0, 9), (0, 9)),   // 0 0 (corner)
            ((2, 0), (2, 1)),   // A S
            ((1, 4), (2, 4)),   // T G
            ((2, 3), (1, 4)),   // F T (diagonal neighbours)
        ]
        for screen in screens {
            let top = Grid(rect: CGRect(origin: .zero, size: screen))
            check(!isFinal(top, screen), "\(screen): level 1 zooms")
            for (a, b) in firstPairs {
                let l2 = zoom(top, a, b, screen: screen)
                check(isFinal(l2, screen), "\(screen): \(a)→\(b) then any pair clicks on level 2")
            }
        }
    }

    /// A wide span (A L) makes level-2 cells too coarse, so one more level is
    /// added — and that level clicks. (Landscape only: on a portrait screen
    /// last-level cells are so tall that the diagonal check lets A L click.)
    static func wideSpanAddsOneLevel() {
        for screen in screens where screen.width > screen.height {
            let top = Grid(rect: CGRect(origin: .zero, size: screen))
            let l2 = zoom(top, (2, 0), (2, 8), screen: screen)
            check(!isFinal(l2, screen), "\(screen): A L → level 2 zooms")
            let l3 = zoom(l2, (2, 0), (2, 1), screen: screen)
            check(isFinal(l3, screen), "\(screen): A L → A S → level 3 clicks")
        }
    }

    /// `levels 3` makes the normal path three levels.
    static func moreLevelsSetting() {
        let screen = CGSize(width: 2240, height: 1260)
        let top = Grid(rect: CGRect(origin: .zero, size: screen))
        let l2 = zoom(top, (2, 0), (2, 0), screen: screen)
        check(!isFinal(l2, screen, levels: 3), "levels 3: level 2 zooms")
        let l3 = zoom(l2, (2, 0), (2, 0), screen: screen)
        check(isFinal(l3, screen, levels: 3), "levels 3: level 3 clicks")
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
        check(up.focus == CGPoint(x: 120, y: 220), "E ↑ clicks a quarter of the way down E")
        check(KeyLayout.arrows[126] == .up && KeyLayout.arrows[123] == .left, "arrow key codes")
    }
}
