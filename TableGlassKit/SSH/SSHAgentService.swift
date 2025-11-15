import Foundation

public protocol SSHAgentService: Sendable {
    func isAgentReachable() -> Bool
}

public struct DefaultSSHAgentService: SSHAgentService {
    private let environment: [String: String]
    private let fileManager: FileManager

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.fileManager = fileManager
    }

    public func isAgentReachable() -> Bool {
        guard let socketPath = environment["SSH_AUTH_SOCK"], !socketPath.isEmpty else {
            return false
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: socketPath, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }

        return fileManager.isReadableFile(atPath: socketPath)
    }
}
