public struct RestartCmdArgs: CmdArgs {
    public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .restart,
        help: restart_help_generated,
        flags: [:],
        posArgs: [],
    )
}
