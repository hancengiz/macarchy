import Common
import Foundation
import Network

public enum ServerClientError: Error, CustomStringConvertible {
    case cannotConnect
    case badAnswer

    public var description: String {
        switch self {
            case .cannotConnect: "Can't connect to the macarchy server. Is macarchy.app running?"
            case .badAnswer: "The server sent a malformed answer."
        }
    }
}

/// One-shot request client over the WM server's UNIX socket (same wire protocol as the CLI).
public struct ServerClient {
    public init() {}

    public func run(_ args: [String], stdin: String = "") async -> Result<ServerAnswer, ServerClientError> {
        let connection = NWConnection(to: NWEndpoint.unix(path: socketPath), using: .tcp)
        if await connection.initConnection().error != nil {
            return .failure(.cannotConnect)
        }
        let request = ClientRequest(args: args, stdin: stdin, windowId: nil, workspace: nil)
        if await connection.writeAtomic(request).error != nil {
            return .failure(.cannotConnect)
        }
        switch await connection.readNonAtomic() {
            case .success(let data):
                if let answer = try? JSONDecoder().decode(ServerAnswer.self, from: data) {
                    return .success(answer)
                }
                return .failure(.badAnswer)
            case .failure:
                return .failure(.cannotConnect)
        }
    }
}
