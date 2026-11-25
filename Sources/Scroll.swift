import CoreGraphics

/// Scrolling from an anchor: ⌥ + a key sets it, and while it's set each key scrolls
/// the view by how far that key is from it.
enum Scroll {
    /// The anchor after ⌥ + a key at `point`: set or moved there, or dropped if it's
    /// already there.
    static func anchor(_ anchor: CGPoint?, pressedAt point: CGPoint) -> CGPoint? {
        anchor == point ? nil : point
    }

    /// How far a key at `point` scrolls the view (y down: a positive dy shows what's
    /// further down, so what was at `point` ends up at the anchor). Nil for the anchor's
    /// own key.
    static func delta(from anchor: CGPoint, to point: CGPoint) -> CGVector? {
        point == anchor ? nil : CGVector(dx: point.x - anchor.x, dy: point.y - anchor.y)
    }

    /// Wheel values that scroll the view by `delta`, split into `count` events (like a
    /// swipe) that add up to exactly the rounded delta. They run the other way to
    /// `delta`: a positive `wheel1` scrolls up, a positive `wheel2` scrolls left.
    static func wheelSteps(_ delta: CGVector, count: Int) -> [(wheel1: Int32, wheel2: Int32)] {
        var sent = (x: 0, y: 0)
        var steps: [(wheel1: Int32, wheel2: Int32)] = []
        for i in 1...count {
            let t = CGFloat(i) / CGFloat(count)
            let total = (x: Int((delta.dx * t).rounded()), y: Int((delta.dy * t).rounded()))
            steps.append((Int32(sent.y - total.y), Int32(sent.x - total.x)))
            sent = total
        }
        return steps
    }
}
