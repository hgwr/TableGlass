import TableGlassKit
import Testing

@testable import TableGlass

struct SSHTunnelManagerTests {

    @Test func mockTunnelManagerTracksEstablishmentAndClosure() async throws {
        let profile = ConnectionProfile(
            name: "Mocked Tunnel",
            kind: .postgreSQL,
            host: "db.internal",
            port: 5432,
            username: "dbuser",
            sshConfiguration: .init(isEnabled: true, configAlias: "bastion", username: "sshuser")
        )

        let expectedHandle = SSHTunnelHandle(localPort: 33_222)
        let manager = MockSSHTunnelManager(handle: expectedHandle)

        let handle = try await manager.establishTunnel(for: profile)
        #expect(handle == expectedHandle)

        let establishedProfiles = await manager.establishedProfiles()
        #expect(establishedProfiles == [profile])

        await manager.closeTunnel(handle)

        let closedHandles = await manager.closedHandles()
        #expect(closedHandles == [handle])
    }
}

actor MockSSHTunnelManager: SSHTunnelManager {
    private var recordedProfiles: [ConnectionProfile] = []
    private var recordedClosures: [SSHTunnelHandle] = []
    private let handle: SSHTunnelHandle

    init(handle: SSHTunnelHandle = SSHTunnelHandle(localPort: 0)) {
        self.handle = handle
    }

    func establishTunnel(for profile: ConnectionProfile) async throws -> SSHTunnelHandle {
        recordedProfiles.append(profile)
        return handle
    }

    func closeTunnel(_ handle: SSHTunnelHandle) async {
        recordedClosures.append(handle)
    }

    func establishedProfiles() -> [ConnectionProfile] {
        recordedProfiles
    }

    func closedHandles() -> [SSHTunnelHandle] {
        recordedClosures
    }
}
