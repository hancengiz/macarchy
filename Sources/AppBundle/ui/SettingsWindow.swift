import AppKit
import Common
import SwiftUI
import TOMLDecoder

@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let contentView = SettingsRootView()
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 580),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            w.title = "macarchy Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: contentView)
            w.setFrameAutosaveName("macarchy-settings")
            window = w
        }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Data types

struct BindingRow: Equatable, Identifiable {
    var id: String { "\(mode)|\(chord)" }
    let mode: String
    var chord: String
    var commandToml: String

    init(mode: String, chord: String, commandToml: String) {
        self.mode = mode
        self.chord = chord
        self.commandToml = commandToml
    }
}

// MARK: - Model

@MainActor
final class SettingsModel: ObservableObject {
    @Published var section: Section = .general
    @Published var originalText: String = ""
    @Published var edits: [String: String] = [:]
    @Published var modeEdits: [String: [BindingRow]] = [:]
    @Published var saveError: String?
    @Published var busy = false

    let profileStore = ProfileStore()

    enum Section: String, CaseIterable, Identifiable {
        case general = "General"
        case gapsAndLayout = "Gaps & Layout"
        case keybindings = "Keybindings"
        case overlays = "Overlays"
        case about = "About"
        var id: String { rawValue }

        var icon: String {
            switch self {
                case .general: "gearshape"
                case .gapsAndLayout: "rectangle.split.3x1"
                case .keybindings: "keyboard"
                case .overlays: "square.on.square.dashed"
                case .about: "info.circle"
            }
        }

        var tint: Color {
            switch self {
                case .general: .blue
                case .gapsAndLayout: .indigo
                case .keybindings: .orange
                case .overlays: .purple
                case .about: .gray
            }
        }
    }

    var configUrl: URL? { try? ConfigPersistence.activeURL() }

    func load() {
        if let url = configUrl {
            originalText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        edits = [:]
        modeEdits = [:]
        saveError = nil
    }

    var draftText: String {
        var doc = TomlDocument(text: ConfigDraft.apply(edits, to: originalText))
        for (mode, rows) in modeEdits {
            _ = doc.replaceModeBindings(
                mode: mode,
                rows: rows.sorted { $0.chord < $1.chord }.map { ($0.chord, $0.commandToml) }
            )
        }
        return doc.text
    }

    var changes: [ConfigChange] {
        var result = ConfigDraft.diff(edits: edits, original: TomlDocument(text: originalText))
        let doc = TomlDocument(text: originalText)
        for (mode, rows) in modeEdits.sorted(by: { $0.key < $1.key }) {
            let old = doc.bindings(mode: mode)
            let new = rows.sorted { $0.chord < $1.chord }
            if old.map({ "\($0.key)=\($0.valueToml)" }) == new.map({ "\($0.chord)=\($0.commandToml)" }) { continue }
            result.append(ConfigChange(
                keyPath: "mode.\(mode).binding",
                oldValueToml: "\(old.count) bindings",
                newValueToml: "\(new.count) bindings"
            ))
        }
        return result
    }

    var hasUnsavedChanges: Bool { !changes.isEmpty }

    func edit(_ path: String, toToml value: String) { edits[path] = value }
    func discard() { edits = [:]; modeEdits = [:]; saveError = nil }

    func setModeRows(_ rows: [BindingRow], for mode: String) {
        modeEdits[mode] = rows
    }

    func revertMode(mode: String) { modeEdits.removeValue(forKey: mode) }

    func bindingRows(mode: String) -> [BindingRow] {
        if let staged = modeEdits[mode] { return staged }
        return TomlDocument(text: originalText).bindings(mode: mode).map {
            BindingRow(mode: mode, chord: $0.key, commandToml: $0.valueToml)
        }
    }

    var availableModes: [String] {
        TomlDocument(text: originalText).text
            .split(separator: "\n")
            .compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("[mode."), trimmed.hasSuffix(".binding]") else { return nil }
                return String(trimmed.dropFirst("[mode.".count).dropLast(".binding]".count))
            }
            .sorted()
    }

    func save() async {
        saveError = nil
        guard let url = configUrl, hasUnsavedChanges else { return }
        let newText = draftText
        guard (try? TOMLTable(source: newText)) != nil else {
            saveError = "The edited config is not valid TOML."
            return
        }
        busy = true
        defer { busy = false }
        // Write + in-process reload (no socket round-trip).
        do {
            try newText.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            saveError = "Can't write config: \(error.localizedDescription)"
            return
        }
        let result = await reloadConfig_nonCancellable(args: ReloadConfigCmdArgs(rawArgs: []))
        if result.isOk {
            originalText = newText
            edits = [:]
            modeEdits = [:]
        } else {
            // Roll back the file; the server kept last-good config.
            try? originalText.write(to: url, atomically: true, encoding: .utf8)
            _ = await reloadConfig_nonCancellable(args: ReloadConfigCmdArgs(rawArgs: []))
            saveError = result.stdout.isEmpty ? "The server rejected the config." : result.stdout
        }
    }

    // MARK: Profile operations

    func saveProfile(name: String) throws {
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

    func loadProfile(name: String) throws {
        guard let toml = try profileStore.load(name) else { return }
        let profileDoc = TomlDocument(text: toml)
        for mode in availableModes {
            let rows = profileDoc.bindings(mode: mode)
            setModeRows(
                rows.map { BindingRow(mode: mode, chord: $0.key, commandToml: $0.valueToml) },
                for: mode
            )
        }
    }

    // MARK: Typed accessors

    func boolValue(path: String) -> Bool? { rawValue(path: path).flatMap(TomlValue.parseBool) }
    func intValue(path: String) -> Int? { rawValue(path: path).flatMap(TomlValue.parseInt) }
    func stringValue(path: String) -> String? { rawValue(path: path).flatMap(TomlValue.parseString) }

    func rawValue(path: String) -> String? {
        if let edited = edits[path] { return edited }
        return TomlDocument(text: originalText).getValue(path: path.split(separator: ".").map(String.init))
    }

    func binding(keyPath: String, default defaultValue: Bool) -> Binding<Bool> {
        Binding(
            get: { self.boolValue(path: keyPath) ?? defaultValue },
            set: { self.edit(keyPath, toToml: TomlValue.format(bool: $0)) }
        )
    }

    func intBinding(keyPath: String, default defaultValue: Int) -> Binding<Int> {
        Binding(
            get: { self.intValue(path: keyPath) ?? defaultValue },
            set: { self.edit(keyPath, toToml: TomlValue.format(int: $0)) }
        )
    }

    func stringBinding(keyPath: String, default defaultValue: String) -> Binding<String> {
        Binding(
            get: { self.stringValue(path: keyPath) ?? defaultValue },
            set: { self.edit(keyPath, toToml: TomlValue.format(string: $0)) }
        )
    }
}

// MARK: - Root view (sidebar + detail + diff bar)

private struct SettingsRootView: View {
    @StateObject private var model = SettingsModel()

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .safeAreaInset(edge: .bottom) { DiffBar(model: model) }
        .frame(minWidth: 820, minHeight: 560)
        .task { model.load() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 30, height: 30)
                    Image(systemName: "rectangle.split.3x1")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text("macarchy")
                    .font(.system(size: 15, weight: .bold))
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)

            ForEach(SettingsModel.Section.allCases) { section in
                Button { model.section = section } label: {
                    SidebarRow(section: section, isSelected: model.section == section)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.rawValue)
                .accessibilityAddTraits(model.section == section ? .isSelected : [])
            }
            Spacer()
        }
        .frame(width: 215)
    }

    private var detail: some View {
        ScrollView {
            Group {
                switch model.section {
                    case .general: GeneralPanel(model: model)
                    case .gapsAndLayout: GapsLayoutPanel(model: model)



                    case .keybindings: KeybindingsPanel(model: model)
                    case .overlays: OverlaysPanel(model: model)
                    case .about: AboutPanel(model: model)
                }
            }
            .padding(24)
            .frame(maxWidth: 660, alignment: .leading)
        }
    }
}

// MARK: - Sidebar row

private struct SidebarRow: View {
    let section: SettingsModel.Section
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.9) : section.tint.opacity(0.16))
                    .frame(width: 26, height: 26)
                Image(systemName: section.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(section.tint)
            }
            Text(section.rawValue)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? section.tint.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Premium card

struct PremiumCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1))
    }
}

struct SettingsCard<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(.secondary.opacity(0.8))
                .kerning(0.8)
                .padding(.bottom, 7)
            PremiumCard {
                VStack(alignment: .leading, spacing: 12) { content }
            }
        }
    }
}

// MARK: - Diff bar

private struct DiffBar: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        if model.hasUnsavedChanges || model.saveError != nil {
            VStack(spacing: 10) {
                if let error = model.saveError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .bold))
                        Text(error).font(.system(size: 11.5)).lineLimit(3)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.red)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.red.opacity(0.25), lineWidth: 1))
                    )
                }
                HStack(spacing: 14) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(model.changes) { change in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(change.keyPath).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                                    Text("\(change.oldValueToml ?? "—") → \(change.newValueToml)")
                                        .font(.system(size: 11, design: .monospaced)).lineLimit(1)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.09)))
                            }
                        }
                    }
                    Button("Discard") { model.discard() }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel("Discard changes")
                    Button { Task { await model.save() } } label: {
                        Text(model.busy ? "Saving…" : "Save")
                            .font(.system(size: 12.5, weight: .bold))
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .background(Capsule().fill(Color(nsColor: .controlAccentColor)))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Save changes")
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: Color.black.opacity(0.15), radius: 14, y: 4)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 1))
            )
            .padding(.horizontal, 16).padding(.bottom, 6)
        }
    }
}

// MARK: - Panels

private struct GeneralPanel: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        SettingsCards {
            SettingsCard(label: "BEHAVIOR") {
                Toggle("Start at login", isOn: model.binding(keyPath: "start-at-login", default: true))
                Toggle("Auto-reload config on change", isOn: model.binding(keyPath: "auto-reload-config", default: true))
                Toggle("Warn about shortcut conflicts", isOn: model.binding(keyPath: "warn-about-shortcut-conflicts", default: true))
                Toggle("Show system mode overlay", isOn: model.binding(keyPath: "show-system-mode-overlay", default: true))
                Toggle("Keep floating windows on top", isOn: model.binding(keyPath: "keep-floating-windows-on-top", default: true))
                Toggle("Adopt native window resize", isOn: model.binding(keyPath: "adopt-native-window-resize", default: true))
                Toggle("Mouse edge focus", isOn: model.binding(keyPath: "enable-mouse-edge-focus", default: true))
            }
        }
    }
}

private struct GapsLayoutPanel: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        SettingsCards {
            SettingsCard(label: "TILING") {
                gapSlider("Inner horizontal", "gaps.inner.horizontal")
                gapSlider("Inner vertical", "gaps.inner.vertical")
                gapSlider("Outer left", "gaps.outer.left")
                gapSlider("Outer right", "gaps.outer.right")
                gapSlider("Outer top", "gaps.outer.top")
                gapSlider("Outer bottom", "gaps.outer.bottom")
                Picker("Root layout", selection: model.stringBinding(keyPath: "default-root-container-layout", default: "scrolling")) {
                    Text("Scrolling").tag("scrolling")
                    Text("Tiles").tag("tiles")
                    Text("Accordion").tag("accordion")
                }
                Picker("Root orientation", selection: model.stringBinding(keyPath: "default-root-container-orientation", default: "horizontal")) {
                    Text("Horizontal").tag("horizontal")
                    Text("Vertical").tag("vertical")
                }
                Stepper("Scrolling column width: \(model.intValue(path: "scrolling-column-width") ?? 49)",
                        value: model.intBinding(keyPath: "scrolling-column-width", default: 49), in: 10...200)
                Stepper("Accordion padding: \(model.intValue(path: "accordion-padding") ?? 20)",
                        value: model.intBinding(keyPath: "accordion-padding", default: 20), in: 0...200)
            }
        }
    }

    private func gapSlider(_ label: String, _ path: String) -> some View {
        HStack {
            Slider(value: Binding(
                get: { Double(model.intValue(path: path) ?? 10) },
                set: { model.edit(path, toToml: TomlValue.format(int: Int($0.rounded()))) }
            ), in: 0...60, step: 1)
            Text("\(model.intValue(path: path) ?? 10)")
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 28, alignment: .trailing)
        }
        .labeledStyle(label)
    }
}

private struct KeybindingsPanel: View {
    @ObservedObject var model: SettingsModel
    @State private var newProfileName = ""
    @State private var isSavingProfile = false
    @State private var profileMessage: String?

    var body: some View {
        let analysis = ShortcutConflictAnalysis(configText: model.draftText, system: .live())
        let profiles = model.profileStore.list()
        SettingsCards {
            SettingsCard(label: "PROFILES") {
                if profiles.isEmpty {
                    Text("No saved profiles yet. Edit bindings below, then save them as a profile.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(profiles, id: \.self) { name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button("Load") { try? model.loadProfile(name: name); profileMessage = "Loaded '\(name)' into the draft — Save to apply." }
                        Button("Delete", role: .destructive) { try? model.profileStore.delete(name); profileMessage = nil }
                    }
                }
                if isSavingProfile {
                    HStack {
                        TextField("Profile name", text: $newProfileName).onSubmit(saveProfile)
                        Button("Save", action: saveProfile)
                    }
                } else {
                    Button("Save current bindings as profile…") { isSavingProfile = true }
                }
                if let profileMessage { Text(profileMessage).font(.caption).foregroundStyle(.secondary) }
            }
            SettingsCard(label: "BINDINGS") {
                ForEach(model.availableModes, id: \.self) { mode in
                    ModeEditor(mode: mode, model: model)
                }
            }
            SettingsCard(label: "CONFLICTS") {
                let rows = analysis.conflictRows()
                if rows.isEmpty {
                    Text("No conflicts detected.").foregroundStyle(.secondary)
                }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            KeycapView(chord: row.chord, prominent: true)
                            Spacer()
                            Text("mode.\(row.mode)").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(row.explanation).font(.caption).foregroundStyle(color(row.severity))
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func saveProfile() {
        let name = newProfileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        do {
            try model.saveProfile(name: name)
            newProfileName = ""
            isSavingProfile = false
            profileMessage = "Saved profile '\(name)'."
        } catch { profileMessage = "Can't save profile: \(error)" }
    }

    private func color(_ severity: ConflictSeverity) -> Color {
        switch severity {
            case .dead, .reserved: .red
            case .dormant: .orange
            case .textEditing: .secondary
        }
    }
}

private struct ModeEditor: View {
    let mode: String
    @ObservedObject var model: SettingsModel
    @State private var newChord = ""
    @State private var newCommand = ""

    var body: some View {
        DisclosureGroup("mode.\(mode)\(model.modeEdits[mode] != nil ? " •" : "")") {
            ForEach(model.bindingRows(mode: mode)) { row in
                BindingRowView(mode: mode, row: row, model: model)
            }
            .onDelete { offsets in
                var updated = model.bindingRows(mode: mode)
                updated.remove(atOffsets: offsets)
                model.setModeRows(updated, for: mode)
            }
            HStack {
                TextField("chord, e.g. alt-h", text: $newChord).frame(width: 150)
                TextField("command, e.g. focus left", text: $newCommand)
                Button("Add") {
                    let chord = newChord.trimmingCharacters(in: .whitespaces)
                    let command = newCommand.trimmingCharacters(in: .whitespaces)
                    guard !chord.isEmpty, !command.isEmpty else { return }
                    var updated = model.bindingRows(mode: mode)
                    updated.removeAll { $0.chord == chord }
                    updated.append(BindingRow(mode: mode, chord: chord, commandToml: TomlValue.format(string: command)))
                    model.setModeRows(updated, for: mode)
                    newChord = ""; newCommand = ""
                }
            }
            if model.modeEdits[mode] != nil {
                Button("Revert mode.\(mode) to file") { model.revertMode(mode: mode) }
            }
        }
    }
}

private struct BindingRowView: View {
    let mode: String
    let row: BindingRow
    let model: SettingsModel

    var body: some View {
        HStack {
            KeycapView(chord: row.chord).frame(width: 150, alignment: .leading)
            TextField("command", text: Binding(
                get: { row.commandToml.trimmingCharacters(in: CharacterSet(charactersIn: "'\"")) },
                set: { updated in
                    var rows = model.bindingRows(mode: mode)
                    if let i = rows.firstIndex(where: { $0.chord == row.chord }) {
                        rows[i].commandToml = TomlValue.format(string: updated)
                        model.setModeRows(rows, for: mode)
                    }
                }
            ))
            .font(.system(.caption, design: .monospaced))
        }
    }
}

private struct OverlaysPanel: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        SettingsCards {
            SettingsCard(label: "FOCUS RING") {
                Toggle("Focus ring around focused window", isOn: model.binding(keyPath: "borders.enabled", default: false))
                Stepper("Ring width: \(model.intValue(path: "borders.width") ?? 4)",
                        value: model.intBinding(keyPath: "borders.width", default: 4), in: 1...16)
                Picker("Ring color", selection: model.stringBinding(keyPath: "borders.color", default: "auto")) {
                    Text("Accent (auto)").tag("auto")
                    Text("Palette").tag("palette")
                    Text("Blue").tag("blue")
                    Text("Red").tag("red")
                    Text("Green").tag("green")
                    Text("Yellow").tag("yellow")
                    Text("Cyan").tag("cyan")
                    Text("Magenta").tag("magenta")
                    Text("White").tag("white")
                }
            }
            SettingsCard(label: "WORKSPACE BAR") {
                Toggle("Workspace bar", isOn: barBinding)
                if model.boolValue(path: "bar.enabled") == true {
                    Stepper("Bar height: \(model.intValue(path: "bar.height") ?? 28)",
                            value: model.intBinding(keyPath: "bar.height", default: 28), in: 20...48)
                    Toggle("Show only where the menu bar auto-hides",
                           isOn: model.binding(keyPath: "bar.only-with-hidden-menu-bar", default: false))
                    Toggle("Step aside while the menu bar is revealed",
                           isOn: model.binding(keyPath: "bar.hide-with-menu-bar", default: true))
                }
            }
            SettingsCard(label: "PALETTE") {
                Picker("Palette", selection: model.stringBinding(keyPath: "palette.name", default: "default")) {
                    Text("Default (accent)").tag("default")
                    Text("Nord").tag("nord")
                    Text("Dracula").tag("dracula")
                    Text("Solarized Dark").tag("solarized-dark")
                    Text("Gruvbox Dark").tag("gruvbox-dark")
                }
            }
        }
    }

    private var barBinding: Binding<Bool> {
        Binding(
            get: { model.boolValue(path: "bar.enabled") ?? false },
            set: { enabled in
                model.edit("bar.enabled", toToml: TomlValue.format(bool: enabled))
                if enabled {
                    let h = model.intValue(path: "bar.height") ?? 28
                    let carve = h + 6
                    if (model.intValue(path: "gaps.outer.top") ?? 0) < carve {
                        model.edit("gaps.outer.top", toToml: TomlValue.format(int: carve))
                    }
                }
            }
        )
    }
}

private struct AboutPanel: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        SettingsCards {
            SettingsCard(label: "SYSTEM") {
                KeyValueRow(key: "Version", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?") (\(gitShortHash))")
                KeyValueRow(key: "Config file", value: model.configUrl?.path ?? "—")
                KeyValueRow(key: "Profiles", value: "\(model.profileStore.list().count) saved")
            }
        }
    }
}

// MARK: - Shared

struct SettingsCards<Content: View>: View {
    @ViewBuilder var sections: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) { sections }
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String
    var body: some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(.caption, design: .monospaced)).lineLimit(1).truncationMode(.middle)
        }
    }
}

extension View {
    func labeledStyle(_ label: String) -> some View {
        HStack { Text(label); Spacer() ; self }
    }
}


@MainActor
func showSettingsError(_ error: Error) {
    NoticeCenter.shared.post(TrayNotice(id: "settings-error", severity: .error, title: "Macarchy", message: error.localizedDescription))
}
