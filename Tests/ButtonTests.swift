import CoreGraphics

// Button choice (⇧ / ⌥) and lone modifier-tap detection. Run with:  ./build.sh test

extension GridTests {
    static func buttonTests() {
        defaultsToLeft()
        heldModifiersPickButton()
        keyPressWithModifierSticks()
        tapsToggleAndExclude()
        loneTapFires()
        slowPressIsNotATap()
        chordIsNotATap()
        interruptedTapDoesNotFire()
        allowedModifierStillTaps()
        inactiveGridIgnoresTaps()
    }

    static func defaultsToLeft() {
        check(ButtonChoice().button() == .left, "nothing chosen = left")
    }

    static func heldModifiersPickButton() {
        let c = ButtonChoice()
        check(c.button(held: .maskShift) == .right, "⇧ held = right")
        check(c.button(held: .maskAlternate) == .middle, "⌥ held = middle")
        check(c.button(held: [.maskShift, .maskAlternate]) == .right, "⇧ beats ⌥")
        check(c.button(held: .maskCommand) == .left, "⌘ held = still left")
    }

    static func keyPressWithModifierSticks() {
        var c = ButtonChoice()
        c.keyPressed(flags: .maskShift)
        check(c.button() == .right, "⇧ + key sticks after release")
        c.keyPressed(flags: [])
        check(c.button() == .right, "a later plain key keeps it")

        var m = ButtonChoice()
        m.keyPressed(flags: .maskAlternate)
        check(m.button() == .middle, "⌥ + key sticks after release")
    }

    static func tapsToggleAndExclude() {
        var c = ButtonChoice()
        c.toggleRight()
        check(c.button() == .right, "tap ⇧ = right on")
        c.toggleRight()
        check(c.button() == .left, "tap ⇧ again = off")

        c.toggleMiddle()
        check(c.button() == .middle, "tap ⌥ = middle on")
        c.toggleRight()
        check(c.button() == .right && !c.middle, "tap ⇧ switches middle → right")
        c.toggleMiddle()
        check(c.button() == .middle && !c.right, "tap ⌥ switches right → middle")

        var held = ButtonChoice()
        held.keyPressed(flags: .maskAlternate)
        held.toggleMiddle()
        check(held.button() == .left, "tap ⌥ turns off a held-⌥ middle")
    }

    static let shiftTap = ModifierTap(codes: [56, 60], flag: .maskShift)

    static func loneTapFires() {
        var t = shiftTap
        check(!t.changed(flags: .maskShift, now: 0, active: true), "press alone doesn't fire")
        check(t.changed(flags: [], now: 0.1, active: true), "quick release fires")
        check(!t.changed(flags: [], now: 0.2, active: true), "a second release doesn't fire again")
    }

    static func slowPressIsNotATap() {
        var t = shiftTap
        _ = t.changed(flags: .maskShift, now: 0, active: true)
        check(!t.changed(flags: [], now: 0.5, active: true), "held too long = no tap")
    }

    static func chordIsNotATap() {
        var t = shiftTap
        _ = t.changed(flags: [.maskShift, .maskCommand], now: 0, active: true)
        check(!t.changed(flags: .maskCommand, now: 0.1, active: true), "⇧ with ⌘ = chord, no tap")
    }

    static func interruptedTapDoesNotFire() {
        // KeyTap clears the candidate when a key or another modifier comes in between.
        var t = shiftTap
        _ = t.changed(flags: .maskShift, now: 0, active: true)
        t.candidate = false
        check(!t.changed(flags: [], now: 0.1, active: true), "⇧ + key = hold, not a tap")
    }

    static func allowedModifierStillTaps() {
        var ctrl = ModifierTap(codes: [59, 62], flag: .maskControl, allowed: .maskShift)
        _ = ctrl.changed(flags: [.maskControl, .maskShift], now: 0, active: true)
        check(ctrl.changed(flags: .maskShift, now: 0.1, active: true), "⌃ tap with ⇧ held still counts")
    }

    static func inactiveGridIgnoresTaps() {
        var t = shiftTap
        _ = t.changed(flags: .maskShift, now: 0, active: false)
        check(!t.changed(flags: [], now: 0.1, active: false), "no tap while the grid is hidden")
    }
}
