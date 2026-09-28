import MacarchySettingsCore
import SwiftUI

@main
struct MacarchySettingsApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("macarchy Settings") {
            MainSplitView(model: model)
                .frame(minWidth: 720, minHeight: 460)
                .task { await model.load() }
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance = "Appearance"
    case gapsAndLayout = "Gaps & Layout"
    case keybindings = "Keybindings"
    case overlays = "Overlays"
    case permissions = "Permissions"
    case about = "About"
    var id: String { rawValue }

    var icon: String {
        switch self {
            case .appearance: "paintbrush"
            case .gapsAndLayout: "rectangle.split.3x1"
            case .keybindings: "keyboard"
            case .overlays: "square.on.square.dashed"
            case .permissions: "hand.raised"
            case .about: "info.circle"
        }
    }
}

struct MainSplitView: View {
    @ObservedObject var model: AppModel
    @State private var selection: SettingsSection = .appearance
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            switch selection {
                case .appearance: AppearancePanel(model: model)
                case .gapsAndLayout: GapsLayoutPanel(model: model)
                case .keybindings: KeybindingsPanel(model: model)
                case .overlays: OverlaysPanel(model: model)
                case .permissions: PermissionsPanel()
                case .about: AboutPanel(model: model)
            }
        }
        .safeAreaInset(edge: .bottom) { DiffBar(model: model) }
        .navigationTitle("macarchy Settings")
        .task {
            // First run: if the server isn't healthy, land on the walkthrough.
            let permission = PermissionStatusModel()
            await permission.refresh()
            if !permission.state.isGranted {
                selection = .permissions
            }
        }
    }
}

// MARK: Appearance

struct AppearancePanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsForm("Behavior") {
            if let problem = model.configLocationProblem {
                Text(problem).foregroundStyle(.secondary)
            }
            Toggle("Start at login", isOn: model.binding(path: "start-at-login", default: true))
            Toggle("Auto-reload config on change", isOn: model.binding(path: "auto-reload-config", default: true))
            Toggle("Warn about shortcut conflicts", isOn: model.binding(path: "warn-about-shortcut-conflicts", default: true))
            Toggle("Show system mode overlay", isOn: model.binding(path: "show-system-mode-overlay", default: true))
            Toggle("Keep floating windows on top", isOn: model.binding(path: "keep-floating-windows-on-top", default: true))
            Toggle("Adopt native window resize", isOn: model.binding(path: "adopt-native-window-resize", default: true))
            Toggle("Mouse edge focus", isOn: model.binding(path: "enable-mouse-edge-focus", default: true))
        }
    }
}

// MARK: Gaps & Layout

struct GapsLayoutPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsForm("Gaps & Layout") {
            gapSlider("Inner horizontal", "gaps.inner.horizontal")
            gapSlider("Inner vertical", "gaps.inner.vertical")
            gapSlider("Outer left", "gaps.outer.left")
            gapSlider("Outer right", "gaps.outer.right")
            gapSlider("Outer top", "gaps.outer.top")
            gapSlider("Outer bottom", "gaps.outer.bottom")
            Picker("Root layout", selection: model.binding(path: "default-root-container-layout", default: "scrolling")) {
                Text("Scrolling").tag("scrolling")
                Text("Tiles").tag("tiles")
                Text("Accordion").tag("accordion")
            }
            Picker("Root orientation", selection: model.binding(path: "default-root-container-orientation", default: "horizontal")) {
                Text("Horizontal").tag("horizontal")
                Text("Vertical").tag("vertical")
            }
            Stepper(
                "Scrolling column width: \(model.intValue(path: "scrolling-column-width") ?? 49)",
                value: model.intBinding(path: "scrolling-column-width", default: 49), in: 10...200
            )
            Stepper(
                "Accordion padding: \(model.intValue(path: "accordion-padding") ?? 20)",
                value: model.intBinding(path: "accordion-padding", default: 20), in: 0...200
            )
        }
    }

    private func gapSlider(_ label: String, _ path: String) -> some View {
        LabeledContent(label) {
            HStack {
                Slider(value: model.doubleBinding(path: path, default: 10), in: 0...60, step: 1)
                Text("\(model.intValue(path: path) ?? 10)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
            }
        }
    }
}

// MARK: Keybindings (profiles + editable rows + conflict rows)

struct KeybindingsPanel: View {
    @ObservedObject var model: AppModel
    @State private var newProfileName = ""
    @State private var isSavingProfile = false
    @State private var profileMessage: String?

    var body: some View {
        let analysis = ShortcutConflictAnalysis(
            configText: model.draftText,
            system: .live()
        )
        let profiles = model.profileStore.list()
        return SettingsForm {
            if model.originalText.isEmpty {
                Text(model.configLocationProblem ?? "No config loaded.").foregroundStyle(.secondary)
            } else {
                Section("Profiles") {
                    if profiles.isEmpty {
                        Text("No saved profiles yet. Edit bindings below, then save them as a profile.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(profiles, id: \.self) { name in
                        HStack {
                            Text(name)
                            Spacer()
                            Button("Load") {
                                try? model.loadProfile(name: name)
                                profileMessage = "Loaded '\(name)' into the draft — Save to apply."
                            }
                            Button("Delete", role: .destructive) {
                                try? model.profileStore.delete(name)
                                profileMessage = nil
                            }
                        }
                    }
                    if isSavingProfile {
                        HStack {
                            TextField("Profile name", text: $newProfileName)
                                .onSubmit(saveProfile)
                            Button("Save", action: saveProfile)
                        }
                    } else {
                        Button("Save current bindings as profile…") { isSavingProfile = true }
                    }
                    if let profileMessage {
                        Text(profileMessage).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Bindings") {
                    ForEach(model.availableModes, id: \.self) { mode in
                        ModeEditor(mode: mode, model: model)
                    }
                }
                Section("Conflicts") {
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
                            Text(row.explanation)
                                .font(.caption)
                                .foregroundStyle(color(row.severity))
                        }
                        .padding(.vertical, 2)
                    }
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
        } catch {
            profileMessage = "Can't save profile: \(error)"
        }
    }

    private func color(_ severity: ConflictSeverity) -> Color {
        switch severity {
            case .dead, .reserved: .red
            case .dormant: .orange
            case .textEditing: .secondary.opacity(1)
        }
    }
}

private struct ModeEditor: View {
    let mode: String
    @ObservedObject var model: AppModel
    @State private var newChord = ""
    @State private var newCommand = ""

    var body: some View {
        DisclosureGroup("mode.\(mode)\(model.modeEdits[mode] != nil ? " •" : "")") {
            let rows = model.bindingRows(mode: mode)
            ForEach(rows) { row in
                BindingRowEditor(mode: mode, row: row, model: model)
            }
            .onDelete { offsets in
                var updated = model.bindingRows(mode: mode)
                updated.remove(atOffsets: offsets)
                model.setModeRows(updated, for: mode)
            }
            HStack {
                TextField("chord, e.g. alt-h", text: $newChord)
                    .frame(width: 150)
                TextField("command, e.g. focus left", text: $newCommand)
                Button("Add") {
                    let chord = newChord.trimmingCharacters(in: .whitespaces)
                    let command = newCommand.trimmingCharacters(in: .whitespaces)
                    guard !chord.isEmpty, !command.isEmpty else { return }
                    var updated = model.bindingRows(mode: mode)
                    updated.removeAll { $0.chord == chord }
                    updated.append(BindingRow(mode: mode, chord: chord, commandToml: TomlValue.format(string: command)))
                    model.setModeRows(updated, for: mode)
                    newChord = ""
                    newCommand = ""
                }
            }
            if model.modeEdits[mode] != nil {
                HStack {
                    Button("Revert mode.\(mode) to file") { model.revertMode(mode: mode) }
                    Spacer()
                }
            }
        }
    }
}

private struct BindingRowEditor: View {
    let mode: String
    let row: BindingRow
    let model: AppModel

    var body: some View {
        HStack {
            KeycapView(chord: row.chord)
                .frame(width: 150, alignment: .leading)
            TextField("command", text: Binding(
                get: { row.commandToml.trimmingCharacters(in: CharacterSet(charactersIn: "'\"")) },
                set: { updated in
                    var rows = model.bindingRows(mode: mode)
                    if let index = rows.firstIndex(where: { $0.chord == row.chord }) {
                        rows[index].commandToml = TomlValue.format(string: updated)
                        model.setModeRows(rows, for: mode)
                    }
                }
            ))
            .font(.system(.caption, design: .monospaced))
        }
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack {
            Text(key).font(.system(.body, design: .monospaced))
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: About

struct AboutPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsForm("About") {
            KeyValueRow(key: "Server", value: model.serverVersionAndHash ?? "not reachable")
            KeyValueRow(key: "Config file", value: model.configUrl?.path(percentEncoded: false) ?? "—")
            KeyValueRow(key: "App", value: MacarchySettingsCoreInfo.version)
        }
    }
}

// MARK: Permissions (AX walkthrough)

struct PermissionsPanel: View {
    @StateObject private var permission = PermissionStatusModel()

    var body: some View {
        SettingsForm("Accessibility") {
            switch permission.state {
                case .granted(let count):
                    Label("macarchy is managing \(count) windows.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .serverNotRunning:
                    Label(
                        "macarchy server is not running. Open the macarchy app first.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                case .waiting:
                    Label(
                        "Server is running but no windows are managed yet — the Accessibility grant is probably missing.",
                        systemImage: "clock"
                    )
                    .foregroundStyle(.orange)
                case .unknown:
                    Text("Checking…").foregroundStyle(.secondary)
            }
            Text("macarchy needs Accessibility access to manage windows:")
                .padding(.top, 4)
            Text(
                "1. Open System Settings → Privacy & Security → Accessibility\n"
                    + "2. Enable macarchy (or drag the macarchy app in)\n"
                    + "3. If the toggle is already on but nothing works, toggle it off and on again"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            HStack {
                Button("Open Accessibility Settings") {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    )
                }
                Spacer()
                Button("Re-check") { Task { await permission.refresh() } }
            }
        }
        .task { await permission.refresh() }
    }
}

// MARK: Overlays (borders / bar / palette)

struct OverlaysPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsForm("Overlays") {
            Toggle("Focus ring around focused window", isOn: model.binding(path: "borders.enabled", default: false))
            Stepper(
                "Ring width: \(model.intValue(path: "borders.width") ?? 4)",
                value: model.intBinding(path: "borders.width", default: 4), in: 1...16
            )
            Picker("Ring color", selection: model.binding(path: "borders.color", default: "auto")) {
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
            Divider()
            Toggle("Workspace bar", isOn: barBinding)
            if model.boolValue(path: "bar.enabled") == true {
                Stepper(
                    "Bar height: \(model.intValue(path: "bar.height") ?? 28)",
                    value: model.intBinding(path: "bar.height", default: 28), in: 20...48
                )
                Text("Windows are moved out from under the bar by raising the outer top gap to the bar height.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(
                    "Show only where the menu bar auto-hides",
                    isOn: model.binding(path: "bar.only-with-hidden-menu-bar", default: false)
                )
                Toggle(
                    "Step aside while the menu bar is revealed",
                    isOn: model.binding(path: "bar.hide-with-menu-bar", default: true)
                )
            }
            Divider()
            Picker("Palette", selection: model.binding(path: "palette.name", default: "default")) {
                Text("Default (accent)").tag("default")
                Text("Nord").tag("nord")
                Text("Dracula").tag("dracula")
                Text("Solarized Dark").tag("solarized-dark")
                Text("Gruvbox Dark").tag("gruvbox-dark")
            }
        }
    }

    /// Enabling the bar also carves space: outer top gap raised to bar height + margin.
    private var barBinding: Binding<Bool> {
        Binding(
            get: { model.boolValue(path: "bar.enabled") ?? false },
            set: { enabled in
                model.edit("bar.enabled", toToml: TomlValue.format(bool: enabled))
                if enabled {
                    let barHeight = model.intValue(path: "bar.height") ?? 28
                    let carve = barHeight + 6
                    if (model.intValue(path: "gaps.outer.top") ?? 0) < carve {
                        model.edit("gaps.outer.top", toToml: TomlValue.format(int: carve))
                    }
                }
            }
        )
    }
}

// MARK: Diff bar (draft-then-commit)

struct DiffBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.hasUnsavedChanges || model.saveError != nil {
            VStack(alignment: .leading, spacing: 6) {
                if let error = model.saveError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(model.changes) { change in
                            VStack(alignment: .leading) {
                                Text(change.keyPath).font(.caption).foregroundStyle(.secondary)
                                Text("\(change.oldValueToml ?? "—") → \(change.newValueToml)")
                                    .font(.system(.caption, design: .monospaced))
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary))
                        }
                    }
                }
                HStack {
                    Button("Discard") { model.discard() }
                        .accessibilityLabel("Discard changes")
                    Spacer()
                    Button("Save") { Task { await model.save() } }
                        .keyboardShortcut(.defaultAction)
                        .accessibilityLabel("Save changes")
                }
            }
            .padding(10)
            .background(.bar)
        }
    }
}

// MARK: Shared scaffolding

struct SettingsForm<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Form {
            if let title {
                Section(title) { content }
            } else {
                content
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640, alignment: .leading)
    }
}
