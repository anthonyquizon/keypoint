import CoreGraphics

// Mode choice (Tab / ⌥ / ⌃) and lone modifier-tap detection. Run with:  ./build.sh test

extension GridTests {
    static func buttonTests() {
        defaultsToLeft()
        heldModifiersPickButton()
        keyPressWithModifierSticks()
        modifiersPickKeyAction()
        tapsToggleAndExclude()
        tabCycles()
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
        check(c.current(held: .maskShift) == .left, "⇧ held = still left (it nudges)")
        check(c.current(held: .maskAlternate) == .highlight, "⌥ held = highlight")
        check(c.current(held: .maskControl) == .left, "⌃ held = still left (it scrolls)")
        check(c.current(held: .maskCommand) == .left, "⌘ held = still left")

        var m = ModeChoice()
        m.cycle()
        check(m.current(held: .maskAlternate) == .highlight, "held ⌥ shows over a Tab right")
        check(m.current(held: []) == .right, "released, back to the Tab mode")
    }

    static func keyPressWithModifierSticks() {
        var c = ModeChoice()
        c.keyPressed(flags: .maskShift)
        check(c.mode == .left, "⇧ + key picks no mode")
        c.keyPressed(flags: .maskControl)
        check(c.mode == .left, "⌃ + key picks no mode (it scrolls)")
        c.keyPressed(flags: .maskAlternate)
        check(c.mode == .highlight, "⌥ + key sticks after release")
        c.keyPressed(flags: [])
        check(c.mode == .highlight, "a later plain key keeps it")

        var tab = ModeChoice()
        tab.cycle()
        tab.keyPressed(flags: .maskAlternate)
        check(tab.mode == .highlight, "⌥ + key overrides a Tab right")
    }

    static func modifiersPickKeyAction() {
        check(KeyAction(flags: [], clicks: false) == .zoom, "plain key zooms")
        check(KeyAction(flags: [], clicks: true) == .click, "plain key clicks on the last level")
        check(KeyAction(flags: .maskCommand, clicks: false) == .click, "⌘ + key clicks now")
        check(KeyAction(flags: .maskControl, clicks: true) == .anchor, "⌃ + key sets the anchor, even on the last level")
        check(KeyAction(flags: .maskShift, clicks: true) == .move, "⇧ + key moves the mouse, even on the last level")
        check(KeyAction(flags: [.maskCommand, .maskShift, .maskControl], clicks: false) == .click, "⌘ beats ⌃ and ⇧")
        check(KeyAction(flags: [.maskControl, .maskShift], clicks: false) == .anchor, "⌃ beats ⇧")
        check(KeyAction(flags: [], clicks: false, anchored: true) == .scroll, "anchored: a plain key scrolls")
        check(KeyAction(flags: [], clicks: true, anchored: true) == .scroll, "anchored: even on the last level")
        check(KeyAction(flags: .maskControl, clicks: false, anchored: true) == .anchor, "anchored: ⌃ + key moves the anchor")
        check(KeyAction(flags: .maskCommand, clicks: false, anchored: true) == .click, "anchored: ⌘ + key still clicks")
        check(KeyAction(flags: .maskShift, clicks: false, anchored: true) == .move, "anchored: ⇧ + key still moves the mouse")
        check(KeyAction(flags: .maskAlternate, clicks: false) == .zoom, "⌥ + key still zooms (it picks highlight)")
    }

    static func tapsToggleAndExclude() {
        var c = ModeChoice()
        c.tapped(.highlight)
        check(c.mode == .highlight, "tap ⌥ = highlight on")
        c.tapped(.highlight)
        check(c.mode == .left, "tap ⌥ again = back to left")
        c.cycle()
        c.tapped(.highlight)
        check(c.mode == .highlight, "tap ⌥ overrides a Tab right")

        var held = ModeChoice()
        held.keyPressed(flags: .maskAlternate)
        held.tapped(.highlight)
        check(held.mode == .left, "tap ⌥ turns off a held-⌥ highlight")
    }

    static func tabCycles() {
        var c = ModeChoice()
        c.cycle()
        check(c.mode == .right, "Tab: left → right")
        c.cycle()
        check(c.mode == .middle, "Tab: right → middle")
        c.cycle()
        check(c.mode == .left, "Tab: middle → left")
        c.tapped(.highlight)
        c.cycle()
        check(c.mode == .right, "Tab from highlight = right")
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
        var option = ModifierTap(codes: [58, 61], flag: .maskAlternate, allowed: .maskShift)
        _ = option.changed(flags: [.maskAlternate, .maskShift], now: 0, active: true)
        check(option.changed(flags: .maskShift, now: 0.1, active: true), "⌥ tap with ⇧ held still counts")
    }

    static func inactiveGridIgnoresTaps() {
        var t = shiftTap
        _ = t.changed(flags: .maskShift, now: 0, active: false)
        check(!t.changed(flags: [], now: 0.1, active: false), "no tap while the grid is hidden")
    }
}
