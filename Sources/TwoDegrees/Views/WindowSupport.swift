import SwiftUI
import AppKit

// Window behaviour borrowed from Meridian: tear the menu bar panel off into a window,
// place the window left / centre / right, and keep it sized to the panel and on screen.

/// An area that moves its window when dragged (the window has no visible title bar), or, in the
/// menu bar panel, tears the panel off into a window once the pointer moves a few points.
struct WindowDragHandle: NSViewRepresentable {
    var onTearOff: (() -> Void)?

    final class DragView: NSView {
        var onTearOff: (() -> Void)?
        private var start: NSPoint?

        override var mouseDownCanMoveWindow: Bool { onTearOff == nil }

        override func mouseDown(with event: NSEvent) {
            if onTearOff == nil {
                window?.performDrag(with: event)
            } else {
                start = event.locationInWindow
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start, let onTearOff else { return }
            let p = event.locationInWindow
            if hypot(p.x - start.x, p.y - start.y) > 4 {
                self.start = nil
                onTearOff()
            }
        }

        override func mouseUp(with event: NSEvent) { start = nil }
    }

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.onTearOff = onTearOff
        return view
    }

    func updateNSView(_ view: DragView, context: Context) { view.onTearOff = onTearOff }
}

/// Where to put the desktop window. Requests are applied by the window itself (see HostWindow),
/// the moment it exists, so a newly opened window is positioned before it's ever seen.
enum WindowPlacement: String, CaseIterable, Identifiable {
    case left, center, right

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    enum Request {
        case edge(WindowPlacement)
        case topLeft(NSPoint)
    }

    /// The latest unapplied request (one at a time).
    static var pending: Request?
    static let didRequest = Notification.Name("TwoDegreesPlaceWindow")

    static func request(_ request: Request) {
        pending = request
        NotificationCenter.default.post(name: didRequest, object: nil)
    }

    /// Top-left point for a window of `size` on `visible`, 16pt from the screen edges.
    static func topLeft(for request: Request, size: CGSize, visible: CGRect) -> NSPoint {
        let margin: CGFloat = 16
        switch request {
        case .topLeft(let point):
            return point
        case .edge(.left):
            return NSPoint(x: visible.minX + margin, y: visible.maxY - margin)
        case .edge(.center):
            return NSPoint(x: (visible.midX - size.width / 2).rounded(), y: visible.maxY - margin)
        case .edge(.right):
            return NSPoint(x: visible.maxX - size.width - margin, y: visible.maxY - margin)
        }
    }
}

/// The menu bar panel opens horizontally centred under the app's menu bar item (macOS puts it with
/// its left edge at the item), kept on screen.
enum MenuBarPlacement {
    /// The left edge for a panel `width` wide centred under an item whose centre is at `itemMidX`.
    static func centeredX(itemMidX: CGFloat, width: CGFloat, visible: CGRect) -> CGFloat {
        let x = (itemMidX - width / 2).rounded()
        return min(max(x, visible.minX), max(visible.minX, visible.maxX - width))
    }

    /// The screen frame of this app's menu bar item: the status bar window AppKit makes for it.
    static var itemFrame: CGRect? {
        NSApp.windows.first { $0.className.contains("StatusBarWindow") && $0.isVisible }?.frame
    }
}

/// Holds the NSWindow hosting the panel (the menu bar popover or the desktop window), and keeps
/// that window fully on screen: after any resize, from SwiftUI or from us, it is pulled back
/// inside the screen's visible area (top edge first, so the header is never lost).
final class HostWindow {
    /// True for the desktop window, which applies WindowPlacement requests.
    var isDesktop = false
    weak var window: NSWindow? {
        didSet { if window !== oldValue { observe() } }
    }
    private var observers: [NSObjectProtocol] = []

    private func observe() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window else { return }
        for name in [NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.centerUnderMenuBarItem()
                self?.keepOnScreen()
            })
        }
        if !isDesktop {
            // macOS places the panel each time it opens; centre it again then.
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didMoveNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.centerUnderMenuBarItem()
                })
            }
            centerUnderMenuBarItem()
        }
        if isDesktop {
            observers.append(NotificationCenter.default.addObserver(forName: WindowPlacement.didRequest, object: nil, queue: .main) { [weak self] _ in
                self?.applyPlacement(animated: true)
            })
            applyPlacement(animated: false)
        }
        keepOnScreen()
    }

    /// Applies a pending placement. A brand-new window is placed while still invisible and then
    /// faded in; an open window glides to its new spot.
    func applyPlacement(animated: Bool) {
        guard isDesktop, let window, let request = WindowPlacement.pending,
              let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        WindowPlacement.pending = nil
        let topLeft = WindowPlacement.topLeft(for: request, size: window.frame.size, visible: visible)
        var frame = window.frame
        frame.origin = NSPoint(x: topLeft.x, y: topLeft.y - frame.height)
        if animated && window.isVisible {
            window.setFrame(frame, display: true, animate: true)
            keepOnScreen()
        } else {
            window.alphaValue = 0
            window.setFrame(frame, display: false)
            keepOnScreen()
            DispatchQueue.main.async {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    window.animator().alphaValue = 1
                }
            }
        }
    }

    /// Centres the menu bar panel under the menu bar item. Does nothing for the desktop window, or a
    /// panel that's already there (so moving it doesn't loop through didMove).
    func centerUnderMenuBarItem() {
        guard !isDesktop, let window, let item = MenuBarPlacement.itemFrame,
              let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let x = MenuBarPlacement.centeredX(itemMidX: item.midX, width: window.frame.width, visible: visible)
        if abs(window.frame.origin.x - x) > 0.5 {
            window.setFrameOrigin(NSPoint(x: x, y: window.frame.origin.y))
        }
    }

    func keepOnScreen() {
        guard let window, let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var origin = window.frame.origin
        let size = window.frame.size
        origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
        if origin.y + size.height > visible.maxY { origin.y = visible.maxY - size.height }
        if origin.y < visible.minY { origin.y = min(visible.minY, visible.maxY - size.height) }
        if origin != window.frame.origin {
            window.setFrameOrigin(origin)
        }
    }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}

struct HostWindowReader: NSViewRepresentable {
    let box: HostWindow
    var onWindow: ((NSWindow) -> Void)? = nil

    /// Reports its window as soon as it's attached (before the window is first drawn).
    final class ReaderView: NSView {
        var box: HostWindow?
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            if let box, box.window !== window { box.window = window }
            let callback = onWindow
            DispatchQueue.main.async { callback?(window) }
        }
    }

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.box = box
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.box = box
        view.onWindow = onWindow
        if box.window !== view.window, view.window != nil { box.window = view.window }
    }
}

