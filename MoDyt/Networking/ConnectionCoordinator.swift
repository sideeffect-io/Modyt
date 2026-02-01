import Foundation
import DeltaDoreClient

actor ConnectionCoordinator {
    private let client: DeltaDoreClient
    private var session: DeltaDoreClient.ConnectionSession?
    private var messageStream: AsyncStream<TydomMessage>?

    init(client: DeltaDoreClient = .live()) {
        self.client = client
    }

    func connect(
        options: DeltaDoreClient.Options,
        selectSiteIndex: DeltaDoreClient.SiteIndexSelector? = nil
    ) async throws -> DeltaDoreClient.ConnectionSession {
        let session = try await client.connect(options: options, selectSiteIndex: selectSiteIndex)
        self.session = session
        self.messageStream = await session.connection.decodedMessages()
        return session
    }

    func disconnect() async {
        await session?.connection.disconnect()
        session = nil
        messageStream = nil
    }

    func setAppActive(_ isActive: Bool) async {
        guard let connection = session?.connection else { return }
        await connection.setAppActive(isActive)
    }

    func send(_ command: TydomCommand) async throws {
        guard let connection = session?.connection else { return }
        try await connection.send(text: command.request)
    }

    func stream() -> AsyncStream<TydomMessage>? {
        messageStream
    }

}
