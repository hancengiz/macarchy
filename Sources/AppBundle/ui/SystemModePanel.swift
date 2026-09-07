import AppKit
import Common
import SwiftUI

struct SystemModeShortcut: Identifiable, Equatable {
    let id: String
    let key: String
    let action: String
    let isExit: Bool
}

@MainActor
func systemModeShortcuts(_ config: Config) -> [SystemModeShortcut] {
    let names = ["audio": "Sound", "bluetooth": "Bluetooth", "network": "Network",
                 "displays": "Displays", "activity": "Activity Monitor", "capture": "Screenshot",
                 "lock": "Lock Screen", "appearance": "Appearance", "wallpaper": "Wallpaper",
                 "notifications": "Notifications", "reminders": "Reminders", "idle": "Lock Screen Settings"]
    return (config.modes["system"]?.bindings.values.map { binding in
        let script = binding.commands.shellOfCommandsDescription
        let commands = binding.commands.flatten()
        let returnsToMain = (commands.first as? ModeCommand)?.args.targetMode.val == "main"
        let isExit = commands.count == 1 && returnsToMain
        let action: String
            // Recognize only the exact bundled helper sequence; custom commands keep their actual description.
            = if commands.count == 2, returnsToMain,
            let exec = commands[1] as? ExecAndForgetCommand,
            let name = names.first(where: {
                exec.args.bashScript.trimmingCharacters(in: .whitespacesAndNewlines) == "\"$HOME/.config/macarchy/action\" \($0.key)"
            })?.value
        {
            name
        } else {
            isExit ? "Exit" : script
        }
        let keyNames = ["alt": "Opt", "shift": "Shift", "ctrl": "Ctrl", "cmd": "Cmd", "esc": "Esc"]
        let key = binding.descriptionWithKeyNotation.split(separator: "-")
            .map { keyNames[String($0)] ?? $0.uppercased() }.joined(separator: "+")
        return SystemModeShortcut(id: binding.descriptionWithKeyNotation, key: key, action: action, isExit: isExit)
    } ?? []).sorted {
        if $0.isExit != $1.isExit { return !$0.isExit }
        return $0.id < $1.id
    }
}

func systemModePanelFrame(visibleFrame: CGRect, contentSize: CGSize) -> CGRect {
    let inset = min(16, max(0, min(visibleFrame.width, visibleFrame.height) / 4))
    return CGRect(x: visibleFrame.minX + inset, y: visibleFrame.minY + inset,
                  width: min(contentSize.width, max(1, visibleFrame.width - inset * 2)),
                  height: min(contentSize.height, max(1, visibleFrame.height - inset * 2)))
}

@MainActor
func refreshSystemModePanel() {
    if !isUnitTest { SystemModePanel.shared.refresh() }
}

@MainActor
final class SystemModePanel: NSPanelHud {
    static let shared = SystemModePanel()
    private var displayedRows: [SystemModeShortcut] = []
    private var hostingView: NSHostingView<SystemModeView>?

    override private init() {
        super.init()
        title = "System Controls"
        identifier = NSUserInterfaceItemIdentifier("omarchy.system-controls")
        ignoresMouseEvents = true
        isOpaque = false
        setAccessibilityLabel("System Controls shortcuts")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func refresh() {
        guard config.showSystemModeOverlay, activeMode == "system", TrayMenuModel.shared.isEnabled else {
            orderOut(nil)
            return
        }
        let rows = systemModeShortcuts(config)
        guard !rows.isEmpty else { orderOut(nil); return }
        let index = focus.workspace.workspaceMonitor.monitorAppKitNsScreenScreensId - 1
        guard let screen = NSScreen.screens.getOrNil(atIndex: index) ?? NSScreen.screens.first else { return }
        let width = min(330, max(100, screen.visibleFrame.width - 32))
        if hostingView == nil || displayedRows != rows || hostingView?.frame.width != width {
            displayedRows = rows
            let view = NSHostingView(rootView: SystemModeView(rows: rows, width: width))
            let background = NSVisualEffectView()
            background.material = .hudWindow
            background.blendingMode = .behindWindow
            background.state = .active
            background.wantsLayer = true
            background.layer?.cornerRadius = 8
            background.layer?.masksToBounds = true
            background.addSubview(view)
            contentView = background
            hostingView = view
        }
        guard let hostingView else { return }
        let frame = systemModePanelFrame(visibleFrame: screen.visibleFrame, contentSize: hostingView.fittingSize)
        setFrame(frame, display: true)
        hostingView.frame = CGRect(origin: .zero, size: frame.size)
        if !isVisible { orderFrontRegardless() }
    }
}

private struct SystemModeView: View {
    let rows: [SystemModeShortcut]
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("System Controls", systemImage: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold))
            Divider()
            ForEach(rows) { row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.key).font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .frame(width: 102, alignment: .leading)
                    Text(row.action).font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(row.isExit ? .secondary : .primary)
            }
        }
        .padding(14)
        .frame(width: width)
        .fixedSize(horizontal: false, vertical: true)
    }
}
