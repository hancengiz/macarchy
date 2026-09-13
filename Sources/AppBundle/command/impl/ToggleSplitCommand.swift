import AppKit
import Common

struct ToggleSplitCommand: Command {
    let args: ToggleSplitCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else {
            return .fail(io.err(noWindowIsFocused))
        }
        guard let parent = window.parent as? TilingContainer else {
            return .fail(io.err("Can't toggle split direction for non-tiling windows"))
        }
        let orientation: Orientation = switch args.arg.val {
            case .vertical: .v
            case .horizontal: .h
            case .opposite: (window.nextSplitOrientation ?? parent.orientation).opposite
        }
        window.nextSplitOrientation = orientation
        return .succ(io.out("The next new window will join the focused window in a \(orientation == .v ? "vertical" : "horizontal") split"))
    }
}
