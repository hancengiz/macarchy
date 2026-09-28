import AppKit
import Common
import SwiftUI

struct BarConfig: ConvenienceMutable, Equatable, Sendable {
    var enabled: Bool = false
    /// Strip height in points.
    var height: Int = 28
    /// With an auto-hiding menu bar: dock to the very top, and get out of
    /// the way while the pointer is in the menu bar reveal band.
    var hideWithMenuBar: Bool = true
    /// Only show the bar on displays whose menu bar auto-hides.
    var onlyWithHiddenMenuBar: Bool = false
}

private let barParser: [String: any ParserProtocol<BarConfig>] = [
    "enabled": Parser(\.enabled, parseBool),
    "height": Parser(\.height, parseInt),
    "hide-with-menu-bar": Parser(\.hideWithMenuBar, parseBool),
    "only-with-hidden-menu-bar": Parser(\.onlyWithHiddenMenuBar, parseBool),
]

func parseBar(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> BarConfig {
    parseTable(raw, BarConfig(), barParser, backtrace, &c)
}

// MARK: Pure cell model

struct BarMonitor {
    let id: Int
    let activeWorkspace: String
}

struct BarWorkspace {
    let name: String
    let monitorId: Int?
    let isVisible: Bool
    let isEffectivelyEmpty: Bool
}

enum BarCellState: Equatable {
    case focused // visible AND the globally focused workspace
    case visible // visible on its monitor
    case hidden // not visible (empty persistent or parked)
}

struct BarCell: Equatable {
    let name: String
    let state: BarCellState
}

struct BarMonitorCells: Equatable {
    let monitorId: Int
    let cells: [BarCell]
}

/// Groups workspaces per monitor, ordered by name; state by visibility/focus.
/// Workspaces with no monitor assignment (never shown) are omitted.
func barCells(monitors: [BarMonitor], workspaces: [BarWorkspace], focusedWorkspace: String) -> [BarMonitorCells] {
    monitors.map { monitor in
        BarMonitorCells(
            monitorId: monitor.id,
            cells: workspaces
                .filter { $0.monitorId == monitor.id }
                .sorted { $0.name < $1.name }
                .map { workspace in
                    BarCell(
                        name: workspace.name,
                        state: barCellState(
                            workspace: workspace,
                            activeOnMonitor: monitor.activeWorkspace,
                            focusedWorkspace: focusedWorkspace,
                        ),
                    )
                }
        )
    }
}

private func barCellState(workspace: BarWorkspace, activeOnMonitor: String, focusedWorkspace: String) -> BarCellState {
    if workspace.name == focusedWorkspace, workspace.isVisible { return .focused }
    if workspace.isVisible { return .visible }
    return .hidden
}

// MARK: Menu-bar-aware placement (pure)

/// Top edge (AppKit y) the bar should occupy: the very top on auto-hide
/// menu bar screens, just below the menu bar otherwise.
func barYTop(screenFrame: CGRect, visibleFrame: CGRect) -> CGFloat {
    visibleFrame.maxY >= screenFrame.maxY - 0.5 ? screenFrame.maxY : visibleFrame.maxY
}

/// True when the display's menu bar auto-hides (visibleFrame reaches the screen top).
func menuBarAutoHidden(screenFrame: CGRect, visibleFrame: CGRect) -> Bool {
    visibleFrame.maxY >= screenFrame.maxY - 0.5
}
/// True while the pointer sits in the menu bar (or its reveal) band.
func barHiddenForMenuBar(mouseY: CGFloat, screenFrame: CGRect, visibleFrame: CGRect) -> Bool {
    let band = max(screenFrame.maxY - visibleFrame.maxY, 28)
    return mouseY >= screenFrame.maxY - band
}

// MARK: Panels

@MainActor
func refreshBar() {
    if !isUnitTest { BarPanels.shared.refresh() }
}

@MainActor
final class BarPanels {
    static let shared = BarPanels()
    private var panels: [Int: BarStripPanel] = [:]
    private var mouseMonitor: Any?

    init() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncMenuBarHiding()
            }
        }
    }

    private func syncMenuBarHiding() {
        let mouseY = NSEvent.mouseLocation.y
        for panel in panels.values {
            panel.syncMenuBarHiding(mouseY: mouseY)
        }
    }
    func refresh() {
        guard config.bar.enabled else {
            panels.values.forEach { $0.orderOut(nil) }
            return
        }
        let groups = barCells(
            monitors: sortedMonitorInfos.map { BarMonitor(id: $0.monitorAppKitNsScreenScreensId, activeWorkspace: $0.activeWorkspace.name) },
            workspaces: Workspace.all.map { workspace in
                BarWorkspace(
                    name: workspace.name,
                    monitorId: workspace.workspaceMonitor.monitorAppKitNsScreenScreensId,
                    isVisible: workspace.isVisible,
                    isEffectivelyEmpty: workspace.isEffectivelyEmpty,
                )
            },
            focusedWorkspace: focus.workspace.name,
        )
        var seen: Set<Int> = []
        for group in groups {
            seen.insert(group.monitorId)
            let panel = panels[group.monitorId] ?? BarStripPanel(monitorId: group.monitorId)
            panels[group.monitorId] = panel
            panel.update(cells: group.cells, height: config.bar.height, monitorId: group.monitorId)
        }
        for (id, panel) in panels where !seen.contains(id) {
            panel.orderOut(nil)
            panels.removeValue(forKey: id)
        }
    }
}

@MainActor
final class BarStripPanel: NSPanelHud {
    let monitorId: Int
    private var hostingView: NSHostingView<BarStripView>?
    private var lastCells: [BarCell] = []
    private var lastHeight: Int = 28
    private var screenFrame: CGRect = .zero
    private var visibleFrame: CGRect = .zero
    private var hiddenForMenuBar = false

    init(monitorId: Int) {
        self.monitorId = monitorId
        super.init()
        title = "macarchy Bar"
        identifier = NSUserInterfaceItemIdentifier("macarchy.bar.\(monitorId)")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func update(cells: [BarCell], height: Int, monitorId: Int) {
        // monitorAppKitNsScreenScreensId is the 1-based index into NSScreen.screens.
        guard let screen = monitorId >= 1 ? NSScreen.screens.dropFirst(monitorId - 1).first : nil else {
            orderOut(nil)
            return
        }
        lastCells = cells
        lastHeight = height
        screenFrame = screen.frame
        visibleFrame = screen.visibleFrame
        if config.bar.onlyWithHiddenMenuBar, !menuBarAutoHidden(screenFrame: screenFrame, visibleFrame: visibleFrame) {
            orderOut(nil)
            screenFrame = .zero // keep the mouse-hide logic away from a hidden panel
            return
        }
        let view = BarStripView(cells: cells)
        if let hosting = hostingView {
            hosting.rootView = view
        } else {
            let hosting = NSHostingView(rootView: view)
            contentView = hosting
            self.hostingView = hosting
        }
        applyFrame(height: height)
        if !hiddenForMenuBar {
            orderFrontRegardless()
        }
    }

    private func applyFrame(height: Int) {
        let h = CGFloat(height)
        let yTop = barYTop(screenFrame: screenFrame, visibleFrame: visibleFrame)
        setFrame(
            NSRect(x: screenFrame.minX, y: yTop - h, width: screenFrame.width, height: h),
            display: true,
        )
    }

    /// Hide while the pointer is in the menu bar band (menu bar revealed), return after.
    func syncMenuBarHiding(mouseY: CGFloat) {
        guard config.bar.hideWithMenuBar, screenFrame != .zero else { return }
        let shouldHide = barHiddenForMenuBar(mouseY: mouseY, screenFrame: screenFrame, visibleFrame: visibleFrame)
        guard shouldHide != hiddenForMenuBar else { return }
        hiddenForMenuBar = shouldHide
        if shouldHide {
            orderOut(nil)
        } else {
            applyFrame(height: lastHeight)
            orderFrontRegardless()
        }
    }
}

private struct BarStripView: View {
    let cells: [BarCell]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(cells, id: \.name) { cell in
                Button {
                    switchWorkspace(cell.name)
                } label: {
                    Text(cell.name)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(chipBackground(cell.state)))
                        .foregroundStyle(chipText(cell.state))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Workspace \(cell.name)")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.clear)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspaces")
    }

    private func chipBackground(_ state: BarCellState) -> Color {
        let palette = Palette(name: config.palette.name)
        switch state {
            case .focused: return Color(nsColor: palette.focus ?? .controlAccentColor)
            case .visible: return Color(nsColor: palette.focus ?? .controlAccentColor).opacity(0.35)
            case .hidden: return Color(nsColor: palette.inactive ?? .quaternaryLabelColor).opacity(0.5)
        }
    }

    private func chipText(_ state: BarCellState) -> Color {
        let palette = Palette(name: config.palette.name)
        return state == .focused
            ? Color(nsColor: palette.background ?? .black)
            : Color(nsColor: palette.text ?? .labelColor)
    }
}

@MainActor
private func switchWorkspace(_ name: String) {
    Task.startUnstructured {
        try? await Task.sleep(for: .milliseconds(150))
        for _ in 0 ..< 3 {
            guard let sessionGuard = RunSessionGuard.isServerEnabled else { return } // paused server: ignore click
            let exit = try await runLightSession(.hotkeyBinding, sessionGuard) { () throws -> Int32ExitCode in
                switch parseCommand(["workspace", name]) {
                    case .cmd(let command):
                        return Int32ExitCode(rawValue: await command.run(.defaultEnv, CmdIoImpl.emptyStdinIgnoringOut).rawValue)
                    case .failure(let error):
                        die("Bar: can't parse workspace command: \(error.msg)")
                    case .help:
                        die("Bar: workspace command returned help")
                }
            }
            if exit.rawValue == 0 { return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }
}
