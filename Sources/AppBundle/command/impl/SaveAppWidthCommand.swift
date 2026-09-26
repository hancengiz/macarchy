import Common

struct SaveAppWidthCommand: Command {
    let args: SaveAppWidthCmdArgs
    let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else { return .fail(io.err("save-app-width requires a window target")) }
        do {
            let snapshot = try AppWidthSnapshot(window: window)
            let warnings = try await snapshot.save()
            io.out("Saved \(snapshot.bundleId) at \(snapshot.percentage)% of its scrolling container.")
            if !warnings.isEmpty { io.err(warnings) }
            return .succ
        } catch {
            return .fail(io.err(error.localizedDescription))
        }
    }
}
