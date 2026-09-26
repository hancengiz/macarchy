public struct SaveAppWidthCmdArgs: CmdArgs {
    public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .saveAppWidth,
        help: save_app_width_help_generated,
        flags: ["--window-id": windowIdSubArgParser()],
        posArgs: [],
    )
}
