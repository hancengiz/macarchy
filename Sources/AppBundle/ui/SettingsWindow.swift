import AppKit
import Common
import SwiftUI

@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?
    private let model = SettingsModel()

    func show(section: SettingsSection = .general) {
        // Capture before activation so Settings cannot become the save-width target.
        if window == nil || NSApp.keyWindow !== window { model.captureTarget() }
        model.values = config
        model.section = section
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: 570), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Macarchy Settings"
            window.identifier = NSUserInterfaceItemIdentifier("macarchy.settings")
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 520, height: 430)
            window.contentMaxSize = NSSize(width: 800, height: 800)
            let hosting = NSHostingView(rootView: SettingsView(model: model))
            hosting.sizingOptions = []
            window.contentView = hosting
            window.center()
            window.setFrameAutosaveName("MacarchySettings")
            self.window = window
        }
        NoticeCenter.shared.dismiss()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

enum SettingsSection: Hashable {
    case general, appWidths, shortcuts
}

@MainActor
private final class SettingsModel: ObservableObject {
    @Published var values = config
    @Published var section = SettingsSection.general
    @Published var busy = false
    @Published var status: String?
    @Published var isError = false
    @Published var target: AppWidthSnapshot?
    @Published var targetIssue: String?

    func captureTarget() {
        do {
            guard let window = focus.windowOrNil else { throw SettingsError("Focus an app window, then open Settings to save its current width.") }
            target = try AppWidthSnapshot(window: window)
            targetIssue = nil
        } catch {
            target = nil
            targetIssue = error.localizedDescription
        }
    }

    func perform(_ action: @escaping @MainActor () async throws -> String) {
        guard !busy else { return }
        busy = true
        status = nil
        isError = false
        Task { @MainActor in
            defer { busy = false; values = config }
            do {
                try await runLightSession(.menuBarButton, .forceRun) {
                    self.status = try await action()
                }
            } catch {
                status = error.localizedDescription
                isError = true
            }
        }
    }

    func set(_ path: [String], _ value: String?) {
        perform {
            let url = try ConfigPersistence.set(path, value: value)
            let warnings = try await ConfigPersistence.reload(url)
            return warnings.isEmpty ? "Saved." : warnings
        }
    }

    func openConfiguration() {
        perform { try await ConfigPersistence.open(); return "Opened configuration in your editor." }
    }

    func reload() {
        perform {
            let warnings = try await ConfigPersistence.reload(ConfigPersistence.activeURL())
            return warnings.isEmpty ? "Configuration reloaded." : warnings
        }
    }

    func bool(_ key: String, _ keyPath: KeyPath<Config, Bool>) -> Binding<Bool> {
        Binding(get: { self.values[keyPath: keyPath] }, set: { self.set([key], String($0)) })
    }

    func string(_ key: String, get: @escaping (Config) -> String) -> Binding<String> {
        Binding(get: { get(self.values) }, set: { self.set([key], ConfigTextEditor.quoteString($0)) })
    }
}

private struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject private var conflicts = ShortcutConflicts.shared
    @State private var selectedBundle = ""
    @State private var bundleId = ""
    @State private var appPercentage = 49

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $model.section) {
                general.tabItem { Text("General") }.tag(SettingsSection.general)
                appWidths.tabItem { Text("App Widths") }.tag(SettingsSection.appWidths)
                shortcuts.tabItem { Text("Shortcuts") }.tag(SettingsSection.shortcuts)
            }
            .padding(12)
            .disabled(model.busy)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let status = model.status {
                    ScrollView {
                        Text(status).foregroundStyle(model.isError ? Color.red : Color.secondary)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 64)
                }
                HStack {
                    Button("Open Configuration…") { model.openConfiguration() }
                    Button("Reload") { model.reload() }
                    Spacer()
                    if model.busy { ProgressView().controlSize(.small) }
                }.disabled(model.busy)
                Text(configUrl.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(configUrl.path)
            }.padding(12)
        }
        .font(.body)
    }

    private var general: some View {
        Form {
            Section("Layout") {
                Picker("Default layout", selection: model.string("default-root-container-layout", get: { $0.defaultRootContainerLayout.rawValue })) {
                    Text("Scrolling").tag("scrolling")
                    Text("Tiles").tag("tiles")
                    Text("Accordion").tag("accordion")
                }
                Picker("Default orientation", selection: model.string("default-root-container-orientation", get: { $0.defaultRootContainerOrientation.rawValue })) {
                    Text("Automatic").tag("auto")
                    Text("Horizontal").tag("horizontal")
                    Text("Vertical").tag("vertical")
                }
                IntegerSettingRow("Default column width", value: model.values.scrollingColumnWidth, range: 10...100, suffix: "%") { model.set(["scrolling-column-width"], String($0)) }
                Text("Defaults apply to new containers. Column width applies continuously to scrolling windows without a manual size.").font(.caption).foregroundStyle(.secondary)
                gap("Horizontal gap", ["gaps", "inner", "horizontal"], model.values.gaps.inner.horizontal)
                gap("Vertical gap", ["gaps", "inner", "vertical"], model.values.gaps.inner.vertical)
                gap("Left outer gap", ["gaps", "outer", "left"], model.values.gaps.outer.left)
                gap("Right outer gap", ["gaps", "outer", "right"], model.values.gaps.outer.right)
                gap("Top outer gap", ["gaps", "outer", "top"], model.values.gaps.outer.top)
                gap("Bottom outer gap", ["gaps", "outer", "bottom"], model.values.gaps.outer.bottom)
            }
            Section("Mouse") {
                Picker("Move / resize modifier", selection: model.string("mouse-modifier", get: { $0.mouseModifier.rawValue })) {
                    Text("Off").tag("none")
                    Text("Option").tag("alt")
                    Text("Control").tag("ctrl")
                    Text("Command").tag("cmd")
                }
                Toggle("Adopt native window resizing", isOn: model.bool("adopt-native-window-resize", \.adoptNativeWindowResize))
                Toggle("Focus windows at the screen edge", isOn: model.bool("enable-mouse-edge-focus", \.enableMouseEdgeFocus))
            }
            Section("Floating Windows") {
                Toggle("Keep floating windows above tiled windows", isOn: model.bool("keep-floating-windows-on-top", \.keepFloatingWindowsOnTop))
            }
            Section("Startup & Configuration") {
                Toggle("Start at login", isOn: model.bool("start-at-login", \.startAtLogin))
                Toggle("Reload configuration when the file changes", isOn: model.bool("auto-reload-config", \.autoReloadConfig))
                Text("Advanced options, callbacks, per-display gaps and shortcut bindings are available in Open Configuration.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    @ViewBuilder private func gap(_ label: String, _ path: [String], _ value: DynamicConfigValue<Int>) -> some View {
        switch value {
            case .constant(let number):
                IntegerSettingRow(label, value: number, range: 0...1000, suffix: "pt") { model.set(path, String($0)) }
            case .perMonitor:
                HStack {
                    Text(label)
                    Spacer()
                    Button("Per-display rules…") { model.openConfiguration() }
                }
        }
    }

    private var appWidths: some View {
        Form {
            Section("Save Current Width") {
                if let target = model.target {
                    LabeledContent(target.appName, value: "\(target.percentage)%")
                    Text(target.bundleId).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Button("Save Width for \(target.appName)") {
                        model.perform {
                            let warnings = try await target.save()
                            return warnings.isEmpty ? "Saved \(target.appName) at \(target.percentage)%." : warnings
                        }
                    }
                } else if let issue = model.targetIssue {
                    Text(issue).foregroundStyle(.secondary)
                }
                Text("Uses the window focused before Settings opened: its logical scrolling width, allocated tile width, or floating width relative to the display. Saving clears only this window’s manual scrolling override.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("App Defaults") {
                if model.values.appWindowWidths.isEmpty {
                    Text("No app defaults saved. Apps use the default column width.").foregroundStyle(.secondary)
                } else {
                    Picker("Saved app", selection: $selectedBundle) {
                        Text("Choose an app").tag("")
                        ForEach(model.values.appWindowWidths.keys.sorted(), id: \.self) { id in Text(id).tag(id) }
                    }.onChange(of: selectedBundle) { id in
                        guard let width = model.values.appWindowWidths[id] else { return }
                        bundleId = id
                        appPercentage = width
                    }
                }
                TextField("Bundle ID", text: $bundleId, prompt: Text("com.example.App"))
                Stepper("Preferred width: \(appPercentage)%", value: $appPercentage, in: 1...100)
                HStack {
                    Button(model.values.appWindowWidths[bundleId] == nil ? "Add Default" : "Update Default") {
                        model.set(["app-window-widths", bundleId], String(appPercentage))
                    }.disabled(bundleId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove Default") {
                        model.set(["app-window-widths", bundleId], nil)
                        selectedBundle = ""
                    }.disabled(model.values.appWindowWidths[bundleId] == nil)
                }
                Text("Percentages are relative to each scrolling container. App defaults apply on every layout unless a window was manually resized. Balance sizes returns those windows to their app defaults.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private var shortcuts: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Check for shortcut registration conflicts", isOn: model.bool("warn-about-shortcut-conflicts", \.warnAboutShortcutConflicts))
                HStack {
                    Button(conflicts.isChecking ? "Checking…" : "Recheck") {
                        model.perform { await conflicts.recheck(); return conflicts.checkStatus ?? "Shortcut check complete." }
                    }.disabled(conflicts.isChecking)
                    Button("Keyboard Settings…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension").orDie())
                    }
                }
                if let status = conflicts.checkStatus { Text(status).foregroundStyle(.secondary) }
                if let date = conflicts.lastChecked { Text("Checked \(date.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary) }
                let actual = conflicts.conflicts.filter { !$0.advisory }
                if actual.isEmpty {
                    Text(conflicts.lastChecked == nil ? "Recheck to inspect active-mode registrations." : "No registration conflicts in the active mode.").foregroundStyle(.secondary)
                } else {
                    Text("Registration Conflicts").font(.headline)
                    Text("These shortcuts could not be registered and are inactive.").font(.caption).foregroundStyle(.secondary)
                    ForEach(actual) { conflict in conflictRow(conflict) }
                }
                let suggestions = conflicts.conflicts.filter(\.advisory)
                if !suggestions.isEmpty {
                    Divider()
                    Text("App Shortcut Suggestions").font(.headline)
                    Text("Informational only. Similar shortcuts are not registration conflicts; these bindings remain active.").font(.caption).foregroundStyle(.secondary)
                    ForEach(suggestions) { conflict in conflictRow(conflict) }
                }
                Divider()
                Text("Current Bindings").font(.headline)
                Text(currentShortcutsDescription(model.values)).textSelection(.enabled).font(.system(.body, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func conflictRow(_ conflict: ShortcutConflict) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(conflict.mode): \(conflict.binding)").fontWeight(.medium)
            Text(conflict.reason).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}

private struct IntegerSettingRow: View {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    let suffix: String
    let save: (Int) -> Void
    @State private var draft: String

    init(_ title: String, value: Int, range: ClosedRange<Int>, suffix: String, save: @escaping (Int) -> Void) {
        self.title = title
        self.value = value
        self.range = range
        self.suffix = suffix
        self.save = save
        _draft = State(initialValue: String(value))
    }

    private var number: Int? { Int(draft).flatMap { range.contains($0) ? $0 : nil } }

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, text: $draft).labelsHidden().multilineTextAlignment(.trailing).frame(width: 55)
                .onSubmit { if let number, number != value { save(number) } }
                .onChange(of: value) { draft = String($0) }
                .help("\(range.lowerBound)–\(range.upperBound) \(suffix)")
            Text(suffix).foregroundStyle(.secondary).frame(width: 20, alignment: .leading)
            Button("Apply") { if let number { save(number) } }.disabled(number == nil || number == value)
        }
    }
}

@MainActor
func showSettingsError(_ error: Error) {
    NoticeCenter.shared.post(TrayNotice(id: "settings-error", severity: .error, title: "Macarchy", message: error.localizedDescription))
}
