import Common
import Foundation
import SwiftUI

@MainActor
func openConfigButton() -> some View {
    Button("Open Configuration…") {
        Task { @MainActor in
            do { try await ConfigPersistence.open() }
            catch { showSettingsError(error) }
        }
    }.keyboardShortcut(",", modifiers: .command)
}

@MainActor
func reloadConfigButton(warningsAsErrors: Bool) -> some View {
    Button("Reload Configuration") {
        Task { @MainActor in
            do {
                try await runLightSession(.menuBarButton, .forceRun) {
                    let url = try ConfigPersistence.activeURL()
                    let args = ReloadConfigCmdArgs(rawArgs: []).copy(\.warningsAsErrors, warningsAsErrors)
                    _ = await reloadConfig_nonCancellable(args: args, forceConfigUrl: url)
                }
            } catch { showSettingsError(error) }
        }
    }.keyboardShortcut("r", modifiers: .command)
}

func getTextEditorToOpenConfig(for url: URL) -> URL {
    NSWorkspace.shared.urlForApplication(toOpen: url)?
        .takeIf { $0.lastPathComponent != "Xcode.app" } // Blacklist Xcode. It is too heavy to open plain text files
        ?? URL(filePath: "/System/Applications/TextEdit.app")
}
