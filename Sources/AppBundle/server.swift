import AppKit
import Common
import Network

@MainActor private var unixSocketListener: NWListener?
@MainActor private var unixSocketConnections: [ObjectIdentifier: NWConnection] = [:]

@MainActor
func startUnixSocketServer() {
    try? FileManager.default.removeItem(atPath: socketPath)
    let params = NWParameters.tcp
    params.requiredLocalEndpoint = .unix(path: socketPath)
    let listener = Result { try NWListener(using: params) }.getOrDie()
    unixSocketListener = listener
    listener.newConnectionHandler = { connection in
        Task.startUnstructured { @MainActor in
            guard unixSocketListener != nil else {
                connection.cancel()
                return
            }
            let id = ObjectIdentifier(connection)
            unixSocketConnections[id] = connection
            defer {
                unixSocketConnections.removeValue(forKey: id)
                connection.cancel()
            }
            connection.start(queue: .global())
            await newConnection(connection)
        }
    }
    listener.start(queue: .global())
}

@MainActor
func stopUnixSocketServer() async {
    guard let listener = unixSocketListener else { return }
    unixSocketListener = nil
    await withCheckedContinuation { continuation in
        listener.stateUpdateHandler = { state in
            if case .cancelled = state { continuation.resume() }
        }
        listener.cancel()
    }
    for connection in unixSocketConnections.values { connection.cancel() }
    unixSocketConnections.removeAll()
    try? FileManager.default.removeItem(atPath: socketPath)
}

func toggleReleaseServerIfDebug(_ state: EnableCmdArgs.State) async {
    if serverArgs.isReadOnly { return }
    if !isDebug { return }
    let socketFile = "/tmp/\(stableAppId)-\(unixUserName).sock"
    let connection = NWConnection(to: NWEndpoint.unix(path: socketFile), using: .tcp)
    defer { connection.cancel() }
    if await connection.initConnection().error != nil { // Can't connect, Macarchy.app is not running
        return
    }

    let req = ClientRequest(args: ["enable", state.rawValue], stdin: "", windowId: nil, workspace: nil)
    _ = await connection.writeAtomic(req)
    _ = await connection.readNonAtomic()
}

private let serverVersionAndHash = "\(appVersion) \(gitHash)"

private func newConnection(_ connection: NWConnection) async { // todo add exit codes
    func answerToClient(exitCode: Int32, stdout: String = "", stderr: String = "") async {
        let ans = ServerAnswer(exitCode: exitCode, stdout: stdout, stderr: stderr, serverVersionAndHash: serverVersionAndHash)
        await answerToClient(ans)
    }
    func answerToClient(_ ans: ServerAnswer) async {
        _ = await connection.writeAtomic(ans)
    }

    guard let clientVersion = await connection.readUInt32().getIgnoringErrorsOrNil() else { return }
    // The server unconditionally answers with the only version it supports
    if await connection.writeUInt32(SOCKET_PROTOCOL_VERSION).error != nil { return }
    if clientVersion != SOCKET_PROTOCOL_VERSION { return }

    while true {
        guard let rawRequest = await connection.readNonAtomic().getOrNil(onFailure: { err in
            await answerToClient(exitCode: EXIT_CODE_TWO, stderr: "Error: \(err)")
        }) else { return }
        guard let request = await ClientRequest.decodeJson(rawRequest).getOrNil(onFailure: { err in
            let msg = """
                Can't parse request \(String(describing: String(data: rawRequest, encoding: .utf8)).singleQuoted).
                Error: \(err)
                """
            return await answerToClient(exitCode: EXIT_CODE_TWO, stderr: msg)
        }) else { continue }
        // Handle subscribe before parseCommand (subscribe doesn't have a Command impl)
        if request.args.first == "subscribe" {
            switch parseSubscribeCmdArgs(request.args.slice(1...).orDie()) {
                case .cmd(let subscribeArgs): await handleSubscribeAndWaitTillError(connection, subscribeArgs)
                case .help(let help): await answerToClient(exitCode: EXIT_CODE_ZERO, stdout: help)
                case .failure(let err): await answerToClient(exitCode: err.exitCode, stderr: err.msg)
            }
            continue
        }
        let parsedCmd = parseCommand(request.args)
        let restartRequestID = UUID()
        if case .cmd(let command) = parsedCmd, command is RestartCommand {
            // Restart must not pass through runLightSession: even its normal
            // post-command relayout would move windows before the replacement.
            let result = await RestartReplyContext.$requestID.withValue(restartRequestID) {
                await command.run(.defaultEnv, CmdStdin(request.stdin))
            }
            let answer = ServerAnswer(
                exitCode: result.exitCode.rawValue,
                stdout: result.stdout.joined(separator: "\n"),
                stderr: result.stderr.joined(separator: "\n"),
                serverVersionAndHash: serverVersionAndHash,
            )
            if await connection.writeAtomic(answer).error != nil {
                await cancelPreparedMacarchyRestart(for: restartRequestID)
            } else if result.exitCode.rawValue == EXIT_CODE_ZERO {
                do { try await finishPreparedMacarchyRestart(for: restartRequestID) }
                catch { await reportSessionFailure("Could not restart Macarchy", error: error) }
            }
            continue
        }
        guard let token: RunSessionGuard = await .isServerEnabled(orIsEnableCommand: parsedCmd.cmdOrNil) else {
            await answerToClient(
                exitCode: EXIT_CODE_TWO,
                stderr: "\(appName) server is disabled and doesn't accept commands. " +
                    "You can use 'macarchy enable on' to enable the server",
            )
            continue
        }
        switch parsedCmd {
            case .help(let help):
                await answerToClient(exitCode: EXIT_CODE_ZERO, stdout: help)
                continue
            case .failure(let err):
                await answerToClient(exitCode: err.exitCode, stderr: err.msg)
                continue
            case .cmd(let command):
                var answer: ServerAnswer =
                    await Result {
                        try await runLightSession(.socketServer(command.args), token) { () throws in
                            let env = CmdEnv.init(
                                windowId: request.windowId.flattenOptional(),
                                workspaceName: request.workspace.flattenOptional(),
                            )
                            let cmdResult = await RestartReplyContext.$requestID.withValue(restartRequestID) {
                                await command.run(env, CmdStdin(request.stdin))
                            }
                            return ServerAnswer(
                                exitCode: cmdResult.exitCode.rawValue,
                                stdout: cmdResult.stdout.joined(separator: "\n"),
                                stderr: cmdResult.stderr.joined(separator: "\n"),
                                serverVersionAndHash: serverVersionAndHash,
                            )
                        }
                    }
                    .get { err in
                        ServerAnswer(
                            exitCode: command.args.failExitCode,
                            stderr: "Fail to await main thread. \(err.localizedDescription)",
                            serverVersionAndHash: serverVersionAndHash,
                        )
                    }
                if request.windowId == nil || request.workspace == nil {
                    answer.stderr += "\n\nMacarchy client has sent incomplete JSON request. 'windowId' or/and 'workspace' fields are missing. Please forward your MACARCHY_WINDOW_ID and MACARCHY_WORKSPACE environment variables to these JSON fields. If the appropriate environment variables are empty, pass explicit 'null' in the JSON."
                }
                if await connection.writeAtomic(answer).error != nil {
                    await cancelPreparedMacarchyRestart(for: restartRequestID)
                } else {
                    do { try await finishPreparedMacarchyRestart(for: restartRequestID) }
                    catch { await reportSessionFailure("Could not restart Macarchy", error: error) }
                }
                continue
        }
    }
}
