// DrawingPad — use the Mac trackpad as an absolute drawing surface.
// Touch the trackpad with one finger to draw; lift to end the stroke.
// Space or a two-finger tap clears the board. Cmd+Q quits.

import AppKit

final class PadView: NSView {
    private var strokes: [[CGPoint]] = []      // normalized 0...1 coordinates
    private var activeTouch: (NSObjectProtocol & NSCopying)?
    private let lineWidth: CGFloat = 9

    override init(frame: NSRect) {
        super.init(frame: frame)
        allowedTouchTypes = [.indirect]
        wantsRestingTouches = false
    }
    required init?(coder: NSCoder) { fatalError() }

    // Fully transparent cursor shown whenever the pointer is over the board.
    private static let blankCursor: NSCursor = {
        let img = NSImage(size: NSSize(width: 1, height: 1))
        img.lockFocus(); NSColor.clear.set(); NSRect(x: 0, y: 0, width: 1, height: 1).fill(); img.unlockFocus()
        return NSCursor(image: img, hotSpot: .zero)
    }()

    override func resetCursorRects() { addCursorRect(bounds, cursor: PadView.blankCursor) }
    override func mouseMoved(with event: NSEvent) { PadView.blankCursor.set() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Touches

    // Two-finger tap detection
    private var gestureStart: TimeInterval?
    private var multiTouch = false
    private let tapMaxDuration: TimeInterval = 0.35

    override func touchesBegan(with event: NSEvent) {
        if gestureStart == nil { gestureStart = event.timestamp; multiTouch = false }

        if event.touches(matching: .touching, in: self).count >= 2 {
            // Second finger landed: this is a gesture, not a stroke. Drop the stroke in progress.
            if !multiTouch {
                multiTouch = true
                if activeTouch != nil, !strokes.isEmpty { strokes.removeLast() }
                activeTouch = nil
                needsDisplay = true
            }
            return
        }

        guard !multiTouch, activeTouch == nil,
              let t = event.touches(matching: .began, in: self).first else { return }
        activeTouch = t.identity
        strokes.append([t.normalizedPosition])
        needsDisplay = true
    }

    override func touchesMoved(with event: NSEvent) {
        guard !multiTouch, let id = activeTouch,
              let t = event.touches(matching: .moved, in: self).first(where: { $0.identity.isEqual(id) }),
              !strokes.isEmpty else { return }
        strokes[strokes.count - 1].append(t.normalizedPosition)
        needsDisplay = true
    }

    override func touchesEnded(with event: NSEvent) { touchesFinished(event, event.touches(matching: .ended, in: self)) }
    override func touchesCancelled(with event: NSEvent) { touchesFinished(event, event.touches(matching: .cancelled, in: self)) }

    private func touchesFinished(_ event: NSEvent, _ touches: Set<NSTouch>) {
        if let id = activeTouch, touches.contains(where: { $0.identity.isEqual(id) }) {
            activeTouch = nil
        }
        // All fingers lifted: if it was a quick two-finger touch, clear.
        if event.touches(matching: .touching, in: self).isEmpty {
            if multiTouch, let start = gestureStart, event.timestamp - start <= tapMaxDuration {
                clear()
            }
            gestureStart = nil
            multiTouch = false
        }
    }

    // Two-finger tap is also delivered as a secondary click when that system setting is on.
    override func rightMouseDown(with event: NSEvent) { clear() }

    private func clear() {
        strokes.removeAll()
        activeTouch = nil
        needsDisplay = true
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            clear()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
        bounds.fill()

        // Faint 田字格 guide grid
        let guide = NSBezierPath()
        guide.move(to: NSPoint(x: bounds.midX, y: 0)); guide.line(to: NSPoint(x: bounds.midX, y: bounds.maxY))
        guide.move(to: NSPoint(x: 0, y: bounds.midY)); guide.line(to: NSPoint(x: bounds.maxX, y: bounds.midY))
        guide.lineWidth = 1
        guide.setLineDash([6, 6], count: 2, phase: 0)
        NSColor(calibratedRed: 0.85, green: 0.4, blue: 0.4, alpha: 0.25).setStroke()
        guide.stroke()

        NSColor.black.setStroke()
        for stroke in strokes {
            let pts = stroke.map { NSPoint(x: $0.x * bounds.width, y: $0.y * bounds.height) }
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            guard let first = pts.first else { continue }
            path.move(to: first)
            if pts.count == 1 {
                path.line(to: first)                  // dot
            } else {
                // Smooth with midpoint quadratic curves
                for i in 1..<pts.count {
                    let mid = NSPoint(x: (pts[i - 1].x + pts[i].x) / 2, y: (pts[i - 1].y + pts[i].y) / 2)
                    path.curve(to: mid, controlPoint1: pts[i - 1], controlPoint2: pts[i - 1])
                }
                path.line(to: pts.last!)
            }
            path.stroke()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ note: Notification) {
        // Roughly the aspect ratio of a MacBook trackpad, so strokes aren't distorted.
        let rect = NSRect(x: 0, y: 0, width: 800, height: 500)
        window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "DrawingPad — space to clear"
        window.contentView = PadView(frame: rect)
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.contentView)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Lock the cursor in the middle of the window while drawing so touches
    // keep going to our view and the pointer doesn't wander off.
    func applicationDidBecomeActive(_ note: Notification) {
        guard let w = window, let screen = w.screen ?? NSScreen.main else { return }
        let c = NSPoint(x: w.frame.midX, y: w.frame.midY)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        CGWarpMouseCursorPosition(CGPoint(x: c.x, y: primaryHeight - c.y))
        CGAssociateMouseAndMouseCursorPosition(0)
        hideCursor()
    }

    func windowDidBecomeKey(_ note: Notification) {
        if NSApp.isActive { hideCursor() }
    }

    private var cursorHidden = false
    private func hideCursor() {
        window.invalidateCursorRects(for: window.contentView!)
        guard !cursorHidden else { return }
        CGDisplayHideCursor(CGMainDisplayID())
        NSCursor.hide()
        cursorHidden = true
    }

    func applicationWillResignActive(_ note: Notification) { releaseCursor() }
    func applicationWillTerminate(_ note: Notification) { releaseCursor() }
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }

    private func releaseCursor() {
        CGAssociateMouseAndMouseCursorPosition(1)
        guard cursorHidden else { return }
        NSCursor.unhide()
        CGDisplayShowCursor(CGMainDisplayID())
        cursorHidden = false
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)

// Minimal menu so Cmd+Q works
let mainMenu = NSMenu()
let appItem = NSMenuItem()
mainMenu.addItem(appItem)
let appMenu = NSMenu()
appMenu.addItem(withTitle: "Quit DrawingPad", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appItem.submenu = appMenu
app.mainMenu = mainMenu

let delegate = AppDelegate()
app.delegate = delegate
app.run()
