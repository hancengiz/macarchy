@testable import AppBundle
import XCTest

final class SessionSnapshotTest: XCTestCase {
    private func window(_ id: UInt32, pid: Int32 = 20, launch: TimeInterval? = 100, title: String = "Project") -> SessionWindow {
        SessionWindow(
            id: id, pid: pid, launchDate: launch.map { Date(timeIntervalSince1970: $0) }, bundleID: "dev.editor", title: title,
            frame: nil, floatingSize: nil, fullscreen: false, noOuterGaps: false, nativeFullscreen: false, previouslyFloating: false,
        )
    }

    func testReusedProcessAndWindowIDsDoNotMatchWithoutLaunchIdentity() {
        let saved = window(1, launch: nil)
        XCTAssertEqual(matchSessionWindows(saved: [saved], live: [window(1, launch: nil)]), [:])
        XCTAssertEqual(matchSessionWindows(saved: [window(1)], live: [window(2)]), [:], "A closed window must not be replaced by another window in the same process")
        XCTAssertEqual(matchSessionWindows(saved: [window(1)], live: [window(1, launch: 200, title: "Unrelated")]), [:])
    }

    func testExactIdentitySurvivesTitleChanges() {
        XCTAssertEqual(matchSessionWindows(saved: [window(1)], live: [window(1, title: "Changed")]), [1: 1])
    }

    func testUniqueTitleFallbackOnlyAcrossRelaunch() {
        XCTAssertEqual(matchSessionWindows(saved: [window(1)], live: [window(9, pid: 30, launch: 200)]), [1: 9])
        XCTAssertEqual(matchSessionWindows(saved: [window(1)], live: [window(9, pid: 30, launch: 200), window(10, pid: 30, launch: 200)]), [:])
        XCTAssertEqual(matchSessionWindows(saved: [window(1), window(2)], live: [window(9, pid: 30, launch: 200)]), [:])
    }

    func testExactMatchDoesNotMakeAnAmbiguousTitleFallbackSafe() {
        let saved = [window(1), window(2)]
        let live = [window(1), window(9, pid: 30, launch: 200)]
        XCTAssertEqual(matchSessionWindows(saved: saved, live: live), [1: 1])
    }

    func testFloatingFrameFitsNegativeOriginAndSmallerDisplay() {
        let frame = SessionFrame(x: 3000, y: -3000, width: 2000, height: 100)
        let bounds = SessionFrame(x: -1920, y: 30, width: 1920, height: 1050)
        XCTAssertEqual(frame.fitted(to: bounds), SessionFrame(x: -1920, y: 30, width: 1920, height: 100))
    }

    func testDuplicateWindowPlacementAndFutureFormatAreRejected() throws {
        let leaf = SessionNode(window: 1, weight: 400, scrollingSize: 600, layout: "tiles", orientation: "h", scrollingOffset: 0, children: [])
        let root = SessionNode(window: nil, weight: 1, scrollingSize: nil, layout: "scrolling", orientation: "h", scrollingOffset: 120, children: [leaf])
        let workspace = SessionWorkspace(name: "1", displayUUID: "display", visible: true, root: root, floating: [1], nativeFullscreen: [], hidden: [])
        var snapshot = SessionSnapshot(windows: [window(1)], workspaces: [workspace], focusedWindow: 1, focusedWorkspace: "1")
        XCTAssertThrowsError(try snapshot.validate())
        snapshot.workspaces[0].floating = []
        snapshot.version = SessionSnapshot.currentVersion + 1
        XCTAssertThrowsError(try snapshot.validate())
        snapshot.version = SessionSnapshot.currentVersion
        snapshot.workspaces[0].root.children[0].weight = -.infinity
        XCTAssertThrowsError(try snapshot.validate())
    }

    func testInvalidReplacementKeepsLastDurableSession() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.json")
        var snapshot = SessionSnapshot(windows: [], workspaces: [], focusedWindow: nil, focusedWorkspace: "saved")
        try snapshot.writeAtomically(to: url)
        snapshot.version += 1
        snapshot.focusedWorkspace = "invalid replacement"
        XCTAssertThrowsError(try snapshot.writeAtomically(to: url))
        let stored = try JSONDecoder().decode(SessionSnapshot.self, from: Data(contentsOf: url))
        XCTAssertEqual(stored.focusedWorkspace, "saved")
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int, 0o600)
    }
}
