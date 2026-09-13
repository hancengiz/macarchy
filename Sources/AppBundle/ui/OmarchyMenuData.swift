import AppKit
import Common
import Foundation

// Omarchy-style menu data model (UI-03). Ports the reference semantics from
// omarchy/shell/plugins/menu/MenuModel.js and docs/menu.md:
// * flat JSONC tree addressed by dotted ids (no nested objects in the data),
// * per-key merge of the user extension onto shipped defaults (order preserved),
// * multi-term search: name-substring or description-whole-word, tiered scoring,
// * batched bash guards (when/checked/disabled),
// * runtime providers ("apps") whose rows are searchable but never routable.
// Deviations from Omarchy are documented in the shipped omarchy-menu.jsonc header.

// MARK: Node

struct OmarchyMenuNode: Equatable {
    enum Kind: Equatable {
        case menu
        case link
        case action
    }

    let id: String
    var label: String
    var title: String?
    var icon: String?
    var action: String?
    var target: String?
    var provider: String?
    var aliases: [String] = []
    var description: String?
    var when: String?
    var checked: String?
    var disabled: String?
    /// macOS addition: provider app exclusion by app name (case-insensitive, with or without .app).
    var exclude: [String] = []
    var order: Int = 0

    var kind: Kind {
        if action != nil { return .action }
        if target != nil { return .link }
        return .menu
    }

    var parent: String {
        if id == "root" { return "" }
        if let lastDot = id.lastIndex(of: "."), id.distance(from: id.startIndex, to: lastDot) > 0 {
            return String(id[id.startIndex ..< lastDot])
        }
        return "root"
    }

    var depth: Int { id.split(separator: ".").count }
}

// MARK: Display row

struct OmarchyMenuRow: Identifiable, Equatable {
    let id: String
    /// Backing node; nil for provider rows.
    let node: OmarchyMenuNode?
    let label: String
    /// SF Symbol name; nil when the row carries an app icon path instead.
    let icon: String?
    /// Provider app rows: bundle path to launch.
    let appPath: String?
    var detail: String?
    let isSubmenu: Bool
    let isDisabled: Bool
    let isChecked: Bool
    /// Separator between current-menu and drilldown search results.
    var isDivider: Bool = false
    var score: Int = 0
    /// In-process activation for provider rows (e.g. keybinding triggers). Not part of equality.
    var handler: (@MainActor () -> Void)? = nil

    static func == (lhs: OmarchyMenuRow, rhs: OmarchyMenuRow) -> Bool {
        lhs.id == rhs.id && lhs.label == rhs.label && lhs.detail == rhs.detail && lhs.isSubmenu == rhs.isSubmenu
            && lhs.isDisabled == rhs.isDisabled && lhs.isChecked == rhs.isChecked && lhs.isDivider == rhs.isDivider
    }
}

// MARK: JSONC dialect

func stripJsonc(_ raw: String) -> String {
    // Whole-line // comments only, exactly like Omarchy's stripJsonc.
    let withoutComments = raw.split(separator: "\n", omittingEmptySubsequences: false)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        .joined(separator: "\n")
    // Trailing commas before } or ].
    guard let regex = try? NSRegularExpression(pattern: ",(\\s*[\\}\\]])") else { return withoutComments }
    let range = NSRange(withoutComments.startIndex ..< withoutComments.endIndex, in: withoutComments)
    return regex.stringByReplacingMatches(in: withoutComments, range: range, withTemplate: "$1")
}

// MARK: Parsing

/// Parses one JSONC source. Returns nil on any parse failure; a broken source
/// contributes nothing while the rest of the menu keeps working (reference semantics).
func parseMenuJsonc(_ raw: String) -> [OmarchyMenuNode]? {
    guard let data = stripJsonc(raw).data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    let entries = (object["items"] as? [String: Any]) ?? object
    // JSONSerialization drops key order; recover it with a regex scan. The dialect
    // forbids nested objects, so every `"id": {` occurrence is a top-level node.
    guard let keyRegex = try? NSRegularExpression(pattern: "\"([A-Za-z0-9._-]+)\"\\s*:\\s*\\{") else { return nil }
    let text = stripJsonc(raw)
    let range = NSRange(text.startIndex ..< text.endIndex, in: text)
    var orderedKeys: [String] = []
    unsafe keyRegex.enumerateMatches(in: text, range: range) { match, _, _ in
        guard let match,
              let keyRange = Range(match.range(at: 1), in: text)
        else { return }
        let key = String(text[keyRange])
        if entries[key] != nil, !orderedKeys.contains(key) { orderedKeys.append(key) }
    }
    var seen = Set(orderedKeys)
    for key in entries.keys where !seen.contains(key) {
        orderedKeys.append(key)
        seen.insert(key)
    }
    var nodes: [OmarchyMenuNode] = []
    for (index, key) in orderedKeys.enumerated() {
        guard let fields = entries[key] as? [String: Any] else { continue }
        nodes.append(OmarchyMenuNode(
            id: key,
            label: fields["label"] as? String ?? key,
            title: fields["title"] as? String,
            icon: fields["icon"] as? String,
            action: fields["action"] as? String,
            target: fields["target"] as? String,
            provider: fields["provider"] as? String,
            aliases: (fields["aliases"] as? [String]) ?? (fields["aliases"] as? String).map { [$0] } ?? [],
            description: fields["description"] as? String,
            when: fields["when"] as? String,
            checked: fields["checked"] as? String,
            disabled: fields["disabled"] as? String,
            exclude: fields["exclude"] as? [String] ?? [],
            order: index,
        ))
    }
    return nodes
}

// MARK: Merge

/// Same-id entries merge per field and keep the default position; new ids append
/// in first-seen order. A synthetic "root" is injected when neither source declares one.
func mergeMenuSources(defaults: [OmarchyMenuNode], extensions: [OmarchyMenuNode]) -> [String: OmarchyMenuNode] {
    var merged: [String: OmarchyMenuNode] = [:]
    var order: [String] = []
    for node in defaults {
        merged[node.id] = node
        order.append(node.id)
    }
    for node in extensions {
        if var existing = merged[node.id] {
            existing.label = node.label
            existing.title = node.title ?? existing.title
            existing.icon = node.icon ?? existing.icon
            existing.action = node.action ?? existing.action
            existing.target = node.target ?? existing.target
            existing.provider = node.provider ?? existing.provider
            existing.aliases = node.aliases.isEmpty ? existing.aliases : node.aliases
            existing.description = node.description ?? existing.description
            existing.when = node.when ?? existing.when
            existing.checked = node.checked ?? existing.checked
            existing.disabled = node.disabled ?? existing.disabled
            existing.exclude = node.exclude.isEmpty ? existing.exclude : node.exclude
            merged[node.id] = existing
        } else {
            merged[node.id] = node
            order.append(node.id)
        }
    }
    if merged["root"] == nil {
        merged["root"] = OmarchyMenuNode(id: "root", label: "Go", icon: "square.grid.2x2")
        order.insert("root", at: 0)
    }
    for (index, id) in order.enumerated() { merged[id]?.order = index }
    return merged
}

// MARK: Guards

struct GuardResults: Equatable {
    var whenHidden: Set<String> = []
    var checkedTrue: Set<String> = []
    var disabledTrue: Set<String> = []

    static let empty = GuardResults()

    func isVisible(_ node: OmarchyMenuNode) -> Bool { !whenHidden.contains(node.id) }
    func isChecked(_ node: OmarchyMenuNode) -> Bool { checkedTrue.contains(node.id) }
    /// `disabled: "true"` is the documented way to unconditionally disable a row.
    func isDisabled(_ node: OmarchyMenuNode) -> Bool {
        disabledTrue.contains(node.id) || node.disabled == "true"
    }
}

/// One bash script evaluating every guard, emitting `id:<w|c|d>:<0|1>` lines,
/// mirroring Omarchy's batched guardScript.
func guardScript(nodes: [OmarchyMenuNode]) -> String {
    var lines: [String] = []
    for node in nodes {
        for (field, letter) in [(node.when, "w"), (node.checked, "c"), (node.disabled, "d")] where field != nil {
            lines.append("if \(field!); then echo \"\(node.id):\(letter):1\"; else echo \"\(node.id):\(letter):0\"; fi")
        }
    }
    return lines.joined(separator: "\n")
}

/// Parses batched guard output. `when` hides when its condition FAILS; checked
/// and disabled apply when their conditions succeed. Malformed lines are ignored;
/// the caller discards the whole batch when the process failed (last complete wins).
func parseGuardOutput(_ output: String) -> GuardResults {
    var results = GuardResults.empty
    for line in output.split(separator: "\n") {
        let parts = line.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3 else { continue }
        switch (parts[1], parts[2]) {
            case ("w", "0"): results.whenHidden.insert(String(parts[0]))
            case ("c", "1"): results.checkedTrue.insert(String(parts[0]))
            case ("d", "1"): results.disabledTrue.insert(String(parts[0]))
            default: continue
        }
    }
    return results
}

// MARK: Search

func normalizeForSearch(_ text: String) -> String {
    text.lowercased().map { character in
        "._-".contains(character) ? " " : String(character)
    }.joined()
}

func nameText(node: OmarchyMenuNode) -> String {
    let lastSegment = node.id.split(separator: ".").last.map(String.init) ?? node.id
    return normalizeForSearch(([node.label, lastSegment] + node.aliases).joined(separator: " "))
}

func searchWords(description: String?) -> Set<String> {
    Set((description ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init))
}

/// Every whitespace-separated term must match: name text by substring or
/// description by whole word. Disabled rows never match.
func matchesQuery(node: OmarchyMenuNode, guards: GuardResults, query: String) -> Bool {
    guard !guards.isDisabled(node) else { return false }
    let haystack = nameText(node: node)
    let words = searchWords(description: node.description)
    return query.split(whereSeparator: \.isWhitespace).allSatisfy { term in
        let term = String(term).lowercased()
        return haystack.contains(term) || words.contains(term)
    }
}

/// Tiered scoring ported from Omarchy's searchScore: lower sorts first.
func searchScore(node: OmarchyMenuNode, isAppRow: Bool, query: String) -> Int {
    let normalizedQuery = normalizeForSearch(query.trimmingCharacters(in: .whitespaces))
    let label = normalizeForSearch(node.label)
    var base: Int = if !normalizedQuery.isEmpty && label == normalizedQuery {
        node.id == "root" ? 2 : 0
    } else if isAppRow && !normalizedQuery.isEmpty && label.split(separator: " ").map(String.init).contains(normalizedQuery) {
        0
    } else if !normalizedQuery.isEmpty && label.hasPrefix(normalizedQuery) {
        10
    } else if !normalizedQuery.isEmpty && label.contains(normalizedQuery) {
        30
    } else if nameText(node: node).contains(normalizedQuery) {
        40
    } else if searchWords(description: node.description).contains(normalizedQuery) {
        60
    } else {
        80
    }
    switch node.kind {
        case .menu, .link: base -= 2
        case .action: break
    }
    if isAppRow { base -= 5 }
    return base * 1000 + node.depth * 25 + node.order
}

// MARK: Apps provider

func slugify(_ name: String) -> String {
    let slug = name.lowercased()
        .replacingOccurrences(of: ".app", with: "")
        .map { character in
            character.isLetter || character.isNumber ? String(character) : "-"
        }
        .joined()
    return slug.split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
}

/// Scans the standard application locations (one level deep for subfolders like
/// Utilities) and builds provider rows. App rows are searchable but never routable.
func appsProviderRows(parentId: String, exclude: [String]) -> [OmarchyMenuRow] {
    let excluded = Set(exclude.map { slugify($0) })
    let fileManager = FileManager.default
    let home = fileManager.homeDirectoryForCurrentUser
    var candidates: [String] = []
    for directory in ["/System/Applications", "/Applications", home.appending(path: "Applications").path] {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }
        for entry in entries.sorted() where entry.hasSuffix(".app") {
            candidates.append("\(directory)/\(entry)")
        }
        // One level of subdirectories (Utilities, etc.).
        for entry in entries.sorted() {
            let sub = "\(directory)/\(entry)"
            var isDirectory: ObjCBool = false
            guard !entry.hasSuffix(".app"),
                  unsafe fileManager.fileExists(atPath: sub, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  let subEntries = try? fileManager.contentsOfDirectory(atPath: sub)
            else { continue }
            for subEntry in subEntries.sorted() where subEntry.hasSuffix(".app") {
                candidates.append("\(sub)/\(subEntry)")
            }
        }
    }
    var rows: [OmarchyMenuRow] = []
    var usedIds = Set<String>()
    for path in candidates {
        let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let slug = slugify(name)
        guard !excluded.contains(slug) else { continue }
        var id = "\(parentId).\(slug)"
        while usedIds.contains(id) { id += "-" }
        usedIds.insert(id)
        rows.append(OmarchyMenuRow(
            id: id,
            node: nil,
            label: name,
            icon: nil,
            appPath: path,
            isSubmenu: false,
            isDisabled: false,
            isChecked: false,
        ))
    }
    return rows
}

/// Omarchy-style "Trigger" category: one row per live main-mode binding.
/// Selecting the row fires the binding through the same path a real keypress uses.
@MainActor
func keybindingsProviderRows(bindings: [String: HotkeyBinding]) -> [OmarchyMenuRow] {
    bindings.values
        .sorted { $0.descriptionWithKeyNotation < $1.descriptionWithKeyNotation }
        .map { binding in
            OmarchyMenuRow(
                id: "keybindings.\(binding.descriptionWithKeyNotation)",
                node: nil,
                label: binding.descriptionWithKeyNotation,
                icon: "keyboard",
                appPath: nil,
                detail: binding.commands.shellOfCommandsDescription,
                isSubmenu: false,
                isDisabled: false,
                isChecked: false,
                handler: {
                    NSLog("MACARCHY-MENU handler start: \(binding.descriptionWithKeyNotation)")
                    Task.startUnstructured {
                        broadcastEvent(.bindingTriggered(mode: mainModeId, binding: binding.descriptionWithKeyNotation))
                        // The menu panel just resigned key focus; give macOS a beat to
                        // restore focus to the underlying window so focus-targeting
                        // commands (layout, close, resize...) see a focused window.
                        try? await Task.sleep(for: .milliseconds(200))
                        for attempt in 0 ..< 3 {
                            let exitCode = try await runLightSession(.hotkeyBinding, .checkServerIsEnabledOrDie()) { () throws -> Int32ExitCode in
                                await binding.commands.run(.defaultEnv, CmdIoImpl.emptyStdinIgnoringOut)
                            }
                            if exitCode.rawValue == 0 {
                                NSLog("MACARCHY-MENU binding fired on attempt \(attempt): \(binding.descriptionWithKeyNotation)")
                                return
                            }
                            try? await Task.sleep(for: .milliseconds(250))
                        }
                        NSLog("MACARCHY-MENU binding FAILED after retries: \(binding.descriptionWithKeyNotation)")
                    }
                    NSLog("MACARCHY-MENU handler task scheduled: \(binding.descriptionWithKeyNotation)")
                },
            )
        }
}
// MARK: Store

@MainActor
final class OmarchyMenuStore: ObservableObject {
    static let shared = OmarchyMenuStore()

    @Published var nodes: [String: OmarchyMenuNode] = [:]
    @Published private(set) var userParseError: String?
    @Published var guards = GuardResults.empty
    @Published private(set) var appsExclude: [String] = []

    let userMenuUrl = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".config/macarchy/menu.jsonc")

    private var defaultNodes: [OmarchyMenuNode] = []
    private var lastGoodUserNodes: [OmarchyMenuNode]? = nil
    private var watcher: ConfigFileWatcher?
    private var watcherDebounce: Task<Void, Never>?

    private init() {}

    func load() {
        defaultNodes = defaultMenuNodes()
        reloadUserFile(startWatcher: true)
        rebuild()
    }

    /// Re-reads the user extension. A parse failure keeps the last-known-good
    /// extension and surfaces the error; the menu itself stays usable.
    func reloadUserFile(startWatcher: Bool = false) {
        do {
            let raw = try String(contentsOf: userMenuUrl, encoding: .utf8)
            if let parsed = parseMenuJsonc(raw) {
                lastGoodUserNodes = parsed
                userParseError = nil
            } else {
                userParseError = "menu.jsonc failed to parse. Whole-line // comments and trailing commas are allowed; inline comments are not. Last-known-good entries are in use."
            }
        } catch {
            // A missing file is the normal state; it contributes nothing.
            lastGoodUserNodes = nil
            userParseError = nil
        }
        if startWatcher { watcher = ConfigFileWatcher(url: userMenuUrl) { [weak self] in self?.scheduleReload() } }
    }

    private func scheduleReload() {
        watcherDebounce?.cancel()
        watcherDebounce = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.reloadUserFile()
            self?.rebuild()
            if let error = self?.userParseError, let url = self?.userMenuUrl {
                postMenuParseErrorNotice(error: error, url: url)
            }
        }
    }

    private func rebuild() {
        nodes = mergeMenuSources(defaults: defaultNodes, extensions: lastGoodUserNodes ?? [])
        appsExclude = nodes["apps"]?.exclude ?? []
        evaluateGuards()
    }

    private func evaluateGuards() {
        let script = guardScript(nodes: Array(nodes.values))
        guard !script.isEmpty else {
            guards = GuardResults.empty
            return
        }
        Task { @MainActor [weak self] in
            // Failed/partial batches are discarded in favor of the last complete set.
            guard let output = await runGuardScript(script) else { return }
            self?.guards = parseGuardOutput(output)
        }
    }

    /// Rows for a submenu: static JSONC children, then provider rows.
    func rows(for menuId: String) -> [OmarchyMenuRow] {
        let children = nodes.values
            .filter { $0.parent == menuId }
            .sorted { $0.order < $1.order }
        var result: [OmarchyMenuRow] = children.compactMap { node in
            guard guards.isVisible(node) else { return nil }
            return OmarchyMenuRow(
                id: node.id,
                node: node,
                label: node.label,
                icon: node.icon,
                appPath: nil,
                detail: nil,
                isSubmenu: node.kind != .action,
                isDisabled: guards.isDisabled(node),
                isChecked: guards.isChecked(node),
            )
        }
        result += providerRows(menuId: menuId)
        return result
    }

    /// Runtime row sources: "apps" (installed applications) and "keybindings"
    /// (live main-mode shortcuts that can be triggered from the menu).
    private func providerRows(menuId: String) -> [OmarchyMenuRow] {
        switch nodes[menuId]?.provider {
            case "apps":
                return appsProviderRows(parentId: menuId, exclude: appsExclude)
            case "keybindings":
                return keybindingsProviderRows(bindings: config.modes[mainModeId]?.bindings ?? [:])
            default:
                return []
        }
    }

    /// rows included), then drilldown matches from deeper levels, split by a divider.
    func search(menuId: String, query: String) -> [OmarchyMenuRow] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let subtree = nodes.values
            .filter { isDescendant(nodeId: $0.id, of: menuId) }
            .sorted { $0.order < $1.order }
        var current: [OmarchyMenuRow] = []
        var drilldown: [OmarchyMenuRow] = []
        for node in subtree where node.id != menuId {
            guard matchesQuery(node: node, guards: guards, query: query) else { continue }
            let row = OmarchyMenuRow(
                id: node.id,
                node: node,
                label: node.label,
                icon: node.icon,
                appPath: nil,
                detail: node.description,
                isSubmenu: node.kind != .action,
                isDisabled: guards.isDisabled(node),
                isChecked: guards.isChecked(node),
                score: searchScore(node: node, isAppRow: false, query: query),
            )
            if node.parent == menuId {
                current.append(row)
            } else {
                drilldown.append(row)
            }
        }
        for row in providerRows(menuId: menuId) {
            guard matchesProviderRow(row: row, query: query) else { continue }
            current.append(OmarchyMenuRow(
                id: row.id,
                node: nil,
                label: row.label,
                icon: row.icon,
                appPath: row.appPath,
                detail: row.detail,
                isSubmenu: false,
                isDisabled: false,
                isChecked: false,
                score: appSearchScore(label: row.label + " " + (row.detail ?? ""), query: query),
                handler: row.handler,
            ))
        }
        let sortedCurrent = current.sorted { $0.score < $1.score }
        let sortedDrilldown = drilldown.sorted { $0.score < $1.score }
        guard !sortedDrilldown.isEmpty else { return sortedCurrent }
        guard !sortedCurrent.isEmpty else { return sortedDrilldown }
        return sortedCurrent + [OmarchyMenuRow(
            id: "divider",
            node: nil,
            label: "",
            icon: nil,
            appPath: nil,
            isSubmenu: false,
            isDisabled: false,
            isChecked: false,
            isDivider: true,
        )] + sortedDrilldown
    }

    func isDescendant(nodeId: String, of menuId: String) -> Bool {
        menuId == "root" || nodeId.hasPrefix("\(menuId).")
    }

    private func matchesProviderRow(row: OmarchyMenuRow, query: String) -> Bool {
        let haystack = normalizeForSearch(row.label + " " + (row.detail ?? ""))
        return query.split(whereSeparator: \.isWhitespace).allSatisfy { term in
            haystack.contains(String(term).lowercased())
        }
    }

    private func appSearchScore(label: String, query: String) -> Int {
        let normalizedQuery = normalizeForSearch(query.trimmingCharacters(in: .whitespaces))
        let normalizedLabel = normalizeForSearch(label)
        let base: Int = if normalizedLabel == normalizedQuery {
            0
        } else if normalizedLabel.hasPrefix(normalizedQuery) {
            10
        } else if normalizedLabel.contains(normalizedQuery) {
            30
        } else {
            40
        }
        return (base - 5) * 1000
    }
}

// MARK: Helpers

private func defaultMenuNodes() -> [OmarchyMenuNode] {
    guard let url = Bundle.module.url(forResource: "omarchy-menu", withExtension: "jsonc", subdirectory: "Resources"),
          let raw = try? String(contentsOf: url, encoding: .utf8),
          let nodes = parseMenuJsonc(raw)
    else {
        check(false, "Shipped omarchy-menu.jsonc is missing or invalid")
        return []
    }
    return nodes
}

/// Runs the batched guard script with /bin/bash off the main actor. Returns nil
/// on failure so the caller keeps the previous complete result.
private func runGuardScript(_ script: String) async -> String? {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(filePath: "/bin/bash")
            process.arguments = ["-c", script]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do { try process.run() } catch { continuation.resume(returning: nil); return }
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { continuation.resume(returning: nil); return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            continuation.resume(returning: String(data: data, encoding: .utf8))
        }
    }
}

let menuParseErrorNoticeId = "menu-parse-error"

@MainActor
func postMenuParseErrorNotice(error: String, url: URL) {
    NoticeCenter.shared.post(TrayNotice(
        id: menuParseErrorNoticeId,
        severity: .error,
        title: "Menu config error",
        message: error,
        actions: [
            TrayNoticeAction(id: "open-menu-config", label: "Open menu.jsonc", tooltip: "Edit your menu extension") {
                NSWorkspace.shared.open(url)
            },
        ],
    ))
}
