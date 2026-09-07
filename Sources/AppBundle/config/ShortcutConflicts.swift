import AppKit
import Carbon
import Common
import HotKey
import SwiftUI

struct ShortcutConflict: Identifiable, Equatable {
    let mode: String
    let binding: String
    let reason: String
    var id: String { "\(mode):\(binding)" }
}

@MainActor
final class ShortcutConflicts: ObservableObject {
    static let shared = ShortcutConflicts()
    @Published private(set) var conflicts: [ShortcutConflict] = []
    @Published private(set) var lastChecked: Date?
    @Published private(set) var checkStatus: String?
    @Published private(set) var isChecking = false
    private var disabled: Set<String> = []
    private var announced: Set<String> = []
    private var monitor: Task<Void, Never>?

    func isDisabled(mode: String, binding: String) -> Bool { disabled.contains("\(mode):\(binding)") }

    func reset() {
        disabled = []
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
        let ids = Set(conflicts.map(\.id))
        let newConflicts = !ids.subtracting(announced).isEmpty
        announced = ids
        // Refresh a visible notice in place so Recheck results update without re-sliding.
        refreshVisibleNotice()
        if newConflicts && MessageModel.shared.message?.type != .config { show() }
    }

    func show() {
        NoticeCenter.shared.post(shortcutConflictNotice(model: self))
    }

    func disable(_ conflict: ShortcutConflict) async {
        disabled.insert(conflict.id)
        await recheck()
    }

    func recheck() async {
        guard !isChecking else { return }
        guard TrayMenuModel.shared.isEnabled else {
            checkStatus = "Enable AeroSpace to check shortcuts."
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
        var notice = shortcutConflictNotice(model: self)
        if let current = NoticeCenter.shared.current, current.id == shortcutConflictNoticeId {
            // Keep the visible notice's footer so unchanged data dedups to a no-op
            // instead of re-rendering on every monitor cycle's fresh timestamp.
            notice.footer = current.footer
        }
        NoticeCenter.shared.refreshIfShown(id: shortcutConflictNoticeId, notice: notice)
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
    let hasConflicts = !model.conflicts.isEmpty
    let checking = model.isChecking
    let rows: [TrayNoticeRow] = model.conflicts.map { conflict in
        TrayNoticeRow(
            title: conflict.binding,
            detail: conflict.reason,
            action: TrayNoticeAction(
                id: "pause-\(conflict.id)",
                label: "Pause",
                tooltip: "Pauses this binding until config reload",
                handler: { Task { @MainActor in await model.disable(conflict) } },
            ),
        )
    }
    var actions: [TrayNoticeAction] = []
    if hasConflicts {
        actions.append(TrayNoticeAction(id: "keyboard-settings", label: "Keyboard Settings", tooltip: "Open macOS Keyboard settings") {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension").orDie())
        })
    }
    actions.append(TrayNoticeAction(id: "recheck", label: checking ? "Checking…" : "Recheck", tooltip: "Re-run shortcut conflict detection") {
        Task { @MainActor in await model.recheck() }
    })
    var footer: [String] = []
    if let date = model.lastChecked { footer.append("Checked \(date.formatted(date: .omitted, time: .standard))") }
    if let status = model.checkStatus { footer.append(status) }
    let extra: AnyView? = hasConflicts ? AnyView(RunningAppsMenu()) : nil
    return TrayNotice(
        id: shortcutConflictNoticeId,
        severity: checking ? .info : (hasConflicts ? .warning : .success),
        title: checking ? "Checking shortcuts…" : (hasConflicts ? "\(model.conflicts.count) conflicting shortcut(s)" : "No conflicts detected"),
        message: hasConflicts && !checking ? "Conflicting shortcuts are paused until resolved." : nil,
        rows: rows,
        actions: actions,
        footer: footer.isEmpty ? nil : footer.joined(separator: " · "),
        extra: extra,
    )
}
