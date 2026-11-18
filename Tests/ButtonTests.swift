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
        check(ModeChoice().current() == .left, "nothing chosen = left")
        check(ClickMode.highlight.button == .left, "highlight drags with the left button")
    }

    static func heldModifiersPickButton() {
        let c = ModeChoice()
        check(c.current(held: .maskShift) == .right, "⇧ held = right")
        check(c.current(held: .maskControl) == .highlight, "⌃ held = highlight")
        check(c.current(held: .maskAlternate) == .middle, "⌥ held = middle")
        check(c.current(held: .maskCommand) == .left, "⌘ held = still left")

        var m = ModeChoice()
        m.tapped(.middle)
        check(m.current(held: .maskShift) == .right, "held ⇧ shows over a tapped middle")
        check(m.current(held: []) == .middle, "released, back to the tapped mode")
    }

    static func keyPressWithModifierSticks() {
        var c = ModeChoice()
        c.keyPressed(flags: .maskShift)
        check(c.mode == .right, "⇧ + key sticks after release")
        c.keyPressed(flags: [])
        check(c.mode == .right, "a later plain key keeps it")
        c.keyPressed(flags: .maskAlternate)
        check(c.mode == .middle, "⌥ + key overrides right")
        c.keyPressed(flags: .maskControl)
        check(c.mode == .highlight, "⌃ + key overrides middle")
        c.keyPressed(flags: .maskShift)
        check(c.mode == .right, "⇧ + key overrides highlight")
    }

    static func tapsToggleAndExclude() {
        var c = ModeChoice()
        c.tapped(.right)
        check(c.mode == .right, "tap ⇧ = right on")
        c.tapped(.right)
        check(c.mode == .left, "tap ⇧ again = back to left")

        c.tapped(.middle)
        check(c.mode == .middle, "tap ⌥ = middle on")
        c.tapped(.highlight)
        check(c.mode == .highlight, "tap ⌃ overrides middle")
        c.tapped(.right)
        check(c.mode == .right, "tap ⇧ overrides highlight")

        var held = ModeChoice()
        held.keyPressed(flags: .maskControl)
        held.tapped(.highlight)
        check(held.mode == .left, "tap ⌃ turns off a held-⌃ highlight")
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
