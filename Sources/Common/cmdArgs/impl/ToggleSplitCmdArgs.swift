public struct ToggleSplitCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    fileprivate init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .toggleSplit,
        help: toggle_split_help_generated,
        flags: [
            "--window-id": windowIdSubArgParser(),
        ],
        posArgs: [newMandatoryPosArgParser(\.arg, parseToggleSplitArg, placeholder: SplitCmdArgs.SplitArg.unionLiteral)],
    )

    public var arg: Lateinit<SplitCmdArgs.SplitArg> = .uninitialized
}

func parseToggleSplitCmdArgs(_ args: StrArrSlice) -> ParsedCmd<ToggleSplitCmdArgs> {
    parseSpecificCmdArgs(ToggleSplitCmdArgs(rawArgs: args), args)
}

private func parseToggleSplitArg(i: PosArgParserInput) -> ParsedCliArgs<SplitCmdArgs.SplitArg> {
    .init(parseEnum(i.arg, SplitCmdArgs.SplitArg.self), advanceBy: 1)
}
