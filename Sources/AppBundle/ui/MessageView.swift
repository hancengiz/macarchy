import Common
import SwiftUI

@MainActor
public func getMessageWindow(messageModel: MessageModel) -> some Scene {
    // Using SwiftUI.Window because another class in Macarchy is already called Window
    SwiftUI.Window(messageModel.message?.title ?? appName, id: messageWindowId) {
        MessageView(model: messageModel)
            .onAppear {
                // Set activation policy; otherwise, Macarchy windows won't be able to receive focus and accept keyboard input
                NSApp.setActivationPolicy(.accessory)
                NSApplication.shared.windows.forEach {
                    if $0.identifier?.rawValue == messageWindowId {
                        $0.level = messageModel.message?.type == .config ? .floating : .normal
                        $0.styleMask.remove(.miniaturizable) // Disable minimize button, because we don't unminimize the window on config error
                        // macOS window-state restoration resurrects this window empty on every launch.
                        $0.isRestorable = false
                    }
                }
            }
            .onChange(of: messageModel.message?.type) { type in
                NSApplication.shared.windows.filter { $0.identifier?.rawValue == messageWindowId }.forEach {
                    $0.level = type == .config ? .floating : .normal
                }
            }
        // .windowMinimizeBehavior(WindowInteractionBehavior.disabled) // SwiftUI way of hiding minimize button. Available only since macOS 15
    }
    .windowResizability(.contentSize)
    .defaultSize(width: 580, height: 380)
    //.windowLevel(.floating) //This might be the SwiftUI way of doing window level instead of the onAppear block above, but it's only available from macOS 15.0
}

public let messageWindowId = "\(appName).messageView"

struct MessageView: View {
    @StateObject private var model: MessageModel
    @Environment(\.dismiss) private var dismiss: DismissAction

    init(model: MessageModel) {
        self._model = .init(wrappedValue: model)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.message?.description ?? "").font(.headline)
            ScrollView {
                Text(model.message?.body ?? "")
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                if let type = model.message?.type {
                    switch type {
                        case .config:
                            reloadConfigButton(warningsAsErrors: model.message?.containsWarnings == true)
                            openConfigButton()
                        case .shortcuts:
                            Button("Refresh") {
                                model.message = Message(type: .shortcuts, title: "Current Shortcuts", description: "Current Shortcuts",
                                                        body: currentShortcutsDescription(config), containsWarnings: false)
                            }
                            openConfigButton()
                    }
                }
                let closeButton = Button("Close") { model.message = nil }.keyboardShortcut(.defaultAction)
                closeButton
            }
            .padding(.top, 4)
        }
        .padding(16)
        .textSelection(.enabled)
        .frame(minWidth: 480, idealWidth: 580, maxWidth: 720, minHeight: 280, idealHeight: 380, maxHeight: 640)
        .onChange(of: model.message) { message in
            if message == nil {
                self.dismiss()
            }
        }
        .onDisappear {
            // If user closes the screen with the macOS native close (x) button and then the error is still the same, this window will not appear again
            model.message = nil
        }
        .onAppear {
            // A window restored without a message must never linger as an empty shell.
            if model.message == nil {
                dismiss()
            }
        }
    }
}

public final class MessageModel: ObservableObject {
    @MainActor public static let shared = MessageModel()
    @Published public var message: Message? = nil

    private init() {}
}

public enum MessageType {
    case config
    case shortcuts
}

public struct Message: Hashable, Equatable {
    public let type: MessageType
    public let title: String
    public let description: String
    public let body: String
    public let containsWarnings: Bool

    init(
        type: MessageType = .config,
        title: String = appName,
        description: String = "macarchy Config Diagnostics",
        body: String,
        containsWarnings: Bool,
    ) {
        self.type = type
        self.title = title
        self.description = description
        self.body = body
        self.containsWarnings = containsWarnings
    }
}
