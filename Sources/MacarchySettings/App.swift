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
    case about = "About"
    var id: String { rawValue }

    var icon: String {
        switch self {
            case .appearance: "paintbrush"
            case .gapsAndLayout: "rectangle.split.3x1"
            case .keybindings: "keyboard"
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
                case .about: AboutPanel(model: model)
            }
        }
        .safeAreaInset(edge: .bottom) { DiffBar(model: model) }
        .navigationTitle("macarchy Settings")
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

// MARK: Keybindings (read-only keycap catalog + conflict rows)

struct KeybindingsPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let analysis = ShortcutConflictAnalysis(
            configText: model.originalText,
            system: .live()
        )
        return SettingsForm {
            if model.originalText.isEmpty {
                Text(model.configLocationProblem ?? "No config loaded.").foregroundStyle(.secondary)
            } else {
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
                Section("Catalog") {
                    ForEach(analysis.catalog(), id: \.mode) { modeCatalog in
                        DisclosureGroup("mode.\(modeCatalog.mode)") {
                            ForEach(modeCatalog.bindings, id: \.chord) { entry in
                                HStack {
                                    KeycapView(chord: entry.chord)
                                    Spacer()
                                    Text(entry.command.trimmingCharacters(in: CharacterSet(charactersIn: "'\"")))
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                    }
                    Text("Binding editing arrives with a later update.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
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
