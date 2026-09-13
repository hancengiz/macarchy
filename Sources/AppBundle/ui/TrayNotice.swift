import AppKit
import Common
import SwiftUI

// Generic tray-anchored notification surface (UI-04).
// A compact translucent panel below the workspace indicators that can present
// any desktop notice: shortcut conflicts, config warnings, etc.

// MARK: Model

enum TrayNoticeSeverity {
    case info
    case success
    case warning
    case error

    var systemImage: String {
        switch self {
            case .info: "info.circle.fill"
            case .success: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
            case .info: .accentColor
            case .success: .green
            case .warning: .orange
            case .error: .red
        }
    }
}

/// Equality intentionally ignores `handler`; equal data means an equal action.
struct TrayNoticeAction: Equatable {
    let id: String
    let label: String
    let tooltip: String
    let handler: (@MainActor () -> Void)?

    init(id: String, label: String, tooltip: String = "", handler: (@MainActor () -> Void)? = nil) {
        self.id = id
        self.label = label
        self.tooltip = tooltip
        self.handler = handler
    }

    static func == (lhs: TrayNoticeAction, rhs: TrayNoticeAction) -> Bool {
        lhs.id == rhs.id && lhs.label == rhs.label && lhs.tooltip == rhs.tooltip
    }
}

struct TrayNoticeRow: Equatable {
    let title: String
    let detail: String?
    let action: TrayNoticeAction?
}

struct TrayNotice: Equatable {
    let id: String
    let severity: TrayNoticeSeverity
    let title: String
    var message: String? = nil
    var rows: [TrayNoticeRow] = []
    var actions: [TrayNoticeAction] = []
    /// Extra context rendered in caption size, e.g. "Checked 18:06".
    var footer: String? = nil
    /// Auto-dismiss delay in seconds. `nil` keeps the notice until dismissed manually.
    var lifetime: TimeInterval? = nil
    /// Optional custom section (e.g. a picker menu). Not part of equality.
    var extra: AnyView? = nil

    init(
        id: String,
        severity: TrayNoticeSeverity,
        title: String,
        message: String? = nil,
        rows: [TrayNoticeRow] = [],
        actions: [TrayNoticeAction] = [],
        footer: String? = nil,
        lifetime: TimeInterval? = nil,
        extra: AnyView? = nil,
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.message = message
        self.rows = rows
        self.actions = actions
        self.footer = footer
        self.lifetime = lifetime
        self.extra = extra
    }

    static func == (lhs: TrayNotice, rhs: TrayNotice) -> Bool {
        lhs.id == rhs.id && lhs.severity == rhs.severity && lhs.title == rhs.title && lhs.message == rhs.message &&
            lhs.rows == rhs.rows && lhs.actions == rhs.actions && lhs.footer == rhs.footer && lhs.lifetime == rhs.lifetime
    }
}

// MARK: Geometry

func noticePanelFrame(anchor: CGRect?, visibleFrame: CGRect, contentSize: CGSize) -> CGRect {
    let margin: CGFloat = 8
    let gap: CGFloat = 7
    let maxHeight = min(visibleFrame.height * 0.6, 320)
    let width = min(contentSize.width, visibleFrame.width - margin * 2).rounded()
    let height = min(contentSize.height, maxHeight).rounded()
    let centerX = anchor.map { $0.midX } ?? visibleFrame.midX
    let x = min(max(centerX - width / 2, visibleFrame.minX + margin), visibleFrame.maxX - margin - width)
    let top = min(anchor?.minY ?? visibleFrame.maxY, visibleFrame.maxY)
    return CGRect(x: x, y: (top - gap - height).rounded(), width: width, height: height)
}

// MARK: Center

@MainActor
final class NoticeCenter: ObservableObject {
    static let shared = NoticeCenter()

    @Published private(set) var current: TrayNotice?
    /// How many distinct notices were presented. In-place refreshes don't count.
    @Published private(set) var presentations = 0
    private var autoDismissTask: Task<Void, Never>?

    private init() {}

    /// Posts a notice. Same id updates the visible notice in place (no re-animation).
    /// Posting an equal notice is a no-op, so periodic rechecks never re-open a dismissed notice.
    func post(_ notice: TrayNotice) {
        if let current, current.id == notice.id {
            guard current != notice else { return }
            self.current = notice
            if !isUnitTest { TrayNoticePanel.shared.refresh(notice: notice) }
            scheduleAutoDismiss(notice)
            return
        }
        current = notice
        presentations += 1
        scheduleAutoDismiss(notice)
        if !isUnitTest { TrayNoticePanel.shared.present(notice: notice, anchor: trayStatusItemAnchor()) }
    }

    /// Replaces the visible notice content if `id` is currently shown.
    func refreshIfShown(id: String, notice: TrayNotice) {
        guard current?.id == id else { return }
        post(notice)
    }

    func dismiss(id: String? = nil) {
        if let id, current?.id != id { return }
        autoDismissTask?.cancel()
        current = nil
        if !isUnitTest { TrayNoticePanel.shared.dismiss() }
    }

    func reset() {
        autoDismissTask?.cancel()
        current = nil
        presentations = 0
        if !isUnitTest { TrayNoticePanel.shared.dismiss() }
    }

    private func scheduleAutoDismiss(_ notice: TrayNotice) {
        autoDismissTask?.cancel()
        guard let lifetime = notice.lifetime else { return }
        autoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(lifetime))
            guard !Task.isCancelled else { return }
            self?.dismiss(id: notice.id)
        }
    }
}

// MARK: Panel

@MainActor
final class TrayNoticePanel: NSPanelHud {
    static let shared = TrayNoticePanel()

    private var background: NSVisualEffectView?
    private var hostingView: NSHostingView<NoticeView>?
    private var displayedNotice: TrayNotice?
    private var eventMonitors: [Any] = []
    private var screenParamsObserver: NSObjectProtocol?

    override private init() {
        super.init()
        title = "Notification"
        identifier = NSUserInterfaceItemIdentifier("macarchy.tray-notice")
        isOpaque = false
        setAccessibilityLabel("Desktop notification")
        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let notice = self.displayedNotice, self.isVisible else { return }
                self.updateContent(notice: notice)
                self.applyFrame(anchor: trayStatusItemAnchor(), animated: false)
            }
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func present(notice: TrayNotice, anchor: CGRect?) {
        updateContent(notice: notice)
        orderFrontRegardless()
        applyFrame(anchor: anchor, animated: true)
        installEventMonitors()
    }

    func refresh(notice: TrayNotice) {
        guard isVisible else { return }
        updateContent(notice: notice)
        applyFrame(anchor: trayStatusItemAnchor(), animated: false)
    }

    func dismiss() {
        removeEventMonitors()
        orderOut(nil)
    }

    private func updateContent(notice: TrayNotice) {
        displayedNotice = notice
        if background == nil {
            let background = NSVisualEffectView()
            background.material = .hudWindow
            background.blendingMode = .behindWindow
            background.state = .active
            background.wantsLayer = true
            background.layer?.cornerRadius = 8
            background.layer?.masksToBounds = true
            background.layer?.borderWidth = 1
            background.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
            contentView = background
            self.background = background
        }
        // Keep one stable hosting view; swapping subviews mid-animation left the panel blank.
        if let hosting = hostingView {
            hosting.rootView = NoticeView(notice: notice)
        } else {
            let hosting = NSHostingView(rootView: NoticeView(notice: notice))
            hosting.autoresizingMask = [.width, .height]
            background?.addSubview(hosting)
            hostingView = hosting
        }
        let size = hostingView?.fittingSize ?? .zero
        hostingView?.setFrameSize(size)
        background?.setFrameSize(size)
    }

    private func applyFrame(anchor: CGRect?, animated: Bool) {
        guard let hostingView else { return }
        let frame = noticePanelFrame(
            anchor: anchor,
            visibleFrame: targetScreen(anchor: anchor).visibleFrame,
            contentSize: hostingView.frame.size,
        )
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !animated || reduceMotion {
            alphaValue = 1
            setFrame(frame, display: true)
            return
        }
        alphaValue = 0
        // Start slightly behind the menu bar so the notice slides down from the top edge.
        setFrame(frame.offsetBy(dx: 0, dy: 14), display: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().setFrame(frame, display: true)
            self.animator().alphaValue = 1
        } completionHandler: {
            // Guarantee the final state even if the animation is interrupted.
            self.alphaValue = 1
            self.setFrame(frame, display: true)
        }
    }

    private func targetScreen(anchor: CGRect?) -> NSScreen {
        if let anchor {
            let point = CGPoint(x: anchor.midX, y: anchor.minY)
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) { return screen }
        }
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) { return screen }
        return NSScreen.main ?? NSScreen.screens.first.orDie()
    }

    // MARK: Dismissal monitors

    private func installEventMonitors() {
        removeEventMonitors()
        let mouseMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Global monitors only observe events delivered to other apps.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mouseMask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissFromOutsideInteraction() }
        }) {
            eventMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mouseMask, handler: { [weak self] event in
            // Clicks inside the notice itself are content interaction, not dismissal.
            let isInsideNotice = event.window === self
            if !isInsideNotice {
                MainActor.assumeIsolated { self?.dismissFromOutsideInteraction() }
            }
            return event
        }) {
            eventMonitors.append(monitor)
        }
        // keyDown global monitors require accessibility trust, which Macarchy already holds.
        // The Escape key is still delivered to the frontmost app; we only observe it.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let isEscape = event.keyCode == 53
            if isEscape {
                MainActor.assumeIsolated { self?.dismissFromOutsideInteraction() }
            }
        }) {
            eventMonitors.append(monitor)
        }
    }

    private func removeEventMonitors() {
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        eventMonitors = []
    }

    private func dismissFromOutsideInteraction() {
        NoticeCenter.shared.dismiss()
    }
}

// MARK: View

struct NoticeView: View {
    let notice: TrayNotice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: notice.severity.systemImage)
                    .foregroundStyle(notice.severity.tint)
                    .font(.system(size: 13, weight: .semibold))
                Text(notice.title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 10)
                Button {
                    NoticeCenter.shared.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
            if let message = notice.message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if !notice.rows.isEmpty { rows }
            if !notice.actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(notice.actions, id: \.id) { action in
                        Button {
                            action.handler?()
                        } label: {
                            Text(action.label).font(.system(size: 12))
                        }
                        .help(action.tooltip)
                    }
                    Spacer(minLength: 0)
                }
            }
            if let extra = notice.extra {
                extra
            }
            if let footer = notice.footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: 420, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var rows: some View {
        if notice.rows.count > 4 {
            ScrollView { rowsList }.frame(maxHeight: 200)
        } else {
            rowsList
        }
    }

    private var rowsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(notice.rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).font(.system(size: 12, weight: .bold, design: .monospaced))
                        if let detail = row.detail {
                            Text(detail)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    if let action = row.action {
                        Button {
                            action.handler?()
                        } label: {
                            Text(action.label).font(.system(size: 11))
                        }
                        .help(action.tooltip)
                    }
                }
            }
        }
    }
}

/// Compact picker for resolving "which app owns the shortcut" manually.
struct RunningAppsMenu: View {
    var body: some View {
        Menu {
            ForEach(
                NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular },
                id: \.processIdentifier,
            ) { app in
                Button(app.localizedName ?? "Application") {
                    NoticeCenter.shared.dismiss()
                    app.activate(options: .activateIgnoringOtherApps)
                }
            }
        } label: {
            Label("Open App…", systemImage: "arrow.up.forward.app")
                .font(.system(size: 12))
        }
        .fixedSize()
        .help("Activate a running application")
    }
}

// MARK: Built-in notices

let modifierMouseNoticeId = "modifier-mouse-warning"

@MainActor
func postModifierMouseWarningNotice(warning: String) {
    NoticeCenter.shared.post(TrayNotice(
        id: modifierMouseNoticeId,
        severity: .warning,
        title: "Modifier mouse gestures disabled",
        message: warning,
        actions: [
            TrayNoticeAction(id: "accessibility-settings", label: "Accessibility Settings", tooltip: "Open Privacy & Security settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Privacy-Settings.extension").orDie())
            },
            TrayNoticeAction(id: "retry", label: "Retry", tooltip: "Reload config to retry enabling gestures") {
                Task { @MainActor in
                    _ = await reloadConfig_nonCancellable(args: ReloadConfigCmdArgs(rawArgs: []))
                }
            },
        ],
    ))
}
