import Common
import Foundation

@MainActor
public final class PermissionStatusModel: ObservableObject {
    public enum State: Equatable {
        case unknown
        case serverNotRunning
        case waiting // server up but no windows managed: grant pending or fresh install
        case granted(windowsCount: Int)

        public var isGranted: Bool {
            if case .granted = self { true } else { false }
        }
    }
    @Published public private(set) var state: State = .unknown
    private let probe: () async -> Result<ServerAnswer, ServerClientError>

    public init(probe: (() async -> Result<ServerAnswer, ServerClientError>)? = nil) {
        if let probe {
            self.probe = probe
        } else {
            let client = ServerClient()
            self.probe = { await client.run(["list-windows", "--all", "--count"]) }
        }
    }

    public func refresh() async {
        switch await probe() {
            case .failure: state = .serverNotRunning
            case .success(let answer):
                let count = Int(answer.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                if answer.exitCode == 0, let count, count > 0 {
                    state = .granted(windowsCount: count)
                } else {
                    state = .waiting
                }
        }
    }
}
