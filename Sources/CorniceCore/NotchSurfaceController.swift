import AppKit
import SwiftUI

/// Owns the panel, the state machine and the pointer tracking.
///
/// Everything that changes the surface goes through here: SwiftUI only renders.
@MainActor
public final class NotchSurfaceController {
    public var onOpenSettings: (() -> Void)? {
        didSet { model.onOpenSettings = onOpenSettings }
    }

    /// Called whenever the surface changes state, so the app can start or stop
    /// widget work with visibility.
    public var onStateChanged: ((NotchState) -> Void)?

    /// Stage content injected by the app (the widget area).
    public var widgetContent: AnyView? {
        didSet { model.widgetContent = widgetContent }
    }

    private let settings: SettingsStore
    private let geometryProvider: NotchGeometryProviding
    public let pager: StagePager
    private let model: NotchSurfaceModel
    private let panel: NotchPanel
    private let hostingView: SurfaceHostingView

    private var geometry: ScreenGeometry?
    private var pending: Task<Void, Never>?
    private var resizeTask: Task<Void, Never>?
    private var machine = NotchInteractionMachine()
    private var monitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var isVisible = false
    /// Pinned surfaces ignore hover: used by the options window to preview changes.
    private var isPinned = false
    private var pageGesture = PagerGestureAccumulator()

    public init(
        settings: SettingsStore,
        geometryProvider: NotchGeometryProviding = AutomaticNotchGeometry(),
        pager: StagePager = StagePager()
    ) {
        self.settings = settings
        self.geometryProvider = geometryProvider
        self.pager = pager

        let initial = NotchSurfaceModel(
            notchSize: NotchGeometryMath.defaultNotchSize,
            expandedSize: settings.settings.expandedSize,
            notchCornerRadius: 8,
            mode: .simulated,
            motion: settings.settings.motion
        )
        self.model = initial
        self.panel = NotchPanel(contentRect: CGRect(origin: .zero, size: settings.settings.expandedSize))
        self.hostingView = SurfaceHostingView(rootView: NotchSurfaceView(model: initial))

        // The view lays out at its final size even while the window is the notch:
        // letting AppKit derive size constraints from it would make the panel
        // refuse to shrink, leaving a rectangle on screen.
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        panel.contentMinSize = .zero
        panel.contentMaxSize = CGSize(width: 1200, height: 600)
    }

    public var state: NotchState { model.state }

    // MARK: - Lifecycle

    public func start() {
        guard !isVisible else { return }

        debugLog("start")

        hostingView.rootView = NotchSurfaceView(model: model)
        panel.contentView = hostingView
        panel.ignoresMouseEvents = true

        refreshGeometry()
        installMonitors()
        observeScreenChanges()
        observeSpaceChanges()

        isVisible = true
    }

    public func stop() {
        cancelPending()
        machine.reset(to: .dormant)
        setState(.dormant)

        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()

        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }

        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
            self.spaceObserver = nil
        }

        panel.orderOut(nil)
        isVisible = false
    }

    public func setVisible(_ visible: Bool) {
        if visible {
            start()
        } else {
            stop()
        }
    }

    public func toggle() {
        setVisible(!isVisible)
    }

    // MARK: - Settings

    /// Re-applies everything the options window can change.
    public func applySettings() {
        model.motion = settings.settings.motion
        refreshGeometry()
    }

    /// Pins the surface open so the options window can preview changes live.
    public func setPinned(_ pinned: Bool) {
        isPinned = pinned
        if pinned {
            openImmediately()
        } else {
            collapse()
        }
    }

    // MARK: - Geometry

    private func refreshGeometry() {
        guard let screen = NotchDisplay.target(in: NSScreen.screens) else { return }
        let geometry = geometryProvider.geometry(for: screen)
        self.geometry = geometry

        guard let notch = geometry.notchRect else {
            panel.orderOut(nil)
            return
        }

        let preferred = settings.settings.expandedSize
        let available = CGSize(
            width: max(NotchGeometryMath.minimumNotchWidth, screen.frame.width - 40),
            height: max(80, screen.frame.height - 40)
        )
        let size = CGSize(
            width: min(preferred.width, available.width),
            height: min(preferred.height, available.height)
        )
        model.expandedSize = size

        model.notchSize = notch.size
        model.notchCornerRadius = geometry.cornerRadius
        model.mode = geometry.mode

        panel.setFrame(frame(for: model.state), display: true)
        hostingView.surfaceSize = model.surfaceSize

        if isVisible, model.state == .open {
            panel.orderFrontRegardless()
        }
    }

    /// While idle the window is exactly the notch: a large transparent window is
    /// snapshotted during Space transitions and shows up as a visible rectangle.
    private func frame(for state: NotchState) -> CGRect {
        guard let notch = geometry?.notchRect else { return .zero }
        guard state == .open, let expanded = expandedRect else { return notch }
        return expanded
    }

    /// Grows the window immediately, shrinks it only after the collapse animation.
    private func updateFrame(animated: Bool) {
        resizeTask?.cancel()

        guard animated else {
            panel.setFrame(frame(for: model.state), display: true)
            return
        }

        let target = frame(for: model.state)
        let settleDelay = model.motion.settleDelay
        resizeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled, let self, self.model.state != .open else { return }

            // Nothing may stay on screen while idle: the Space switch snapshots
            // every window, and a transparent overlay turns into a rectangle.
            self.panel.orderOut(nil)
            self.panel.setFrame(target, display: true)
        }
    }

    private var expandedRect: CGRect? {
        guard let geometry, let notch = geometry.notchRect else { return nil }
        return NotchGeometryMath.expandedRect(
            screenFrame: geometry.screenFrame,
            notchRect: notch,
            size: model.expandedSize
        )
    }

    // MARK: - State machine

    private func setState(_ newState: NotchState) {
        guard model.state != newState else { return }

        debugLog("\(model.state.rawValue) -> \(newState.rawValue)")

        // The window must already be at its final size when SwiftUI starts
        // animating, otherwise the resize and the spring fight each other.
        if newState == .open {
            resizeTask?.cancel()
            panel.setFrame(frame(for: .open), display: true)
            panel.orderFrontRegardless()
        }

        model.state = newState
        hostingView.surfaceSize = model.surfaceSize
        panel.ignoresMouseEvents = newState != .open

        if newState != .open {
            updateFrame(animated: true)
        }

        onStateChanged?(newState)
    }

    private func debugLog(_ message: String) {
        guard ProcessInfo.processInfo.environment["CORNICE_DEBUG"] == "1" else { return }
        FileHandle.standardError.write(Data("[cornice] \(message)\n".utf8))
    }

    private func pointerMoved() {
        guard !isPinned,
              isVisible,
              let geometry,
              let notch = geometry.notchRect,
              let expanded = expandedRect
        else { return }

        let command = machine.pointerMoved(
            at: NSEvent.mouseLocation,
            notch: notch,
            panel: expanded
        )
        apply(command)
    }

    private func apply(_ command: NotchInteractionMachine.Command) {
        switch command {
        case .none:
            break

        case .scheduleOpen:
            schedule(settings.settings.hoverOpenDelay) { [weak self] in
                guard let self else { return }
                self.apply(self.machine.openDeadlineReached())
            }

        case .cancelScheduled:
            cancelPending()

        case .scheduleClose:
            schedule(settings.settings.hoverCloseDelay) { [weak self] in
                guard let self else { return }
                self.apply(self.machine.closeDeadlineReached())
            }

        case .open:
            setState(.open)

        case .collapse:
            setState(.dormant)
        }
    }

    /// Shows the expanded surface without hovering (debug, preview, options window).
    public func openImmediately() {
        machine.reset(to: .open)
        cancelPending()
        setState(.open)
    }

    public func collapse() {
        isPinned = false
        machine.reset(to: .dormant)
        cancelPending()
        setState(.dormant)
    }

    private func schedule(_ seconds: Double, _ action: @escaping @MainActor () -> Void) {
        cancelPending()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.pending = nil
            action()
        }
    }

    private func cancelPending() {
        pending?.cancel()
        pending = nil
    }

    // MARK: - Input

    private func installMonitors() {
        guard monitors.isEmpty else { return }

        // Global: events that go to other apps (the surface is click-through while collapsed).
        let globalHandler: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pointerMoved()
            }
        }

        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: globalHandler) {
            monitors.append(global)
        }

        // Local: events delivered to our own panel while it is open.
        let localHandler: (NSEvent) -> NSEvent? = { [weak self] event in
            MainActor.assumeIsolated {
                self?.pointerMoved()
            }
            return event
        }

        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: localHandler) {
            monitors.append(local)
        }

        // Trackpad swipe pages the stage while the surface is open.
        let scrollHandler: (NSEvent) -> NSEvent? = { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleScroll(event)
            }
            return event
        }

        if let scroll = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel], handler: scrollHandler) {
            monitors.append(scroll)
        }
    }

    private func handleScroll(_ event: NSEvent) {
        guard model.state == .open,
              pager.pageCount > 1,
              let expanded = expandedRect,
              expanded.contains(NSEvent.mouseLocation)
        else { return }

        if event.phase == .ended || event.momentumPhase == .ended {
            pageGesture.reset()
            return
        }

        // Only horizontal intent; vertical scrolling stays with the content.
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }

        if let step = pageGesture.feed(deltaX: event.scrollingDeltaX, now: Date()) {
            pager.advance(step)
        }
    }

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshGeometry()
            }
        }
    }

    private func observeSpaceChanges() {
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isPinned, self.model.state == .open else { return }
                self.collapse()
            }
        }
    }
}
