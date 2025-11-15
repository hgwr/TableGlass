import Foundation

public struct SSHTunnelHandle: Sendable, Hashable {
    public let identifier: UUID
    public let localPort: Int

    public init(identifier: UUID = UUID(), localPort: Int) {
        self.identifier = identifier
        self.localPort = localPort
    }
}

public protocol SSHTunnelManager: Sendable {
    func establishTunnel(for profile: ConnectionProfile) async throws -> SSHTunnelHandle
    func closeTunnel(_ handle: SSHTunnelHandle) async
}

public struct NoopSSHTunnelManager: SSHTunnelManager {
    public init() {}

    public func establishTunnel(for profile: ConnectionProfile) async throws -> SSHTunnelHandle {
        _ = profile
        return SSHTunnelHandle(localPort: 0)
    }

    public func closeTunnel(_ handle: SSHTunnelHandle) async {
        _ = handle
    }
}
