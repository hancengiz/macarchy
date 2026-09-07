@testable import AppBundle
import XCTest

@MainActor
final class TrayNoticeTest: XCTestCase {
    override func setUp() async throws {
        NoticeCenter.shared.reset()
        ShortcutConflicts.shared.reset()
        MessageModel.shared.message = nil
    }

    override func tearDown() async throws {
        NoticeCenter.shared.reset()
        MessageModel.shared.message = nil
    }

    // MARK: Panel frame geometry

    private let visibleFrame = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func testPanelFrameCentersUnderAnchorBelowMenuBar() {
        let anchor = CGRect(x: 485, y: 800, width: 30, height: 24)
        let frame = noticePanelFrame(anchor: anchor, visibleFrame: visibleFrame, contentSize: CGSize(width: 300, height: 100))
        XCTAssertEqual(frame.midX, anchor.midX, accuracy: 1)
        XCTAssertEqual(frame.maxY, anchor.minY - 7, accuracy: 1, "Panel must sit just below the workspace indicators")
    }

    func testPanelFrameClampsToScreenEdges() {
        let leftAnchor = CGRect(x: 0, y: 800, width: 30, height: 24)
        let leftFrame = noticePanelFrame(anchor: leftAnchor, visibleFrame: visibleFrame, contentSize: CGSize(width: 300, height: 80))
        XCTAssertGreaterThanOrEqual(leftFrame.minX, visibleFrame.minX + 8)

        let rightAnchor = CGRect(x: 970, y: 800, width: 30, height: 24)
        let rightFrame = noticePanelFrame(anchor: rightAnchor, visibleFrame: visibleFrame, contentSize: CGSize(width: 300, height: 80))
        XCTAssertLessThanOrEqual(rightFrame.maxX, visibleFrame.maxX - 8)
    }

    func testPanelFrameFallsBackToVisibleFrameTopWithoutAnchor() {
        let frame = noticePanelFrame(anchor: nil, visibleFrame: visibleFrame, contentSize: CGSize(width: 300, height: 80))
        XCTAssertEqual(frame.maxY, visibleFrame.maxY - 7, accuracy: 1)
    }

    func testPanelFrameCapsOversizedContent() {
        let frame = noticePanelFrame(anchor: nil, visibleFrame: visibleFrame, contentSize: CGSize(width: 5000, height: 5000))
        XCTAssertLessThanOrEqual(frame.width, visibleFrame.width - 16)
        XCTAssertLessThanOrEqual(frame.height, 320)
    }

    // MARK: Center semantics

    func testPostReplacesAndDismissesById() {
        let center = NoticeCenter.shared
        center.post(TrayNotice(id: "a", severity: .info, title: "A"))
        center.post(TrayNotice(id: "b", severity: .warning, title: "B"))
        XCTAssertEqual(center.current?.id, "b")
        center.dismiss(id: "a")
        XCTAssertEqual(center.current?.id, "b", "dismiss(id:) of a non-visible notice must be a no-op")
        center.dismiss()
        XCTAssertNil(center.current)
    }

    func testSameIdPostRefreshesInPlaceWithoutNewPresentation() {
        let center = NoticeCenter.shared
        center.post(TrayNotice(id: "a", severity: .warning, title: "Old"))
        XCTAssertEqual(center.presentations, 1)
        center.post(TrayNotice(id: "a", severity: .warning, title: "New"))
        XCTAssertEqual(center.current?.title, "New")
        XCTAssertEqual(center.presentations, 1, "Same-id refresh must not re-present")
        center.post(TrayNotice(id: "a", severity: .warning, title: "New"))
        XCTAssertEqual(center.presentations, 1, "Equal-content post must be a no-op")
    }

    func testRefreshIfShownOnlyUpdatesMatchingId() {
        let center = NoticeCenter.shared
        center.post(TrayNotice(id: "a", severity: .info, title: "A"))
        center.refreshIfShown(id: "b", notice: TrayNotice(id: "b", severity: .info, title: "B"))
        XCTAssertEqual(center.current?.title, "A")
        center.refreshIfShown(id: "a", notice: TrayNotice(id: "a", severity: .info, title: "A2"))
        XCTAssertEqual(center.current?.title, "A2")
        XCTAssertEqual(center.presentations, 1)
    }

    func testLifetimeAutoDismisses() async {
        let center = NoticeCenter.shared
        center.post(TrayNotice(id: "temp", severity: .success, title: "Done", lifetime: 0.05))
        XCTAssertNotNil(center.current)
        let dismissed = expectation(description: "auto-dismiss")
        Task { @MainActor in
            while NoticeCenter.shared.current != nil {
                try? await Task.sleep(for: .milliseconds(10))
            }
            dismissed.fulfill()
        }
        await fulfillment(of: [dismissed], timeout: 2)
    }

    // MARK: Conflict notice content

    func testConflictNoticeCompactWhenResolved() {
        let notice = shortcutConflictNotice(model: ShortcutConflicts.shared)
        XCTAssertEqual(notice.severity, .success)
        XCTAssertTrue(notice.rows.isEmpty)
        XCTAssertEqual(notice.actions.map(\.id), ["recheck"], "Resolved state must hide app-opening controls")
    }

    func testConflictNoticeListsRowsAndResolutionActions() {
        let model = ShortcutConflicts.shared
        model.update([ShortcutConflict(mode: "main", binding: "alt-t", reason: "Test")])
        let notice = shortcutConflictNotice(model: model)
        XCTAssertEqual(notice.severity, .warning)
        XCTAssertEqual(notice.rows.count, 1)
        XCTAssertEqual(notice.rows.first?.action?.id, "pause-main:alt-t")
        XCTAssertEqual(Set(notice.actions.map(\.id)), ["keyboard-settings", "recheck"])
        XCTAssertNotNil(notice.footer, "Checked time must be part of the notice")
    }
}
