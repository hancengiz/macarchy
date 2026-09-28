import XCTest
@testable import MacarchySettingsCore

/// Live integration smoke against the running WM server (skips when the server is down).
final class LiveServerSmokeTest: XCTestCase {
    func testListMonitorsOverSocket() async throws {
        let result = await ServerClient().run(["list-monitors", "--count"])
        switch result {
            case .success(let answer):
                XCTAssertEqual(answer.exitCode, 0, "stdout: \(answer.stdout) stderr: \(answer.stderr)")
                XCTAssertFalse(answer.stdout.isEmpty)
                XCTAssertFalse(answer.serverVersionAndHash.isEmpty)
            case .failure(let error):
                throw XCTSkip("Server not running: \(error)")
        }
    }
}
