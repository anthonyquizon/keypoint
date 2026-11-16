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

    static func widths(_ e: [CGFloat]) -> [CGFloat] { zip(e, e.dropFirst()).map { $1 - $0 } }

    static let rect = CGRect(x: 0, y: 0, width: 1000, height: 400)

    static func main() {
        evenGrid()
        leanHigh()
        leanLowMirrorsHigh()
        noSkewMeansEven()
        leanToward()
        offsetRect()
        spanSameKeyIsCell()
        spanUsesCentres()
        spanMatchesOldEvenFormula()
        smallestAndLargestCell()
        clickRuleWTthenAS()
        clickRuleVerticalLean()
        clickRuleSmallGridStillDrills()
        clickRuleNoEndlessDrilling()
        clickRuleEvenGridUnchanged()
        clickRuleWideSpanZooms()
        legibleLeavesBigGridsAlone()
        legibleFlattensBeforeGrowing()
        legibleKeepsLeanOnNarrowPair()
        legibleNarrowPairDrillStops()
        legibleGrowsAroundFocus()
        legibleStaysOnScreen()
        legibleStopsDrilling()

        print(failures == 0 ? "OK — \(checks) checks passed" : "\(failures) of \(checks) checks failed")
        if failures > 0 { exit(1) }
    }

    static func evenGrid() {
        let g = Grid(rect: rect)
        check(g.columnEdges == (0...10).map { CGFloat($0) * 100 }, "even column edges")
        check(g.rowEdges == [0, 100, 200, 300, 400], "even row edges")
    }

    static func leanHigh() {
        let g = Grid(rect: rect, leanX: .high, skew: 3)
        let w = widths(g.columnEdges)
        close(w.first! / w.last!, 3, "largest ÷ smallest = skew")
        close(w.reduce(0, +), 1000, "widths fill the rect")
        check(w == w.sorted(by: >), "columns shrink toward the last column")
        check(g.columnEdges.first == 0 && g.columnEdges.last == 1000, "edges pinned to rect")
        check(g.rowEdges == Grid(rect: rect).rowEdges, "other axis stays even")
    }

    static func leanLowMirrorsHigh() {
        let hi = Grid(rect: rect, leanX: .high, skew: 3)
        let lo = Grid(rect: rect, leanX: .low, skew: 3)
        for (a, b) in zip(hi.columnEdges, lo.columnEdges.reversed()) {
            close(a, 1000 - b, "low lean mirrors high")
        }
    }

    static func noSkewMeansEven() {
        let even = Grid(rect: rect)
        check(Grid(rect: rect, leanX: .high, skew: 1) == even, "skew 1 → even")
        check(Grid(rect: rect, leanX: .none, leanY: .none, skew: 3) == even, "no lean → even")
    }

    static func leanToward() {
        check(Grid.Lean.toward(8, from: 0) == .high, "A→L leans high")
        check(Grid.Lean.toward(0, from: 8) == .low, "L→A leans low")
        check(Grid.Lean.toward(3, from: 3) == .none, "same column → no lean")
    }

    static func offsetRect() {
        let r = CGRect(x: 200, y: 50, width: 300, height: 80)
        let g = Grid(rect: r, leanX: .high, leanY: .low, skew: 2)
        check(g.columnEdges.first == 200 && g.columnEdges.last == 500, "column edges offset")
        check(g.rowEdges.first == 50 && g.rowEdges.last == 130, "row edges offset")
        let h = widths(g.rowEdges)
        check(h == h.sorted(by: <), "rows shrink toward row 0 when leaning low")
    }

    static func spanSameKeyIsCell() {
        let g = Grid(rect: rect, leanX: .high, skew: 3)
        for (r, c) in [(0, 0), (2, 5), (3, 9)] {
            check(g.span(from: (r, c), to: (r, c)) == g.cell(row: r, col: c), "same key \(r),\(c) = its cell")
        }
    }

    static func spanUsesCentres() {
        let g = Grid(rect: rect, leanX: .high, skew: 3)
        let s = g.span(from: (1, 0), to: (1, 9))
        let e = g.columnEdges
        close(s.minX, (e[0] + e[1]) / 2, "span starts at first key's centre")
        close(s.maxX, (e[9] + e[10]) / 2, "span ends at second key's centre")
        check(g.span(from: (1, 9), to: (1, 0)) == s, "box doesn't depend on order")
    }

    /// The even-grid box must match the pre-skew formula for every key pair:
    /// span between cell centres, any axis thinner than a cell padded to one
    /// cell centred on the keys.
    static func spanMatchesOldEvenFormula() {
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
        check(mismatches == 0, "even span matches old formula for all 1600 pairs (\(mismatches) differ)")
    }

    // MARK: - Click vs zoom

    static let screen = CGSize(width: 2240, height: 1260)
    static let top = Grid(rect: CGRect(origin: .zero, size: screen))

    /// The level-2 grid after pressing `a` then `b` on the full screen.
    static func after(_ a: (Int, Int), _ b: (Int, Int), skew: CGFloat) -> Grid {
        Grid(rect: top.span(from: a, to: b),
             leanX: .toward(b.1, from: a.1), leanY: .toward(b.0, from: a.0), skew: skew)
    }

    static func clicks(_ g: Grid, row: Int, col: Int) -> Bool {
        g.isClickable(g.cell(row: row, col: col).size, screen: screen, levels: 2, slack: 1.5)
    }

    /// Regression: W T → A S clicked although A and S were the wide bail-out
    /// cells (they passed the diagonal check alone).
    static func clickRuleWTthenAS() {
        let g = after((1, 1), (1, 4), skew: 2)
        let a = g.cell(row: 2, col: 0).size
        check(hypot(a.width, a.height) <= hypot(screen.width / 100, screen.height / 16) * 1.5,
              "A passes the diagonal check alone (the original bug)")
        check(!clicks(g, row: 2, col: 0), "W T → A zooms")
        check(!clicks(g, row: 2, col: 1), "W T → S zooms")
        check(clicks(g, row: 2, col: 9), "W T → ; (fine end) clicks")
        let row = (0..<10).map { clicks(g, row: 2, col: $0) }
        check(row == [false, false, false, false, true, true, true, true, true, true],
              "W T: coarse four zoom, rest click — got \(row)")
    }

    /// Regression: 2 W → 2 3 clicked although row 0 was visibly the tall
    /// bail-out row (it was under last-level height × slack).
    static func clickRuleVerticalLean() {
        let g = after((0, 1), (1, 1), skew: 2)
        check(!clicks(g, row: 0, col: 1), "2 W → 2 zooms")
        check(!clicks(g, row: 0, col: 2), "2 W → 3 zooms")
        check(clicks(g, row: 3, col: 1), "2 W → X (fine end) clicks")
    }

    /// Small coarse cells drill down too — width alone tells you.
    static func clickRuleSmallGridStillDrills() {
        let g = after((2, 3), (2, 4), skew: 2)
        check(!clicks(g, row: 2, col: 0), "F G → A zooms")
        check(clicks(g, row: 2, col: 9), "F G → ; clicks")
    }

    /// The extra level (and deeper) never drills again: its cells are already
    /// below a normal last-level cell, even when they lean.
    static func clickRuleNoEndlessDrilling() {
        let l2 = after((1, 1), (1, 4), skew: 2)
        let l3 = Grid(rect: l2.span(from: (2, 0), to: (2, 1)), leanX: .high, skew: 2)
        check((0..<4).allSatisfy { r in (0..<10).allSatisfy { clicks(l3, row: r, col: $0) } },
              "W T → A S → every cell clicks")
    }

    /// Without skew the rule is the plain diagonal check, as before.
    static func clickRuleEvenGridUnchanged() {
        for (a, b) in [((1, 1), (1, 4)), ((2, 3), (2, 4)), ((0, 0), (3, 2))] {
            let g = after(a, b, skew: 1)
            let c = g.cell(row: 0, col: 0).size
            let old = hypot(c.width, c.height) <= hypot(screen.width / 100, screen.height / 16) * 1.5
            check(clicks(g, row: 0, col: 0) == old, "even grid after \(a)→\(b) matches diagonal rule")
        }
        check(clicks(after((1, 1), (1, 4), skew: 1), row: 2, col: 0), "W T → A clicks with skew off")
    }

    /// A wide span is too coarse everywhere, so it zooms whatever the skew.
    static func clickRuleWideSpanZooms() {
        let g = after((2, 0), (2, 8), skew: 2)
        check(!(0..<10).contains { clicks(g, row: 2, col: $0) }, "A L: every cell zooms")
    }

    // MARK: - Minimum cell size

    static let minCell = CGSize(width: 18, height: 18)
    static let bounds = CGRect(origin: .zero, size: screen)

    /// Last-level cell on this screen at 2 levels: 22.4 × 78.75.
    static let base = Grid.lastLevelCell(screen: screen, levels: 2)

    static func legible(_ g: Grid) -> Grid {
        g.legible(minCell: minCell, within: bounds, lastLevelCell: base)
    }

    static func legibleLeavesBigGridsAlone() {
        let g = after((1, 1), (1, 4), skew: 2)   // cells ≥ 46 × 78
        check(legible(g) == g, "big enough → unchanged")
    }

    /// Rows 80 tall with skew 3: finest row ≈ 11pt, even 20pt, and even is
    /// well under a last-level row (78.75) — so flatten, no growing.
    static func legibleFlattensBeforeGrowing() {
        let r = CGRect(x: 500, y: 500, width: 400, height: 80)
        let g = Grid(rect: r, leanY: .high, skew: 3)
        check(g.smallestCell.height < 18, "precondition: finest row too small")
        let l = legible(g)
        check(l.rect == r, "rect unchanged")
        check(l.leanY == .none, "y lean dropped")
        check(l.rowEdges == Grid(rect: r).rowEdges, "y now even")
    }

    /// Regression: 8 9 lost its lean — the level-2 box is one cell wide, so
    /// the finest column (≈15.5) was under the minimum and got flattened.
    /// Now it keeps the lean and grows just enough.
    static func legibleKeepsLeanOnNarrowPair() {
        let g = after((0, 7), (0, 8), skew: 2)
        check(g.smallestCell.width < 18, "precondition: finest column too small")
        let l = legible(g)
        check(l.leanX == .high, "8 9 keeps leaning toward 9")
        close(l.smallestCell.width, 18, "finest column grown to the minimum")
        close(l.rect.width, g.rect.width * 18 / g.smallestCell.width, "grown only as needed")
        close(l.rect.midX, g.rect.midX, "centred on the selection")
        check(!clicks(l, row: 0, col: 0), "8 9 → 1 (coarse) zooms")
        check(clicks(l, row: 0, col: 9), "8 9 → 0 (fine) clicks")
    }

    /// Drilling from 8 9's coarse end gives a level that's flattened and
    /// clicks everywhere — the lean doesn't make it drill forever.
    static func legibleNarrowPairDrillStops() {
        let l2 = legible(after((0, 7), (0, 8), skew: 2))
        let raw = Grid(rect: l2.span(from: (0, 0), to: (0, 1)), leanX: .high, skew: 2)
        let l3 = legible(raw)
        check(l3.leanX == .none, "level 3 flattened")
        check((0..<4).allSatisfy { r in (0..<10).allSatisfy { clicks(l3, row: r, col: $0) } },
              "level 3: every cell clicks")
    }

    static func legibleGrowsAroundFocus() {
        let r = CGRect(x: 1000, y: 600, width: 50, height: 20)
        let g = Grid(rect: r, leanX: .high, leanY: .low, skew: 2)
        let l = legible(g)
        close(l.rect.width, 180, "grown to 10 × 18")
        close(l.rect.height, 72, "grown to 4 × 18")
        close(l.rect.midX, r.midX, "centred on selection (x)")
        close(l.rect.midY, r.midY, "centred on selection (y)")
        check(l.focus == CGPoint(x: r.midX, y: r.midY), "focus unchanged")
        close(l.smallestCell.width, 18, "every column ≥ min")
        close(l.smallestCell.height, 18, "every row ≥ min")
    }

    /// Near the menu bar: grows down instead of off-screen, keeps the focus.
    static func legibleStaysOnScreen() {
        let r = CGRect(x: 2230, y: 0, width: 10, height: 6)
        let l = legible(Grid(rect: r))
        check(l.rect.minY == 0 && l.rect.maxX == 2240, "pinned to the screen corner")
        close(l.rect.width, 180, "full width still")
        check(l.focus == CGPoint(x: r.midX, y: r.midY), "focus still on the selection")
    }

    /// The extra level after W T → A S is unreadably fine; once legible,
    /// every cell clicks (no endless drilling).
    static func legibleStopsDrilling() {
        let l2 = after((1, 1), (1, 4), skew: 2)
        let raw = Grid(rect: l2.span(from: (2, 0), to: (2, 1)), leanX: .high, skew: 2)
        check(raw.smallestCell.width < 18, "precondition: level 3 too fine to label")
        let l3 = legible(raw)
        check(l3.smallestCell.width >= 18 - 1e-9 && l3.smallestCell.height >= 18 - 1e-9, "level 3 labels fit")
        check((0..<4).allSatisfy { r in (0..<10).allSatisfy { clicks(l3, row: r, col: $0) } },
              "legible level 3: every cell clicks")
    }

    static func smallestAndLargestCell() {
        let even = Grid(rect: rect)
        check(even.smallestCell == CGSize(width: 100, height: 100), "even smallest cell")
        check(even.largestCell == CGSize(width: 100, height: 100), "even largest cell")

        let g = Grid(rect: rect, leanX: .high, skew: 3)
        let w = widths(g.columnEdges)
        close(g.smallestCell.width, w.last!, "smallest = fine end")
        close(g.largestCell.width, w.first!, "largest = coarse end")
        close(g.largestCell.width / g.smallestCell.width, 3, "ratio = skew")
    }
}
