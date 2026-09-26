import AppKit
import Common
import Darwin

/// The socket path must finish its response before handing off to a fresh process.
enum RestartReplyContext {
    @TaskLocal static var requestID: UUID? = nil
}

@MainActor private var restartPrepared = false
@MainActor private var preparingRestart = false
@MainActor private var restartRequestID: UUID?
@MainActor var isMacarchyRestartPrepared: Bool { restartPrepared }

@MainActor
func restartMacarchy() async throws {
    guard !preparingRestart, !restartPrepared else { throw RestartError.alreadyRequested }
    preparingRestart = true
    defer { preparingRestart = false }
    guard let executable = Bundle.main.executableURL,
          FileManager.default.isExecutableFile(atPath: executable.path) else { throw RestartError.missingExecutable }
    try await SessionState.shared.saveBeforeRestart()
    restartPrepared = true
    restartRequestID = RestartReplyContext.requestID
    if restartRequestID == nil { try await finishPreparedMacarchyRestart() }
}

@MainActor
func cancelPreparedMacarchyRestart(for requestID: UUID) {
    guard restartRequestID == requestID else { return }
    restartPrepared = false
}

@MainActor
func finishPreparedMacarchyRestart(for requestID: UUID? = nil) async throws {
    guard restartPrepared, restartRequestID == requestID else { return }
    preparingRestart = true
    defer { preparingRestart = false }
    restartPrepared = false
    guard let executable = Bundle.main.executableURL else { throw RestartError.missingExecutable }
    // In-place exec leaves NSStatusItem detached from the menu bar on macOS.
    // A child waits for EOF before launching: the parent keeps the write end
    // alive until _exit, so the two window managers never run concurrently.
    let handoff = Pipe()
    guard fcntl(handoff.fileHandleForWriting.fileDescriptor, F_SETFD, FD_CLOEXEC) == 0 else {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    let launcher = Process()
    launcher.executableURL = URL(filePath: "/bin/sh")
    launcher.arguments = [
        "-c", "IFS= read -r _; exec \"$@\"", "macarchy-relaunch", executable.path,
    ] + CommandLine.arguments.dropFirst()
    launcher.standardInput = handoff
    // Drain only after the command response has reached the client.
    await stopUnixSocketServer()
    do {
        try launcher.run()
    } catch {
        startUnixSocketServer()
        throw error
    }
    // Bypass normal Quit/unhide hooks. The snapshot is already durable, and
    // process exit closes the pipe and releases AX/hotkey/menu-bar registrations.
    withExtendedLifetime(handoff) { _exit(EXIT_SUCCESS) }
}

private enum RestartError: LocalizedError {
    case alreadyRequested
    case missingExecutable

    var errorDescription: String? {
        switch self {
            case .alreadyRequested: "A Macarchy restart is already in progress."
            case .missingExecutable: "The Macarchy executable is missing or not executable. Reinstall the app before restarting."
        }
    }
}
