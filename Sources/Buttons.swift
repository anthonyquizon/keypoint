import CoreGraphics
import Foundation

/// Which mouse button a click uses.
enum MouseButton { case left, right, middle }

/// The button chosen for the current pick: ⇧ = right, ⌥ = middle (⇧ wins).
/// Holding either on a key press sticks for the rest of the pick; a lone tap
/// toggles it, and turning one on turns the other off.
struct ButtonChoice {
    private(set) var right = false
    private(set) var middle = false

    /// A key was pressed with these modifiers held.
    mutating func keyPressed(flags: CGEventFlags) {
        if flags.contains(.maskShift) { right = true }
        if flags.contains(.maskAlternate) { middle = true }
    }

    mutating func toggleRight() {
        right.toggle()
        if right { middle = false }
    }

    mutating func toggleMiddle() {
        middle.toggle()
        if middle { right = false }
    }

    /// The button, counting modifiers held right now as well as earlier choices.
    func button(held: CGEventFlags = []) -> MouseButton {
        right || held.contains(.maskShift) ? .right
            : middle || held.contains(.maskAlternate) ? .middle : .left
    }
}

/// Detects a lone tap of one modifier while the grid is open: pressed and
/// released quickly with no key or other modifier (bar `allowed`) in between.
struct ModifierTap {
    let codes: Set<CGKeyCode>
    let flag: CGEventFlags
    var allowed: CGEventFlags = []
    var maxDuration: TimeInterval = 0.35
    /// Down and still a possible tap. Cleared when a key or other modifier intervenes.
    var candidate = false
    private var downAt: TimeInterval = 0

    init(codes: Set<CGKeyCode>, flag: CGEventFlags, allowed: CGEventFlags = []) {
        self.codes = codes
        self.flag = flag
        self.allowed = allowed
    }

    /// Feed a change of this modifier. Returns true when it completes a tap.
    mutating func changed(flags: CGEventFlags, now: TimeInterval, active: Bool) -> Bool {
        if flags.contains(flag) {
            let others = CGEventFlags([.maskCommand, .maskControl, .maskShift, .maskAlternate,
                                       .maskSecondaryFn]).subtracting([flag]).subtracting(allowed)
            candidate = active && flags.intersection(others).isEmpty
            downAt = now
            return false
        }
        defer { candidate = false }
        return candidate && active && now - downAt <= maxDuration
    }
}
