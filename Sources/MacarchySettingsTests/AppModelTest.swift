import XCTest
import Common
@testable import MacarchySettingsCore

@MainActor
final class AppModelTest: XCTestCase {
    func makeModel(
        original: String,
        written: ((String) -> Void)? = nil,
        answer: @escaping ([String]) async -> Result<ServerAnswer, ServerClientError>,
    ) -> AppModel {
        AppModel(
            loadText: { original },
            writeText: { text, _ in written?(text) },
            runServer: answer,
        )
    }

    func okAnswer() async -> Result<ServerAnswer, ServerClientError> {
        .success(ServerAnswer(exitCode: 0, stdout: "", stderr: "", serverVersionAndHash: "test"))
    }

    func rejectedAnswer() async -> Result<ServerAnswer, ServerClientError> {
        .success(ServerAnswer(exitCode: 1, stdout: "ERROR: unknown key 'nope'", stderr: "", serverVersionAndHash: "test"))
    }

    func testSaveCommitsEditsAndClearsDraft() async {
        let model = makeModel(original: "gaps.inner.horizontal = 10\n") { _ in } answer: { _ in await self.okAnswer() }
        await model.load()
        model.edit("gaps.inner.horizontal", toToml: "24")
        XCTAssertEqual(model.changes.map(\.keyPath), ["gaps.inner.horizontal"])
        await model.save()
        XCTAssertNil(model.saveError)
        XCTAssertTrue(model.changes.isEmpty)
        XCTAssertTrue(model.originalText.contains("24"))
    }

    func testSaveRollsBackFileWhenServerRejects() async {
        var writes: [String] = []
        let model = makeModel(
            original: "start-at-login = true\n",
            written: { writes.append($0) },
            answer: { args in args.first == "reload-config" ? await self.rejectedAnswer() : await self.okAnswer() },
        )
        await model.load()
        model.edit("start-at-login", toToml: "false")
        await model.save()
        XCTAssertNotNil(model.saveError)
        XCTAssertTrue(model.saveError!.contains("unknown key"))
        // Last write must be the restored original
        XCTAssertEqual(writes.last, "start-at-login = true\n")
        XCTAssertEqual(model.originalText, "start-at-login = true\n")
        // The draft is preserved so nothing is lost
        XCTAssertEqual(model.changes.map(\.keyPath), ["start-at-login"])
    }

    func testSyntaxGate() {
        XCTAssertTrue(ConfigDraft.syntaxIsValid("a = 1\nb = 'x'\n"))
        XCTAssertFalse(ConfigDraft.syntaxIsValid("a = = 1\n"))
        XCTAssertFalse(ConfigDraft.syntaxIsValid("[unterminated\n"))
    }

    func testEditAndDiscard() async {
        let model = makeModel(original: "a = true\n") { _ in } answer: { _ in await self.okAnswer() }
        await model.load()
        model.edit("a", toToml: "false")
        model.discard()
        XCTAssertTrue(model.changes.isEmpty)
        XCTAssertEqual(model.boolValue(path: "a"), true)
    }

    func testTypedAccessorsFallBackToOriginal() async {
        let model = makeModel(original: "n = 5\ns = 'tiles'\nb = true\n") { _ in } answer: { _ in await self.okAnswer() }
        await model.load()
        XCTAssertEqual(model.intValue(path: "n"), 5)
        XCTAssertEqual(model.stringValue(path: "s"), "tiles")
        XCTAssertEqual(model.boolValue(path: "b"), true)
        model.edit("n", toToml: "9")
        XCTAssertEqual(model.intValue(path: "n"), 9)
        XCTAssertEqual(model.intValue(path: "missing"), nil)
    }
}
