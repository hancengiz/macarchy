import AppKit
import Combine
import Common
import SwiftUI

// Replaces SwiftUI MenuBarExtra with a manual NSStatusItem.
// Own reasons:
// * MenuBarExtra does not expose its NSStatusItem, so there is no reliable way
//   to anchor a notification panel below the workspace indicators (UI-04).
// * A manual NSStatusItem provides the exact button frame in screen coordinates.
// The label is rendered with the same MenuBarLabel SwiftUI view as before.

@MainActor private(set) var trayStatusItem: TrayStatusItem?

@MainActor
func initTrayStatusItem() {
    guard !isUnitTest, trayStatusItem == nil else { return }
    trayStatusItem = TrayStatusItem()
}

@MainActor
func trayStatusItemAnchor() -> CGRect? {
    trayStatusItem?.anchorRect()
}

@MainActor
final class TrayStatusItem: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellables: [AnyCancellable] = []
    /// Retained for the lifetime of the open menu; rebuilt on every menuNeedsUpdate.
    private var menuActions: [MenuAction] = []

    override init() {
        super.init()
        let model = TrayMenuModel.shared
        let button = statusItem.button
        button?.imagePosition = .imageOnly
        button?.imageScaling = .scaleProportionallyDown
        button?.setAccessibilityLabel(appName)
        statusItem.menu = buildMenu()
        Publishers.Merge3(
            model.$isEnabled.dropFirst().map { _ in () },
            model.$axPermissionStatus.dropFirst().map { _ in () },
            model.$trayItems.dropFirst().map { _ in () },
        ).sink { [weak self] _ in self?.refreshLabel() }
            .store(in: &cancellables)
        refreshLabel()
    }

    /// Frame of the status item button in screen coordinates, or nil when the item
    /// is not currently visible (e.g. auto-hidden menu bar in native fullscreen).
    func anchorRect() -> CGRect? {
        guard let button = unsafe statusItem.button, let window = unsafe button.window else { return nil }
        return window.convertToScreen(button.bounds)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menuActions = []
        menu.items = buildMenuItems()
    }

    // MARK: Label

    private func refreshLabel() {
        let model = TrayMenuModel.shared
        guard let button = statusItem.button else { return }
        switch (model.axPermissionStatus, model.isEnabled) {
            case (.granted, true):
                let color: Color = isDarkAppearance(button) ? .white : .black
                let label = MenuBarLabel(color: color).environmentObject(model)
                let renderer = ImageRenderer(content: label)
                renderer.proposedSize = ProposedViewSize(width: nil, height: NSStatusBar.system.thickness - 7)
                renderer.scale = (unsafe button.window)?.backingScaleFactor ?? 2
                guard let image = renderer.nsImage else { return }
                image.isTemplate = false // MenuBarLabel bakes in the menu-bar-appropriate color
                button.image = image
            case (.granted, false):
                button.image = NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: "Macarchy disabled")
            case (_, _):
                button.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Waiting for accessibility permission")
        }
    }

    private func isDarkAppearance(_ button: NSStatusBarButton) -> Bool {
        button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    // MARK: Menu content

    private func buildMenuItems() -> [NSMenuItem] {
        let viewModel = TrayMenuModel.shared
        var items: [NSMenuItem] = []

        let shortIdentification = "\(appName) v\(appVersion) \(gitShortHash)"
        items.append(header(shortIdentification))
        items.append(.separator())

        if viewModel.axPermissionStatus == .granted {
            if config.modes[omarchyMenuMode] != nil {
                items.append(action("Open macarchy Menu...") {
                    Task { await activateMode_nonCancellable(omarchyMenuMode) }
                })
            }
            items.append(.separator())

            if let token: RunSessionGuard = .isServerEnabled {
                items.append(header("Workspaces:"))
                for workspace in viewModel.workspaces {
                    let item = action(workspace.name + workspace.suffix, state: workspace.isFocused ? .on : .off) {
                        Task.startUnstructured {
                            try await runLightSession(.menuBarButton, token) {
                                _ = Workspace.get(byName: workspace.name).focusWorkspace()
                            }
                        }
                    }
                    item.attributedTitle = NSAttributedString(
                        string: workspace.name + workspace.suffix,
                        attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)],
                    )
                    items.append(item)
                }
                items.append(.separator())
            }

            items.append(action(viewModel.isEnabled ? "Disable" : "Enable", key: "e") {
                Task.startUnstructured {
                    try await runLightSession(.menuBarButton, .forceRun) {
                        _ = await EnableCommand(args: EnableCmdArgs(rawArgs: [], targetState: .toggle))
                            .run(.defaultEnv, .emptyStdin)
                    }
                }
            })

        } else {
            items.append(header("macarchy requires accessibility permission to move windows"))
        }
        items.append(action("Settings…", key: ",") {
            SettingsWindow.shared.show()
        })
        items.append(action("Restart Macarchy…") {
            Task { @MainActor in
                do { try await restartMacarchy() }
                catch { showSettingsError(error) }
            }
        })

        items.append(.separator())
        items.append(action("Quit \(appName)", key: "q") {
            Task.startUnstructured {
                terminationHandler?.beforeTermination()
                terminateApp()
            }
        })
        return items
    }

    // MARK: Item helpers

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(
        _ title: String,
        key: String = "",
        systemImage: String? = nil,
        state: NSControl.StateValue = .off,
        closure: @escaping () -> Void,
    ) -> NSMenuItem {
        let menuAction = MenuAction(closure)
        menuActions.append(menuAction)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.invoke), keyEquivalent: key)
        item.target = menuAction
        item.state = state
        if let systemImage {
            item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
        }
        return item
    }

}

/// Retains the closure behind an NSMenuItem target-action pair while the menu is open.
private final class MenuAction: NSObject {
    private let closure: () -> Void

    init(_ closure: @escaping () -> Void) {
        self.closure = closure
    }

    @objc func invoke() { closure() }
}
