import CoreGraphics

// Scroll anchor, scroll distances and wheel steps. Run with:  ./build.sh test

extension GridTests {
    static func scrollTests() {
        anchorSetsMovesAndDrops()
        keysScrollByTheirDistanceFromTheAnchor()
        wheelStepsAddUp()
        wheelStepsRunTheOtherWay()
    }

    static func anchorSetsMovesAndDrops() {
        let q = CGPoint(x: 50, y: 150), z = CGPoint(x: 50, y: 350)
        check(Scroll.anchor(nil, pressedAt: q) == q, "⌃ + key sets the anchor")
        check(Scroll.anchor(q, pressedAt: z) == z, "⌃ + another key moves it")
        check(Scroll.anchor(q, pressedAt: q) == nil, "⌃ + the anchor's own key drops it")
    }

    static func keysScrollByTheirDistanceFromTheAnchor() {
        let g = Grid(rect: rect)   // cells 100 × 100
        func centre(_ row: Int, _ col: Int, in g: Grid = g) -> CGPoint {
            let c = g.cell(row: row, col: col)
            return CGPoint(x: c.midX, y: c.midY)
        }
        let q = centre(1, 0)
        check(Scroll.delta(from: q, to: centre(3, 0)) == CGVector(dx: 0, dy: 200), "anchor Q, Z = two rows down")
        check(Scroll.delta(from: q, to: centre(0, 0)) == CGVector(dx: 0, dy: -100), "1 = a row up")
        check(Scroll.delta(from: q, to: centre(1, 3)) == CGVector(dx: 300, dy: 0), "R = three columns right")
        check(Scroll.delta(from: q, to: centre(2, 1)) == CGVector(dx: 100, dy: 100), "S = down and right")
        check(Scroll.delta(from: q, to: q) == nil, "the anchor's own key doesn't scroll")
        // A shifted grid moves the keys but not the anchor.
        let s = g.shifted(.down, by: 0.5)
        check(Scroll.delta(from: q, to: centre(2, 0, in: s)) == CGVector(dx: 0, dy: 150), "shifted: A is half a row further")
        check(Scroll.delta(from: q, to: centre(3, 0, in: s)) == CGVector(dx: 0, dy: -150), "shifted: Z wrapped to the top scrolls up")
    }

    static func wheelStepsAddUp() {
        for delta in [CGVector(dx: 0, dy: 540), CGVector(dx: -576, dy: 0), CGVector(dx: 7, dy: -3),
                      CGVector(dx: 33.4, dy: 66.6), CGVector(dx: 0, dy: 0)] {
            let steps = Scroll.wheelSteps(delta, count: 10)
            check(steps.count == 10, "\(delta): ten events")
            check(steps.reduce(0) { $0 + Int($1.wheel1) } == -Int(delta.dy.rounded()), "\(delta): vertical adds up")
            check(steps.reduce(0) { $0 + Int($1.wheel2) } == -Int(delta.dx.rounded()), "\(delta): horizontal adds up")
            let most = Int((max(abs(delta.dx), abs(delta.dy)) / 10).rounded(.up)) + 1
            check(steps.allSatisfy { abs(Int($0.wheel1)) <= most && abs(Int($0.wheel2)) <= most },
                  "\(delta): spread evenly, no big jump")
        }
        check(Scroll.wheelSteps(CGVector(dx: 0, dy: 1), count: 1).map(\.wheel1) == [-1], "one event")
    }

    /// The view moving down (what's further down comes into view) is a negative wheel1;
    /// moving right, a negative wheel2.
    static func wheelStepsRunTheOtherWay() {
        let down = Scroll.wheelSteps(CGVector(dx: 0, dy: 100), count: 10)
        check(down.allSatisfy { $0.wheel1 == -10 && $0.wheel2 == 0 }, "down = wheel1 negative")
        let up = Scroll.wheelSteps(CGVector(dx: 0, dy: -100), count: 10)
        check(up.allSatisfy { $0.wheel1 == 10 }, "up = wheel1 positive")
        let right = Scroll.wheelSteps(CGVector(dx: 100, dy: 0), count: 10)
        check(right.allSatisfy { $0.wheel2 == -10 && $0.wheel1 == 0 }, "right = wheel2 negative")
        let left = Scroll.wheelSteps(CGVector(dx: -100, dy: 0), count: 10)
        check(left.allSatisfy { $0.wheel2 == 10 }, "left = wheel2 positive")
    }
}
