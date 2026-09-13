@testable import AppBundle
import Carbon
import HotKey
import XCTest

@MainActor
final class ShortcutConflictsTest: XCTestCase {
    override func setUp() async throws {
        setUpWorkspacesForTests()
        ShortcutConflicts.shared.reset()
        NoticeCenter.shared.reset()
        MessageModel.shared.message = nil
    }

    override func tearDown() async throws {
        MessageModel.shared.message = nil
        NoticeCenter.shared.reset()
    }

    func testNewConflictWarnsOnceUntilResolved() {
        let model = ShortcutConflicts.shared
        let conflict = ShortcutConflict(mode: "main", binding: "alt-t", reason: "Test")
        model.update([conflict])
        XCTAssertEqual(NoticeCenter.shared.current?.id, shortcutConflictNoticeId)
        NoticeCenter.shared.dismiss()
        model.update([conflict])
        XCTAssertNil(NoticeCenter.shared.current, "Dismissing a warning must not cause repeated popups")
        model.update([])
        model.update([conflict])
        XCTAssertEqual(NoticeCenter.shared.current?.id, shortcutConflictNoticeId)
    }

    func testConflictDoesNotReplaceConfigurationDiagnostic() {
        MessageModel.shared.message = Message(body: "Configuration error", containsWarnings: false)
        ShortcutConflicts.shared.update([ShortcutConflict(mode: "main", binding: "alt-t", reason: "Test")])
        XCTAssertEqual(MessageModel.shared.message?.type, .config)
        XCTAssertNil(NoticeCenter.shared.current, "Auto-warning must not pop while config diagnostics are open")
        XCTAssertEqual(ShortcutConflicts.shared.conflicts.count, 1)
    }

    func testResolvedCheckClearsRowsAndRecordsCompletion() {
        let model = ShortcutConflicts.shared
        model.update([ShortcutConflict(mode: "main", binding: "alt-t", reason: "Test")])
        model.update([])
        XCTAssertTrue(model.conflicts.isEmpty)
        XCTAssertNotNil(model.lastChecked)
        XCTAssertNil(model.checkStatus)
    }

    func testManualRecheckReportsDisabledManagerInsteadOfSilentlyReturning() async {
        let enabled = TrayMenuModel.shared.isEnabled
        defer { TrayMenuModel.shared.isEnabled = enabled }
        TrayMenuModel.shared.isEnabled = false
        await ShortcutConflicts.shared.recheck()
        XCTAssertEqual(ShortcutConflicts.shared.checkStatus, "Enable Macarchy to check shortcuts.")
        XCTAssertFalse(ShortcutConflicts.shared.isChecking)
    }

    func testSystemShortcutIsReportedWithoutRegistration() {
        let binding = HotkeyBinding(.option, .t, .cmd(FocusCommand.new(direction: .left)))
        let reason = shortcutRegistrationConflict(binding, systemCombos: [KeyCombo(key: .t, modifiers: .option)])
        XCTAssertTrue(reason?.contains("macOS system shortcut") == true)
    }

    func testRegistrationStatusMessages() {
        XCTAssertNil(shortcutRegistrationConflict(status: noErr))
        XCTAssertTrue(shortcutRegistrationConflict(status: OSStatus(eventHotKeyExistsErr))?.contains("does not identify the owner") == true)
        XCTAssertTrue(shortcutRegistrationConflict(status: -50)?.contains("error -50") == true)
    }

    func testExclusiveProbeDetectsAndReleasesActualCarbonReservation() throws {
        let binding = HotkeyBinding([.control, .option, .shift, .command], .f19, .cmd(FocusCommand.new(direction: .left)))
        let combo = KeyCombo(key: binding.keyCode, modifiers: binding.modifiers)
        var reservation: EventHotKeyRef?
        let status = unsafe RegisterEventHotKey(combo.carbonKeyCode, combo.carbonModifiers,
                                                EventHotKeyID(signature: 0x5445_5354, id: 1), GetEventDispatcherTarget(), OptionBits(kEventHotKeyExclusive), &reservation)
        // Headless CI may not have a WindowServer connection.
        try XCTSkipIf(status != noErr, "Carbon reservation unavailable: \(status)")
        XCTAssertNotNil(shortcutRegistrationConflict(binding, systemCombos: []))
        if let reservation = unsafe reservation { unsafe UnregisterEventHotKey(reservation) }
        XCTAssertNil(shortcutRegistrationConflict(binding, systemCombos: []))
        XCTAssertNil(shortcutRegistrationConflict(binding, systemCombos: []), "The probe must unregister itself")
    }

    func testDisableIsModeScopedAndResetOnReload() async {
        let model = ShortcutConflicts.shared
        await model.disable(ShortcutConflict(mode: "main", binding: "alt-t", reason: "Test"))
        XCTAssertTrue(model.isDisabled(mode: "main", binding: "alt-t"))
        XCTAssertFalse(model.isDisabled(mode: "resize", binding: "alt-t"))
        model.reset()
        XCTAssertFalse(model.isDisabled(mode: "main", binding: "alt-t"))
    }
}
