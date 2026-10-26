import AppKit

/// Owns the panel, the state machine and the pointer tracking.
///
/// Everything that changes the surface goes through here: SwiftUI only renders.
@MainActor
public final class NotchSurfaceController {
    public struct Timing: Sendable {
        /// How long the pointer must rest in the hot zone before opening.
        public var openDelay: Duration
        /// How long the pointer may leave before collapsing.
        public var closeDelay: Duration

        public init(openDelay: Duration = .milliseconds(110), closeDelay: Duration = .milliseconds(320)) {
            self.openDelay = openDelay
            self.closeDelay = closeDelay
        }
    }

    public var timing: Timing
    public var expandedSize: CGSize

    private let geometryProvider: NotchGeometryProviding
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

    public init(
        geometryProvider: NotchGeometryProviding = AutomaticNotchGeometry(),
        expandedSize: CGSize = CGSize(width: 420, height: 190),
        timing: Timing = Timing()
    ) {
        self.geometryProvider = geometryProvider
        self.expandedSize = expandedSize
        self.timing = timing

        let initial = NotchSurfaceModel(
            notchSize: NotchGeometryMath.defaultNotchSize,
            expandedSize: expandedSize,
            notchCornerRadius: 8,
            mode: .simulated,
            motion: .fromEnvironment()
        )
        self.model = initial
        self.panel = NotchPanel(contentRect: CGRect(origin: .zero, size: expandedSize))
        self.hostingView = SurfaceHostingView(rootView: NotchSurfaceView(model: initial))

        // The view lays out at its final size even while the window is the notch:
        // letting AppKit derive size constraints from it would make the panel
        // refuse to shrink, leaving a rectangle on screen.
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        panel.contentMinSize = .zero
        panel.contentMaxSize = expandedSize
    }

    public var state: NotchState { model.state }

    // MARK: - Lifecycle

    public func start() {
        guard !isVisible else { return }

        if isDebugLoggingEnabled {
            debugLog("start")
        }

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

    // MARK: - Geometry

    private func refreshGeometry() {
        guard let screen = NotchDisplay.target(in: NSScreen.screens) else { return }
        let geometry = geometryProvider.geometry(for: screen)
        self.geometry = geometry

        guard let notch = geometry.notchRect else {
            panel.orderOut(nil)
            return
        }

        let available = CGSize(
            width: max(NotchGeometryMath.minimumNotchWidth, screen.frame.width - 40),
            height: max(80, screen.frame.height - 40)
        )
        let size = CGSize(
            width: min(expandedSize.width, available.width),
            height: min(expandedSize.height, available.height)
        )
        model.expandedSize = size

        model.notchSize = notch.size
        model.notchCornerRadius = geometry.cornerRadius
        model.mode = geometry.mode

        let expanded = NotchGeometryMath.expandedRect(
            screenFrame: screen.frame,
            notchRect: notch,
            size: size
        )

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
    }

    private var isDebugLoggingEnabled: Bool {
        ProcessInfo.processInfo.environment["CORNICE_DEBUG"] == "1"
    }

    private func debugLog(_ message: String) {
        guard isDebugLoggingEnabled else { return }
        FileHandle.standardError.write(Data("[cornice] \(message)\n".utf8))
    }

    private func pointerMoved() {
        guard isVisible,
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
            schedule(timing.openDelay) { [weak self] in
                guard let self else { return }
                self.apply(self.machine.openDeadlineReached())
            }

        case .cancelScheduled:
            cancelPending()

        case .scheduleClose:
            schedule(timing.closeDelay) { [weak self] in
                guard let self else { return }
                self.apply(self.machine.closeDeadlineReached())
            }

        case .open:
            setState(.open)

        case .collapse:
            setState(.dormant)
        }
    }

    /// Debug affordance: shows the expanded surface without hovering.
    public func openImmediately() {
        machine.reset(to: .open)
        cancelPending()
        setState(.open)
    }

    private func schedule(_ delay: Duration, _ action: @escaping @MainActor () -> Void) {
        cancelPending()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
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
                guard let self, self.model.state == .open else { return }
                self.machine.reset(to: .dormant)
                self.cancelPending()
                self.setState(.dormant)
            }
        }
    }
}
