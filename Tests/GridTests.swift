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
        // (Slides by a fraction of a cell, as the arrows do.)
        evenGrid()
        offsetRect()
        selectionIsCell()
        selectionWithArrowIsHalf()
        twoKeysReachLastLevelCell()
        legibleLeavesBigGridsAlone()
        legibleGrowsAroundFocus()
        legibleStaysOnScreen()
        arrowHalves()
        inclusiveDragWidensOutward()
        repeatedArrowHalvesAgain()
        arrowsStack()
        arrowsDescribed()
        smallPicksClickAtOnce()
        nudgeMovesTheSlot()
        shiftSlidesTheGrid()
        zoomScalesTheGrid()
        buttonTests()

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
        let e = g.cell(row: 1, col: 2)!
        for d: Grid.Direction in [.up, .down, .left, .right] {
            check(g.selection(row: 1, col: 2, arrows: [d]) == Grid.half(of: e, toward: d), "\(d) E = that half of E")
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
            let l2 = Grid(rect: top.selection(row: 2, col: 3)!)
            let target = Grid(rect: l2.selection(row: 2, col: 6)!)
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

    static func repeatedArrowHalvesAgain() {
        let g = Grid(rect: rect)
        let e = g.cell(row: 1, col: 2)!   // 100 × 100 at (200, 100)
        check(g.selection(row: 1, col: 2, arrows: [.up]) == Grid.half(of: e, toward: .up), "one arrow = half")
        check(g.selection(row: 1, col: 2, arrows: [.up, .up])
              == CGRect(x: 200, y: 100, width: 100, height: 25), "↑ ↑ E = top quarter")
        check(g.selection(row: 1, col: 2, arrows: [.down, .down])
              == CGRect(x: 200, y: 175, width: 100, height: 25), "↓ ↓ E = bottom quarter")
        check(g.selection(row: 1, col: 2, arrows: [.right, .right, .right])
              == CGRect(x: 287.5, y: 100, width: 12.5, height: 100), "→ → → E = right eighth")
    }

    static func arrowsStack() {
        let g = Grid(rect: rect)   // E = 100 × 100 at (200, 100)
        check(g.selection(row: 1, col: 2, arrows: [.up, .left])
              == CGRect(x: 200, y: 100, width: 50, height: 50), "↑ ← E = top-left quarter")
        check(g.selection(row: 1, col: 2, arrows: [.up, .down])
              == CGRect(x: 200, y: 125, width: 100, height: 25), "↑ ↓ E = 2nd quarter from top")
        check(g.selection(row: 1, col: 2, arrows: [.down, .up, .down])
              == CGRect(x: 200, y: 162.5, width: 100, height: 12.5), "↓ ↑ ↓ E = 6th eighth")
        check(g.selection(row: 1, col: 2, arrows: [.up, .left])
              == g.selection(row: 1, col: 2, arrows: [.left, .up]), "axes don't depend on order")

        check(Grid.push(.up, onto: [.up, .down]) == [.up, .down, .up], "push stacks")
        check(Grid.push(.left, onto: [.up, .down, .up]) == [.up, .down, .up, .left], "other axis still free")
        check(Grid.push(.down, onto: [.up, .down, .up]) == [.up, .down, .up, .down], "4th arrow = a sixteenth")
        check(Grid.push(.down, onto: [.up, .down, .up, .down]) == nil, "an axis stops at a sixteenth")
    }

    static func smallPicksClickAtOnce() {
        check(Grid.isClickSize(CGRect(x: 0, y: 0, width: 20, height: 24), size: 24), "≤ size both ways clicks")
        check(Grid.isClickSize(CGRect(x: 0, y: 0, width: 20, height: 300), size: 24), "narrow enough clicks")
        check(Grid.isClickSize(CGRect(x: 0, y: 0, width: 300, height: 10), size: 24), "short enough clicks")
        check(!Grid.isClickSize(CGRect(x: 0, y: 0, width: 30, height: 30), size: 24), "too big both ways zooms")
        // A 1920 × 1080 screen: an F cell is 192 × 270; ← ← ← ↑ ↑ ↑ ↑ gets it to 24 × ~17.
        let g = Grid(rect: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let pick = g.selection(row: 2, col: 3, arrows: [.left, .left, .left, .up, .up, .up, .up])!
        check(Grid.isClickSize(pick, size: 24), "enough arrows on level 1 click at once")
    }

    static func arrowsDescribed() {
        check(Grid.describe([]) == "", "no arrows")
        check(Grid.describe([.up]) == "top half", "↑")
        check(Grid.describe([.down, .down]) == "bottom quarter", "↓ ↓")
        check(Grid.describe([.up, .down]) == "2nd quarter from top", "↑ ↓")
        check(Grid.describe([.down, .up]) == "3rd quarter from top", "↓ ↑")
        check(Grid.describe([.up, .left]) == "top half · left half", "↑ ←")
        check(Grid.describe([.right, .left, .right]) == "6th eighth from left", "→ ← →")
        check(Grid.describe([.up, .up, .down, .up]) == "3rd sixteenth from top", "↑ ↑ ↓ ↑")
        check(Grid.describe([.down, .up, .down, .down]) == "12th sixteenth from top", "↓ ↑ ↓ ↓")
        check(Grid.describe([.down, .down, .down, .down]) == "bottom sixteenth", "↓ ×4")
        check(Grid.describe([.down, .down, .down, .up]) == "15th sixteenth from top", "↓ ↓ ↓ ↑")
        check(Grid.describe([.down, .up, .up, .down]) == "10th sixteenth from top", "↓ ↑ ↑ ↓")
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

    static func shiftSlidesTheGrid() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 400)
        let g = Grid(rect: CGRect(x: 300, y: 100, width: 100, height: 100))   // cells 10 × 25
        check(g.shifted(toward: .right, within: screen)?.rect == CGRect(x: 310, y: 100, width: 100, height: 100),
              "⇧→ slides one cell right")
        check(g.shifted(toward: .up, within: screen)?.rect == CGRect(x: 300, y: 75, width: 100, height: 100),
              "⇧↑ slides one cell up")
        check(g.shifted(toward: .down, within: screen)?.focus == CGPoint(x: 350, y: 175), "focus moves with it")
        let edge = Grid(rect: CGRect(x: 5, y: 0, width: 100, height: 100))
        check(edge.shifted(toward: .left, within: screen)?.rect.minX == 0, "stops at the screen edge")
        check(edge.shifted(toward: .up, within: screen) == nil, "can't go past the edge")
        check(Grid(rect: screen).shifted(toward: .right, within: screen) == nil, "whole screen can't slide")
        // With overshoot the box goes past the edge, up to that many points (cells 10 × 25;
        // half a top-level cell of this screen is 50 × 50).
        let over = CGSize(width: 50, height: 50)
        var past = edge, steps = 0
        while let next = past.shifted(toward: .up, within: screen, overshoot: over) { past = next; steps += 1 }
        check(past.rect.minY == -50 && steps == 2, "↑ goes up to half a top-level cell past the edge (\(steps) steps)")
        check(edge.shifted(toward: .left, within: screen, fraction: 0.25, overshoot: over)?.rect.minX == 2.5,
              "⇧← a quarter cell past the edge")
        // Top level: cells slide half a cell and wrap around (cells 100 × 100).
        let top = Grid(rect: screen)
        let left = top.slid(toward: .left)
        check(left.rect == screen, "the grid still fills the screen")
        check(left.cell(row: 0, col: 4) == CGRect(x: 350, y: 0, width: 100, height: 100), "cells move half a cell")
        check(left.pieces(of: left.virtualCell(row: 0, col: 0)) == [CGRect(x: 950, y: 0, width: 50, height: 100),
                                                                     CGRect(x: 0, y: 0, width: 50, height: 100)],
              "Q's left half wraps to the right edge")
        check(left.cell(row: 0, col: 0) == CGRect(x: 0, y: 0, width: 50, height: 100), "a tie picks the home side")
        let twice = left.slid(toward: .left)
        check(twice.cell(row: 0, col: 0) == CGRect(x: 900, y: 0, width: 100, height: 100),
              "a whole cell left puts Q at the right edge")
        check(twice.cell(row: 0, col: 1) == CGRect(x: 0, y: 0, width: 100, height: 100), "and W at the left")
        var round = top
        for _ in 0..<20 { round = round.slid(toward: .right) }
        check(round == top, "a whole row's turn comes back to the start")
        check(top.slid(toward: .right).slid(toward: .left) == top, "and slides back")
        let fine = top.slid(toward: .right, fraction: 0.125)
        check(fine.cell(row: 0, col: 4) == CGRect(x: 412.5, y: 0, width: 100, height: 100), "⇧ slides an eighth of a cell")
        var eighths = top
        for _ in 0..<4 { eighths = eighths.slid(toward: .right, fraction: 0.125) }
        check(eighths == top.slid(toward: .right), "four eighths = one half-cell slide")
        check(g.shifted(toward: .right, within: screen, fraction: 0.25)?.rect.minX == 302.5,
              "zoomed in, ⇧ moves the box a quarter of a cell")
        let up = top.slid(toward: .up).slid(toward: .left)
        check(up.pieces(of: up.virtualCell(row: 0, col: 0)).count == 4, "a corner cell can split four ways")
        check(up.selection(row: 1, col: 1, arrows: [.down]) == CGRect(x: 50, y: 100, width: 100, height: 50),
              "arrows halve the slid cell")
    }

    static func zoomScalesTheGrid() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 400)   // cells 100 × 100
        let min = CGSize(width: 12, height: 12)
        let top = Grid(rect: screen)
        let zin = top.zoomed(by: 0.8, minCell: min)!
        check(zin.cellSize == CGSize(width: 80, height: 80), "+ makes the cells 0.8×")
        check(zin.box == CGRect(x: 100, y: 40, width: 800, height: 320), "around the screen's centre")
        check(zin.rect == screen && zin.period == screen.size, "and still wraps round the whole screen")
        let copies = zin.copies
        check(!copies.isEmpty && Grid(rect: screen).copies.isEmpty, "zoomed in, copies tile round the box")
        check(copies.contains { $0.row == 3 && $0.col == 9 && $0.rect == CGRect(x: 20, y: -40, width: 80, height: 80) },
              "the up-left copy's / sits just above-left of the box's Q")
        check(!copies.contains { $0.rect.intersects(zin.box.insetBy(dx: 1, dy: 1)) }, "no copy overlaps the live box")
        let back = zin.zoomed(by: 1.25, minCell: min)!
        check(back.scale == 1 && back.box == screen, "− zooms back out to exactly unzoomed")
        // Zoomed in, the box slides round the screen and wraps.
        let moved = zin.slid(toward: .right, by: CGSize(width: 150, height: 0))
        check(moved.pieces(of: moved.virtualCell(row: 0, col: 9)) == [CGRect(x: 970, y: 40, width: 30, height: 80),
                                                                       CGRect(x: 0, y: 40, width: 50, height: 80)],
              "a zoomed box wraps across the screen edge")
        check(moved.cell(row: 0, col: 9) == CGRect(x: 0, y: 40, width: 50, height: 80), "the key picks its bigger piece")
        check(moved.cell(row: 0, col: 0) == CGRect(x: 250, y: 40, width: 80, height: 80), "the rest moves with it")
        // Past the screen: cells bigger than a tenth, the box wrapping on its own size.
        let out = top.zoomed(by: 1.25, minCell: min)!
        check(out.cellSize == CGSize(width: 125, height: 125), "− keeps going past the screen")
        check(out.period == CGSize(width: 1250, height: 500), "the box repeats on its own size")
        check(out.cell(row: 1, col: 4) == CGRect(x: 375, y: 75, width: 125, height: 125),
              "zoomed out around the screen's centre")
        check(out.cell(row: 0, col: 0) == nil, "Q is pushed out of view")
        check(out.cell(row: 0, col: 1) == CGRect(x: 0, y: 0, width: 125, height: 75), "edge cells are cut to the screen")
        let away = out.slid(toward: .right, by: CGSize(width: 125, height: 0))
        check(away.cell(row: 0, col: 9) == nil, "a cell slid past the screen is out of view")
        let atF = top.zoomed(by: 0.8, minCell: min, around: (2, 3))!
        check(atF.cell(row: 2, col: 3) == CGRect(x: 310, y: 210, width: 80, height: 80),
              "⇧ + a key zooms in around that key's cell")
        let zinF = zin.zoomed(by: 0.8, minCell: min, around: (0, 0))!
        check(zinF.virtualCell(row: 0, col: 0).midX == zin.virtualCell(row: 0, col: 0).midX
              && zinF.virtualCell(row: 0, col: 0).midY == zin.virtualCell(row: 0, col: 0).midY,
              "zoomed in, that key's centre stays put too")
        var g = top, n = 0
        while let next = g.zoomed(by: 1.25, minCell: min) { g = next; n += 1 }
        check(abs(g.scale - Grid.maxScale) < 1e-6, "stops at a cell the size of the screen (\(n) steps)")
        g = top; n = 0
        while let next = g.zoomed(by: 0.8, minCell: min) { g = next; n += 1 }
        check(n == 9 && g.cellSize.width >= 12, "+ stops before cells get under 12pt (\(n) steps)")
    }

    static func nudgeMovesTheSlot() {
        check(Grid.nudge([.up], toward: .down) == [.down], "top half ⇧↓ = bottom half")
        check(Grid.nudge([.up, .up], toward: .down) == [.up, .down], "top quarter ⇧↓ = 2nd quarter")
        check(Grid.nudge([.up, .down], toward: .down) == [.down, .up], "2nd quarter ⇧↓ = 3rd quarter")
        check(Grid.nudge([.up, .left, .down], toward: .down) == [.down, .left, .up],
              "other axis keeps its place")
        check(Grid.nudge([.left], toward: .right) == [.right], "left half ⇧→ = right half")
        check(Grid.nudge([.down, .down], toward: .down) == nil, "bottom quarter can't go lower")
        check(Grid.nudge([.left], toward: .up) == nil, "no vertical arrows = nothing to nudge")
        check(Grid.nudge([], toward: .left) == nil, "no arrows = nothing to nudge")
    }
}

extension Grid {
    /// Slide by `fraction` of a cell (tests only).
    func slid(toward d: Direction, fraction f: CGFloat = 0.5) -> Grid {
        slid(toward: d, by: CGSize(width: cellSize.width * f, height: cellSize.height * f))
    }
}
