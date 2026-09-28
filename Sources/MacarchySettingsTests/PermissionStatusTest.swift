import XCTest
import Common
@testable import MacarchySettingsCore

@MainActor
final class PermissionStatusTest: XCTestCase {
    func testUnreachableServer() async {
        let model = PermissionStatusModel(probe: { .failure(.cannotConnect) })
        await model.refresh()
        XCTAssertEqual(model.state, .serverNotRunning)
    }

    func testServerRunningAndManagingWindows() async {
        let model = PermissionStatusModel(probe: {
            .success(ServerAnswer(exitCode: 0, stdout: "3\n", stderr: "", serverVersionAndHash: "v"))
        })
        await model.refresh()
        XCTAssertEqual(model.state, .granted(windowsCount: 3))
    }

    func testServerRunningWithoutWindowsMeansUnresolved() async {
        let model = PermissionStatusModel(probe: {
            .success(ServerAnswer(exitCode: 0, stdout: "0\n", stderr: "", serverVersionAndHash: "v"))
        })
        await model.refresh()
        XCTAssertEqual(model.state, .waiting)
    }

    func testCommandFailureMeansUnresolved() async {
        let model = PermissionStatusModel(probe: {
            .success(ServerAnswer(exitCode: 1, stdout: "", stderr: "ERROR", serverVersionAndHash: "v"))
        })
        await model.refresh()
        XCTAssertEqual(model.state, .waiting)
    }
}
