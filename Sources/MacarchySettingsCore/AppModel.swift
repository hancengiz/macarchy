import Common
import Foundation
import SwiftUI
import TOMLDecoder

@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var originalText: String = ""
    @Published public private(set) var edits: ConfigDraft.Edits = [:]
    @Published public private(set) var configUrl: URL?
    @Published public private(set) var configLocationProblem: String?
    @Published public private(set) var serverVersionAndHash: String?
    @Published public var saveError: String?
    /// Staged full-replacement row sets per mode ("mode.main" → rows).
    @Published public private(set) var modeEdits: [String: [BindingRow]] = [:]
    public let profileStore = ProfileStore()
    public let loadText: () -> String?
    public let writeText: (String, URL) -> Void
    public let runServer: ([String]) async -> Result<ServerAnswer, ServerClientError>
    private let server = ServerClient()

    public init(
        loadText: (() -> String?)? = nil,
        writeText: ((String, URL) -> Void)? = nil,
        runServer: (([String]) async -> Result<ServerAnswer, ServerClientError>)? = nil,
    ) {
        self.loadText = loadText ?? AppModel.readLiveConfig
        self.writeText = writeText ?? AppModel.writeLiveConfig
        self.runServer = runServer ?? { [server] in await server.run($0) }
    }
}

public struct BindingRow: Equatable, Identifiable {
    public var id: String { "\(mode)|\(chord)" }
    public let mode: String
    public var chord: String
    public var commandToml: String // raw TOML value, e.g. 'close' or ['mode main', 'close']

    public init(mode: String, chord: String, commandToml: String) {
        self.mode = mode
        self.chord = chord
        self.commandToml = commandToml
    }
}

extension AppModel {


    public func load() async {
        switch ConfigFileLocation.live() {
            case .file(let url):
                configUrl = url
                configLocationProblem = nil
                originalText = loadText() ?? ""
            case .ambiguousConfigError(let candidates):
                configUrl = nil
                configLocationProblem = "Ambiguous config location: \(candidates.map { $0.path(percentEncoded: false) }.joined(separator: ", "))"
                originalText = ""
            case .noCustomConfigExists:
                configUrl = nil
                configLocationProblem = "No config file found. Create ~/.macarchy.toml (macarchy/install.py does it for you)."
                originalText = ""
        }
        edits = [:]
        modeEdits = [:]
        saveError = nil
        if case .success(let answer) = await runServer([]) {
            serverVersionAndHash = answer.serverVersionAndHash
        }
    }

    public var draftText: String {
        var doc = TomlDocument(text: ConfigDraft.apply(edits, to: originalText))
        for (mode, rows) in modeEdits {
            _ = doc.replaceModeBindings(
                mode: mode,
                rows: rows.sorted { $0.chord < $1.chord }.map { ($0.chord, $0.commandToml) }
            )
        }
        return doc.text
    }

    public var changes: [ConfigChange] {
        var result = ConfigDraft.diff(edits: edits, original: TomlDocument(text: originalText))
        let originalDoc = TomlDocument(text: originalText)
        for (mode, rows) in modeEdits.sorted(by: { $0.key < $1.key }) {
            let oldRows = originalDoc.bindings(mode: mode)
            let newRows = rows.sorted { $0.chord < $1.chord }
            if oldRows.map({ "\($0.key)=\($0.valueToml)" }) == newRows.map({ "\($0.chord)=\($0.commandToml)" }) { continue }
            result.append(ConfigChange(
                keyPath: "mode.\(mode).binding",
                oldValueToml: "\(oldRows.count) bindings",
                newValueToml: "\(newRows.count) bindings",
            ))
        }
        return result
    }

    public var hasUnsavedChanges: Bool { !changes.isEmpty }

    public func edit(_ path: String, toToml value: String) { edits[path] = value }

    /// Stage a full replacement of one mode's binding rows.
    public func setModeRows(_ rows: [BindingRow], for mode: String) {
        modeEdits[mode] = rows
    }

    public func revertMode(mode: String) {
        modeEdits.removeValue(forKey: mode)
    }

    /// Rows shown in the editor: staged rows if any, else the original's.
    public func bindingRows(mode: String) -> [BindingRow] {
        if let staged = modeEdits[mode] { return staged }
        return TomlDocument(text: originalText).bindings(mode: mode).map {
            BindingRow(mode: mode, chord: $0.key, commandToml: $0.valueToml)
        }
    }

    /// All modes present in the original config file.
    public var availableModes: [String] {
        TomlDocument(text: originalText).text
            .split(separator: "\n")
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("[mode."), trimmed.hasSuffix(".binding]") else { return nil }
                return String(trimmed.dropFirst("[mode.".count).dropLast(".binding]".count))
            }
            .sorted()
    }

    /// Save the current draft keymap as a named profile.
    public func saveProfile(name: String) throws {
        let doc = TomlDocument(text: draftText)
        var out = ""
        for mode in availableModes {
            let rows = doc.bindings(mode: mode)
            guard !rows.isEmpty else { continue }
            out += "[mode.\(mode).binding]\n"
            out += rows.map { "\($0.key) = \($0.valueToml)" }.joined(separator: "\n") + "\n\n"
        }
        try profileStore.save(name, toml: out)
    }

    /// Stage every mode of a profile for the next Save (modes missing from
    /// the original file are skipped — v1 edits existing sections only).
    public func loadProfile(name: String) throws {
        guard let toml = try profileStore.load(name) else { return }
        let profileDoc = TomlDocument(text: toml)
        for mode in availableModes {
            let rows = profileDoc.bindings(mode: mode)
            if !rows.isEmpty || TomlDocument(text: originalText).bindings(mode: mode).isEmpty == false {
                setModeRows(
                    rows.map { BindingRow(mode: mode, chord: $0.key, commandToml: $0.valueToml) },
                    for: mode,
                )
            }
        }
    }

    public func discard() {
        edits = [:]
        modeEdits = [:]
        saveError = nil
    }

    // Typed accessors: draft value if edited, else parsed original.
    public func boolValue(path: String) -> Bool? { rawValue(path: path).flatMap(TomlValue.parseBool) }
    public func intValue(path: String) -> Int? { rawValue(path: path).flatMap(TomlValue.parseInt) }
    public func stringValue(path: String) -> String? { rawValue(path: path).flatMap(TomlValue.parseString) }

    public func rawValue(path: String) -> String? {
        if let edited = edits[path] { return edited }
        return TomlDocument(text: originalText).getValue(path: path.split(separator: ".").map(String.init))
    }

    public func save() async {
        saveError = nil
        guard let url = configUrl, hasUnsavedChanges else { return }
        let newText = draftText
        guard ConfigDraft.syntaxIsValid(newText) else {
            saveError = "The edited config is not valid TOML."
            return
        }
        writeText(newText, url)
        switch await runServer(["reload-config"]) {
            case .success(let answer) where answer.exitCode == 0:
                originalText = newText
                edits = [:]
                modeEdits = [:]
            case .success(let answer):
                writeText(originalText, url) // rollback the file; server kept last-good config
                _ = await runServer(["reload-config"])
                saveError = answer.stdout.isEmpty ? "The server rejected the config." : answer.stdout
            case .failure(let error):
                writeText(originalText, url)
                saveError = "\(error) Your edits are still in the draft (nothing was saved)."
        }
    }

    // MARK: Live IO

    nonisolated private static func readLiveConfig() -> String? {
        guard let url = ConfigFileLocation.live().urlOrNil else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    nonisolated private static func writeLiveConfig(_ text: String, _ url: URL) {
        let temporary = url.deletingLastPathComponent()
            .appending(path: ".\(url.lastPathComponent).tmp-\(UUID().uuidString.prefix(8))")
        do {
            try text.write(to: temporary, atomically: true, encoding: .utf8)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } catch {
            // A failed write leaves the original file untouched; the next save retries.
        }
    }
}

// MARK: SwiftUI binding helpers

extension AppModel {
    public func binding(path: String, default defaultValue: String) -> Binding<String> {
        Binding(
            get: { self.stringValue(path: path) ?? defaultValue },
            set: { self.edit(path, toToml: TomlValue.format(string: $0)) }
        )
    }

    public func binding(path: String, default defaultValue: Bool) -> Binding<Bool> {
        Binding(
            get: { self.boolValue(path: path) ?? defaultValue },
            set: { self.edit(path, toToml: TomlValue.format(bool: $0)) }
        )
    }

    public func intBinding(path: String, default defaultValue: Int) -> Binding<Int> {
        Binding(
            get: { self.intValue(path: path) ?? defaultValue },
            set: { self.edit(path, toToml: TomlValue.format(int: $0)) }
        )
    }

    public func doubleBinding(path: String, default defaultValue: Double) -> Binding<Double> {
        Binding(
            get: { Double(self.intValue(path: path) ?? Int(defaultValue)) },
            set: { self.edit(path, toToml: TomlValue.format(int: Int($0.rounded()))) }
        )
    }
}

extension ConfigDraft {
    /// Engine-adjacent syntax gate. Full validation is the server's job (reload-config).
    public static func syntaxIsValid(_ text: String) -> Bool {
        (try? TOMLTable(source: text)) != nil
    }
}
