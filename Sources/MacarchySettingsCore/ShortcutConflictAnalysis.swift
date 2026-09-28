import Foundation

public enum ConflictSeverity: Equatable {
    case dead(name: String)
    case dormant(name: String)
    case reserved(name: String)
    case textEditing
}

public struct ConflictRow: Identifiable, Equatable {
    public let mode: String
    public let chord: String
    public let severity: ConflictSeverity
    public var id: String { "\(mode).\(chord)" }

    public var explanation: String {
        switch severity {
            case .dead(let name): "macOS owns this chord (\(name) is enabled) — this binding never fires."
            case .dormant(let name): "Matches the \(name) system shortcut (currently off). It takes the chord back if you enable it."
            case .reserved(let name): "\(name) is hard-wired in macOS — this binding never fires."
            case .textEditing: "macOS uses Option-chords for text input (word jump, special characters) — typing in text fields loses them."
        }
    }
}

public struct CatalogEntry: Equatable {
    public let mode: String
    public let chord: String
    public let command: String // raw TOML value
}

public struct ModeCatalog: Equatable {
    public let mode: String
    public let bindings: [CatalogEntry]
}

public struct ShortcutConflictAnalysis {
    let configText: String
    let system: SystemShortcuts

    public init(configText: String, system: SystemShortcuts) {
        self.configText = configText
        self.system = system
    }

    public func conflictRows() -> [ConflictRow] {
        var rows: [ConflictRow] = []
        for mode in modeNames() {
            for binding in TomlDocument(text: configText).bindings(mode: mode) {
                if let row = classify(mode: mode, chord: binding.key) {
                    rows.append(row)
                }
            }
        }
        return rows.sorted { $0.chord < $1.chord }
    }

    public func catalog() -> [ModeCatalog] {
        modeNames()
            .sorted()
            .map { mode in
                ModeCatalog(
                    mode: mode,
                    bindings: TomlDocument(text: configText).bindings(mode: mode).map {
                        CatalogEntry(mode: mode, chord: $0.key, command: $0.valueToml)
                    }
                )
            }
            .filter { !$0.bindings.isEmpty }
    }

    private func modeNames() -> [String] {
        var modes: [String] = []
        for line in configText.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[mode."), trimmed.hasSuffix(".binding]") {
                modes.append(String(trimmed.dropFirst("[mode.".count).dropLast(".binding]".count)))
            }
        }
        return modes
    }

    private func classify(mode: String, chord: String) -> ConflictRow? {
        if let systemClass = system.classify(chord: chord) {
            let severity: ConflictSeverity
            switch systemClass {
                case .dead(let name): severity = .dead(name: name)
                case .dormant(let name): severity = .dormant(name: name)
                case .reserved(let name): severity = .reserved(name: name)
            }
            return ConflictRow(mode: mode, chord: chord, severity: severity)
        }
        // Option-chord text-input loss: alt (no cmd/ctrl) + single letter or arrow.
        let parts = SystemShortcuts.normalize(chord)
        if parts.contains("alt"), !parts.contains("cmd"), !parts.contains("ctrl"), parts.count == 2 {
            let key = parts.last!
            if key.count == 1 || ["left", "right", "up", "down"].contains(key) {
                return ConflictRow(mode: mode, chord: chord, severity: .textEditing)
            }
        }
        return nil
    }
}
