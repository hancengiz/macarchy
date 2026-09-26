import Common

struct RestartCommand: Command {
    let args: RestartCmdArgs
    let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        do {
            try await restartMacarchy()
            io.out("Session saved; restarting Macarchy without moving windows.")
            return .succ
        } catch {
            io.err("Could not restart Macarchy: \(error.localizedDescription)")
            return .fail
        }
    }
}
