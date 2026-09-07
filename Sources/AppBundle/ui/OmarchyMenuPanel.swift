import AppKit
import Common
import SwiftUI

let omarchyMenuMode = "macarchy-menu"

@MainActor
func refreshOmarchyMenu() {
    if !isUnitTest { OmarchyMenuPanel.shared.refresh() }
}

@MainActor
final class OmarchyMenuPanel: NSPanelHud, NSWindowDelegate {
    static let shared = OmarchyMenuPanel()
    private let model = OmarchyMenuModel()
    private var loaded = false

    override private init() {
        super.init()
        title = "macarchy"
        identifier = NSUserInterfaceItemIdentifier("omarchy.launcher")
        isOpaque = false
        delegate = self
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func refresh() {
        guard activeMode == omarchyMenuMode, TrayMenuModel.shared.isEnabled else {
            orderOut(nil)
            return
        }
        if isVisible { return }
        if !loaded {
            model.store.load()
            loaded = true
        }
        model.resetToRoot()
        let index = focus.workspace.workspaceMonitor.monitorAppKitNsScreenScreensId - 1
        guard let screen = NSScreen.screens.getOrNil(atIndex: index) ?? NSScreen.screens.first else { return }
        let width = min(560, screen.visibleFrame.width - 32)
        let height = min(520, screen.visibleFrame.height - 32)
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor.separatorColor.cgColor
        let view = NSHostingView(rootView: OmarchyMenuView(model: model, choose: choose, dismiss: dismissMenu))
        background.addSubview(view)
        contentView = background
        view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        setFrame(CGRect(x: screen.visibleFrame.midX - width / 2,
                        y: screen.visibleFrame.minY + (screen.visibleFrame.height - height) * 0.65,
                        width: width, height: height), display: true)
        makeKeyAndOrderFront(nil)
    }

    func windowDidResignKey(_ notification: Notification) { dismissMenu() }

    func dismissMenu() {
        guard activeMode == omarchyMenuMode else { return }
        Task { @MainActor in
            if activeMode == omarchyMenuMode { await activateMode_nonCancellable(mainModeId) }
        }
    }

    private func choose(_ row: OmarchyMenuRow) {
        if row.isSubmenu {
            model.enter(row)
            return
        }
        if let handler = row.handler {
            NSLog("OMARCHY-MENU keybinding row chosen: \(row.label)")
            Task { @MainActor in
                await activateMode_nonCancellable(mainModeId)
                NSLog("OMARCHY-MENU mode restored, firing handler: \(row.label)")
                handler()
            }
            return
        }
        if let appPath = row.appPath {
            Task { @MainActor in
                await activateMode_nonCancellable(mainModeId)
                try? await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: appPath), configuration: NSWorkspace.OpenConfiguration())
            }
            return
        }
        guard let action = row.node?.action else { return }
        guard action.hasPrefix("aerospace:") else {
            // Shell actions come only from parsed menu files, never from search text.
            Task { @MainActor in
                guard let token = RunSessionGuard.isServerEnabled else { return }
                try await runLightSession(.menuBarButton, token) {
                    await activateMode_nonCancellable(mainModeId)
                    let command = ExecAndForgetCommand(args: .init(bashScript: action))
                    _ = command.run(.defaultEnv, CmdIoImpl.emptyStdinIgnoringOut)
                }
            }
            return
        }
        Task { @MainActor in
            guard let token = RunSessionGuard.isServerEnabled else { return }
            try await runLightSession(.menuBarButton, token) {
                await activateMode_nonCancellable(mainModeId)
                await runReservedMenuAction(action)
            }
        }
    }
}

@MainActor
private func runReservedMenuAction(_ action: String) async {
    switch action {
        case "aerospace:shortcuts":
            MessageModel.shared.message = Message(
                type: .shortcuts,
                title: "Current Shortcuts",
                description: "Current Shortcuts",
                body: currentShortcutsDescription(config),
                containsWarnings: false,
            )
        case "aerospace:conflicts":
            await ShortcutConflicts.shared.recheck()
            ShortcutConflicts.shared.show()
        case "aerospace:reload":
            _ = await reloadConfig_nonCancellable(args: ReloadConfigCmdArgs(rawArgs: []))
        case "aerospace:hotkeys":
            let url = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: ".config/aerospace/omarchy/HOTKEYS.txt")
            NSWorkspace.shared.open(url)
        default:
            break
    }
}

private struct OmarchyMenuView: View {
    @ObservedObject var model: OmarchyMenuModel
    let choose: (OmarchyMenuRow) -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.headerTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                if model.store.userParseError != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 11))
                        .help("menu.jsonc failed to parse; last-known-good entries are in use")
                }
                Image(systemName: "command.square")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12))
                    .help("Type to search · Return opens · Right enters a submenu · Backspace goes back · Esc closes")
            }
            .padding(.horizontal, 22).frame(height: 24)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                MenuSearchField(
                    query: $model.query,
                    move: model.moveSelection,
                    submit: { if let row = model.selection { choose(row) } },
                    dismiss: dismiss,
                    navigateBack: {
                        _ = model.back()
                    },
                    enterSubmenu: {
                        if let row = model.selection, row.isSubmenu { model.enter(row) }
                    },
                )
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        let rows = model.rows
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if row.isDivider {
                                Divider().padding(.horizontal, 12).padding(.vertical, 6)
                            } else {
                                MenuRowView(row: row, isSelected: index == model.selectedIndex, isSearching: model.isSearching) {
                                    choose(row)
                                }
                                .id(row.id)
                                .accessibilityAddTraits(index == model.selectedIndex ? [.isSelected] : [])
                            }
                        }
                        if rows.isEmpty {
                            Text(model.isSearching ? "No matches for \"\(model.query)\"" : "Nothing here yet")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 50)
                        }
                    }
                    .padding(.horizontal, 10).padding(.bottom, 10)
                }
                .onChange(of: model.selectedIndex) { _ in
                    if let row = model.selection { proxy.scrollTo(row.id) }
                }
                .onChange(of: model.query) { _ in
                    if let row = model.selection { proxy.scrollTo(row.id, anchor: .top) }
                }
            }
            Divider()
            HStack {
                Text(model.activeMenu == "root" ? "Omarchy" : model.activeMenu)
                Spacer()
                Text("\(model.rows.count(where: { model.isSelectable($0) })) actions")
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.horizontal, 22).frame(height: 34)
        }
    }
}

private struct MenuRowView: View {
    let row: OmarchyMenuRow
    let isSelected: Bool
    let isSearching: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 14) {
                icon
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(row.label).font(.system(size: 14, weight: .medium))
                        if row.isChecked { Text("✓").font(.system(size: 12)).foregroundStyle(.green) }
                    }
                    if isSearching || row.node == nil, let detail = row.detail {
                        Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer()
                if row.isSubmenu {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.6))
                } else if isSelected {
                    Image(systemName: "return").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: isSearching && row.detail != nil ? 52 : 44)
            .contentShape(Rectangle())
            .background(isSelected ? Color.teal.opacity(0.13) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .opacity(row.isDisabled ? 0.4 : 1)
        .disabled(row.isDisabled)
    }

    @ViewBuilder
    private var icon: some View {
        if let symbol = row.icon {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(.teal)
        } else if let appPath = row.appPath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appPath))
                .resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "circle.dotted")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
        }
    }
}

private struct MenuSearchField: NSViewRepresentable {
    @Binding var query: String
    let move: (Int) -> Void
    let submit: () -> Void
    let dismiss: () -> Void
    let navigateBack: () -> Void
    let enterSubmenu: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        // Plain borderless field: NSSearchField's built-in magnifier overlapped
        // the typed text when its chrome was disabled. The icon lives in SwiftUI now.
        let field = NSTextField()
        field.placeholderString = "Search apps, settings and commands"
        field.font = .systemFont(ofSize: 17)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        DispatchQueue.main.async { unsafe field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != query { field.stringValue = query }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MenuSearchField
        init(_ parent: MenuSearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.query = field.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            let textLength = (textView.string as NSString).length
            let caret = textView.selectedRange().location
            switch selector {
                case #selector(NSResponder.moveUp(_:)): parent.move(-1)
                case #selector(NSResponder.moveDown(_:)): parent.move(1)
                case #selector(NSResponder.pageUp(_:)): parent.move(-6)
                case #selector(NSResponder.pageDown(_:)): parent.move(6)
                case #selector(NSResponder.moveLeft(_:)):
                    // Navigate back only when the caret is at the very start.
                    guard textLength == 0 || caret == 0 else { return false }
                    parent.navigateBack()
                case #selector(NSResponder.moveRight(_:)):
                    // Enter a submenu only when the caret is at the very end.
                    guard caret >= textLength else { return false }
                    parent.enterSubmenu()
                case #selector(NSResponder.deleteBackward(_:)):
                    guard textLength == 0 else { return false }
                    parent.navigateBack()
                case #selector(NSResponder.insertNewline(_:)): parent.submit()
                case #selector(NSResponder.cancelOperation(_:)): parent.dismiss()
                default: return false
            }
            return true
        }
    }
}
