import AppKit
import CoreGraphics

/// Global keyboard hook. Detects a lone tap of ⌘ to toggle the overlay, and
/// while the overlay is up it swallows key presses so they don't reach the
/// app underneath.
final class KeyTap {
    private let overlay: OverlayController
    private var port: CFMachPort?
    private var mouseMonitor: Any?

    // ⌘-tap detection
    private var cmdCandidate = false
    private var cmdDownAt: TimeInterval = 0
    private let tapMaxDuration: TimeInterval = 0.35
    /// ⌘ taps within this window of a tap-click turn it into a double / triple-click.
    private let doubleTapWindow: TimeInterval = 0.3
    /// When the last tap-triggered click happened (for double/triple-click).
    private var lastClickTapAt: TimeInterval = 0

    /// Lone modifier taps while the grid is open: ⌃ highlight (Tab cycles the button).
    /// ⌃ may be tapped with ⇧ held.
    private var modifierTaps: [(tap: ModifierTap, action: (OverlayController) -> Void)] = [
        (ModifierTap(codes: [KeyLayout.leftControl, KeyLayout.rightControl], flag: .maskControl,
                     allowed: .maskShift), { $0.modeTapped(.highlight) }),
    ]

    /// Key codes whose keyDown we swallowed; swallow the matching keyUp too.
    private var swallowed = Set<CGKeyCode>()

    init(overlay: OverlayController) {
        self.overlay = overlay
    }

    var isRunning: Bool { port != nil }

    func start() -> Bool {
        if port != nil { return true }
        // Keyboard only — pointer events (mouse, trackpad, Wacom pen) never pass
        // through this tap, so we can't delay or alter them.
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let me = Unmanaged<KeyTap>.fromOpaque(refcon!).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.port = port
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        // Listen-only monitor for clicks: a real click cancels a pending ⌘ tap / the overlay.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self else { return }
            self.cmdCandidate = false
            if self.overlay.isActive { self.overlay.cancel() }
        }
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return pass

        case .flagsChanged:
            handleFlags(event)
            return pass

        case .keyDown:
            cmdCandidate = false
            for i in modifierTaps.indices { modifierTaps[i].tap.candidate = false }
            guard overlay.isActive else { return pass }
            let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            swallowed.insert(code)
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                overlay.handleKey(code, flags: event.flags)
            }
            return nil

        case .keyUp:
            let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            if swallowed.remove(code) != nil { return nil }
            return overlay.isActive ? nil : pass

        default:
            return pass
        }
    }

    private func handleFlags(_ event: CGEvent) {
        let code = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        if overlay.isActive {
            // Use this event's flags: NSEvent.modifierFlags can lag behind inside the tap.
            overlay.modifiersChanged(flags)
        }

        let now = ProcessInfo.processInfo.systemUptime

        if let i = modifierTaps.firstIndex(where: { $0.tap.codes.contains(code) }) {
            cmdCandidate = false
            // Any other modifier changing means those aren't lone taps.
            for j in modifierTaps.indices where j != i { modifierTaps[j].tap.candidate = false }
            if modifierTaps[i].tap.changed(flags: flags, now: now, active: overlay.isActive) {
                modifierTaps[i].action(overlay)
            }
            return
        }
        for i in modifierTaps.indices { modifierTaps[i].tap.candidate = false }

        guard code == KeyLayout.leftCommand || code == KeyLayout.rightCommand else {
            // Some other modifier changed while ⌘ was down → not a lone tap.
            cmdCandidate = false
            return
        }

        if flags.contains(.maskCommand) {
            // ⇧ / ⌥ are allowed; other modifiers aren't.
            let others: CGEventFlags = [.maskControl, .maskSecondaryFn]
            cmdCandidate = flags.intersection(others).isEmpty
            cmdDownAt = now
        } else {
            if cmdCandidate && now - cmdDownAt <= tapMaxDuration {
                if now - lastClickTapAt <= doubleTapWindow && !overlay.isActive
                    && overlay.repeatLastClick() {
                    // 3rd / 4th tap: turn the click into a double / triple-click.
                    lastClickTapAt = now
                } else if overlay.isActive {
                    // Grid up: click where the mouse is (it sits on the current box).
                    lastClickTapAt = now
                    overlay.clickAtMouse(button: overlay.currentButton)
                } else {
                    overlay.show()
                }
            }
            cmdCandidate = false
        }
    }
}

