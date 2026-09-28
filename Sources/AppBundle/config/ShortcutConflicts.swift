import AppKit
import Carbon
import Common
import HotKey
import SwiftUI

struct ShortcutConflict: Identifiable, Equatable {
    let mode: String
    let binding: String
    let reason: String
    /// App-level collisions are informational: the binding stays registered.
    var advisory = false
    var id: String { "\(mode):\(binding)" }
}

@MainActor
final class ShortcutConflicts: ObservableObject {
    static let shared = ShortcutConflicts()
    @Published private(set) var conflicts: [ShortcutConflict] = []
    @Published private(set) var lastChecked: Date?
    @Published private(set) var checkStatus: String?
    @Published private(set) var isChecking = false
    private var announced: Set<String> = []
    private var monitor: Task<Void, Never>?

    func reset() {
        announced = []
        conflicts = []
        lastChecked = nil
        checkStatus = nil
        NoticeCenter.shared.dismiss(id: shortcutConflictNoticeId)
    }

    func update(_ conflicts: [ShortcutConflict]) {
        self.conflicts = conflicts.sorted { $0.id < $1.id }
        lastChecked = Date()
        checkStatus = nil
        let ids = Set(conflicts.filter { !$0.advisory }.map(\.id))
        let newConflicts = !ids.subtracting(announced).isEmpty
        announced = ids
        // Refresh a visible notice in place so Recheck results update without re-sliding.
        refreshVisibleNotice()
        if newConflicts && MessageModel.shared.message?.type != .config { show() }
    }

    func show() {
        NoticeCenter.shared.post(shortcutConflictNotice(model: self))
    }

    func recheck() async {
        guard !isChecking else { return }
        guard TrayMenuModel.shared.isEnabled else {
            checkStatus = "Enable Macarchy to check shortcuts."
            refreshVisibleNotice()
            return
        }
        guard !ModifierMouse.isDragging else {
            checkStatus = "Finish dragging the window, then recheck."
            refreshVisibleNotice()
            return
        }
        isChecking = true
        refreshVisibleNotice()
        defer {
            isChecking = false
            refreshVisibleNotice()
        }
        await activateMode_nonCancellable(activeMode, forceConflictCheck: true)
    }
    private func refreshVisibleNotice() {
        NoticeCenter.shared.refreshIfShown(id: shortcutConflictNoticeId, notice: shortcutConflictNotice(model: self))
    }

    func syncMonitor() {
        monitor?.cancel()
        monitor = nil
        guard config.warnAboutShortcutConflicts, !isUnitTest else { return }
        monitor = Task { @MainActor in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                // Do not change registrations under a held shortcut or during a modal operation.
                let modifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
                if activeMode == mainModeId && NSEvent.modifierFlags.intersection(modifiers).isEmpty {
                    await recheck()
                }
            }
        }
    }
}

@MainActor
func shortcutRegistrationConflict(_ binding: HotkeyBinding, systemCombos: [KeyCombo]) -> String? {
    let combo = KeyCombo(key: binding.keyCode, modifiers: binding.modifiers)
    if systemCombos.contains(combo) { return "Reserved by an enabled macOS system shortcut." }
    var probe: EventHotKeyRef?
    let status = unsafe RegisterEventHotKey(combo.carbonKeyCode, combo.carbonModifiers,
                                            EventHotKeyID(signature: 0x4145_524F, id: 0), GetEventDispatcherTarget(), OptionBits(kEventHotKeyExclusive), &probe)
    if let probe = unsafe probe { unsafe UnregisterEventHotKey(probe) }
    return shortcutRegistrationConflict(status: status)
}

func shortcutRegistrationConflict(status: OSStatus) -> String? {
    if status == noErr { return nil }
    if status == eventHotKeyExistsErr { return "Another global registration already uses this shortcut. macOS does not identify the owner." }
    return "macOS refused registration (error \(status)). The owner or cause is unavailable."
}

// MARK: Tray notice presentation (UI-04)

let shortcutConflictNoticeId = "shortcut-conflicts"

@MainActor
func shortcutConflictNotice(model: ShortcutConflicts) -> TrayNotice {
    let count = model.conflicts.filter { !$0.advisory }.count
    return TrayNotice(
        id: shortcutConflictNoticeId,
        severity: count > 0 ? .warning : .success,
        title: count > 0 ? "\(count) shortcut registration conflict\(count == 1 ? "" : "s")" : "Shortcut conflicts resolved",
        message: count > 0
            ? "Some shortcuts could not be registered. Review the affected bindings in Settings."
            : "No registration conflicts remain in the active mode.",
        actions: [
            TrayNoticeAction(id: "settings", label: "Review in Settings…") {
                SettingsWindow.shared.show()
            },
        ],
        lifetime: 8,
    )
}
