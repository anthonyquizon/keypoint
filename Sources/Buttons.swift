import CoreGraphics
import Foundation

/// Which mouse button a click uses.
enum MouseButton { case left, right, middle }

/// What the next pick does: a left, right or middle click, or a highlight (drag).
enum ClickMode {
    case left, right, middle, highlight

    /// The button a click in this mode uses (a highlight drags with the left button).
    var button: MouseButton {
        switch self {
        case .left, .highlight: return .left
        case .right: return .right
        case .middle: return .middle
        }
    }

    /// The mode a modifier picks: ⇧ right, ⌃ highlight, ⌥ middle (⇧ ⌃ ⌥ order if several).
    static func picked(by flags: CGEventFlags) -> ClickMode? {
        if flags.contains(.maskShift) { return .right }
        if flags.contains(.maskControl) { return .highlight }
        if flags.contains(.maskAlternate) { return .middle }
        return nil
    }
}

/// The mode for the current pick. Any ⇧ / ⌃ / ⌥ overrides whatever mode is on:
/// held on a key press it switches to its mode (and that sticks); a lone tap
/// switches to its mode, or back to a left click if that mode was already on.
struct ModeChoice {
    private(set) var mode = ClickMode.left

    /// A key was pressed with these modifiers held.
    mutating func keyPressed(flags: CGEventFlags) {
        if let m = ClickMode.picked(by: flags) { mode = m }
    }

    /// A lone tap of the modifier for `m`.
    mutating func tapped(_ m: ClickMode) {
        mode = mode == m ? .left : m
    }

    /// The mode, counting modifiers held right now over the chosen one.
    func current(held: CGEventFlags = []) -> ClickMode {
        ClickMode.picked(by: held) ?? mode
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
