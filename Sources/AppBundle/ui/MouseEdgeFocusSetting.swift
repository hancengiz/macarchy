import Common
import Foundation

/// Tray setting that flips `enable-mouse-edge-focus` in the live config file
/// and reloads. The file is the single source of truth, so the choice survives
/// restarts and stays consistent with config documentation.
@MainActor
func toggleMouseEdgeFocusSetting() {
    guard let url = findCustomConfigUrl().urlOrNil,
          var text = try? String(contentsOf: url, encoding: .utf8)
    else { return }
    let newValue = !config.enableMouseEdgeFocus
    if let range = text.range(of: #"enable-mouse-edge-focus\s*=\s*(true|false)"#, options: .regularExpression) {
        text.replaceSubrange(range, with: "enable-mouse-edge-focus = \(newValue)")
    } else {
        // Top-level keys must precede any TOML table; prepending is always safe.
        text = "enable-mouse-edge-focus = \(newValue)\n" + text
    }
    do {
        try text.write(to: url, atomically: true, encoding: .utf8)
    } catch {
        return
    }
    guard let token: RunSessionGuard = .isServerEnabled else { return }
    Task.startUnstructured {
        try? await runLightSession(.menuBarButton, token) {
            _ = await reloadConfig_nonCancellable(args: ReloadConfigCmdArgs(rawArgs: []))
        }
    }
}
