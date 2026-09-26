import AppKit
import Common
import ServiceManagement

@MainActor private(set) var startAtLoginError: String?

@MainActor
func syncStartAtLogin() {
    cleanupPlistFromPrevVersions()
    let service = SMAppService.mainApp
    startAtLoginError = nil
    do {
        if !config.startAtLogin {
            if service.status != .notRegistered { try service.unregister() }
        } else if isDebug {
            startAtLoginError = "Start at login is saved, but is not available in debug builds."
        } else {
            if service.status != .enabled { try service.register() }
            if service.status == .requiresApproval {
                startAtLoginError = "Allow Macarchy in System Settings → General → Login Items to finish enabling start at login."
            }
        }
    } catch {
        startAtLoginError = "Could not update start at login: \(error.localizedDescription)"
    }
}

private func cleanupPlistFromPrevVersions() { // todo Drop after a couple of versions
    let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser.appending(component: "Library/LaunchAgents/")
    Result { try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true) }.getOrDie()
    let url: URL = launchAgentsDir.appending(path: "bobko.aerospace.plist")
    try? FileManager.default.removeItem(at: url)
}
