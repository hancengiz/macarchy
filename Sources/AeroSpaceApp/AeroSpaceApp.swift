import AppBundle
import SwiftUI

// This file is shared between SPM and xcode project

@main
struct AeroSpaceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var messageModel = MessageModel.shared
    @Environment(\.openWindow) var openWindow: OpenWindowAction

    init() {
        initAppBundle()
    }

    var body: some Scene {
        // The tray presence, its menu, and the notice surface are provided by
        // TrayStatusItem (NSStatusItem); see ui/TrayStatusItem.swift and ui/TrayNotice.swift
        getMessageWindow(messageModel: messageModel)
            .onChange(of: messageModel.message) { message in
                if message != nil {
                    openWindow(id: messageWindowId)
                }
            }
    }
}

/// Without MenuBarExtra, the app's only scene is a SwiftUI.Window; SwiftUI would
/// otherwise terminate the app when that window closes. The status item keeps the
/// app alive conceptually, but AppKit still needs this answer.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ application: NSApplication) -> Bool {
        false
    }
}
