import Foundation

public protocol SSHAgentService: Sendable {
    func isAgentReachable() -> Bool
}

public struct DefaultSSHAgentService: SSHAgentService {
    private let environment: [String: String]
    private let fileAccess: any SSHFileAccessing

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.init(environment: environment, fileAccess: DefaultSSHFileAccess())
    }

    init(
        environment: [String: String],
        fileAccess: any SSHFileAccessing
    ) {
        self.environment = environment
        self.fileAccess = fileAccess
    }

    public func isAgentReachable() -> Bool {
        guard let socketPath = environment["SSH_AUTH_SOCK"], !socketPath.isEmpty else {
            return false
        }

        var isDirectory: ObjCBool = false
        guard fileAccess.fileExists(atPath: socketPath, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return false
        }

        return fileAccess.isReadableFile(atPath: socketPath)
    }
}

protocol SSHFileAccessing: Sendable {
    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool
    func isReadableFile(atPath path: String) -> Bool
}

struct DefaultSSHFileAccess: SSHFileAccessing {
    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        FileManager.default.fileExists(atPath: path, isDirectory: isDirectory)
    }

    func isReadableFile(atPath path: String) -> Bool {
        FileManager.default.isReadableFile(atPath: path)
    }
}
