import Foundation
import Persistence

struct GroupMetadataUpsert: DomainUpsert, Equatable {
    let id: String
    let name: String
    let usage: String
    let picto: String?
    let isGroupUser: Bool
    let isGroupAll: Bool
}

struct GroupMembershipUpsert: DomainUpsert, Equatable {
    let id: String
    let memberIdentifiers: [DeviceIdentifier]
}

enum GroupUpsertEvent: DomainUpsert {
    case metadata(GroupMetadataUpsert)
    case membership(GroupMembershipUpsert)

    var id: String {
        switch self {
        case .metadata(let metadata):
            metadata.id
        case .membership(let membership):
            membership.id
        }
    }
}

typealias GroupRepository = DomainRepository<Group, GroupUpsertEvent>

extension DomainRepository where Item == Group, Upsert == GroupUpsertEvent {
    static func makeGroupRepository(
        createDAO: @escaping GroupRepository.DAOFactory,
        now: @escaping @Sendable () -> Date = Date.init,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) -> Self {
        Self(
            configuration: .init(
                resolveUpsert: resolveUpsert,
                idValue: { .text($0) }
            ),
            createDAO: createDAO,
            now: now,
            log: log
        )
    }

    static func makeGroupRepository(
        databasePath: String,
        now: @escaping @Sendable () -> Date = Date.init,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) -> Self {
        makeGroupRepository(
            createDAO: {
                let database = try SQLiteDatabase(path: databasePath)
                try database.execute(createTableSQL)
                try database.execute(createDashboardOrderIndexSQL)

                let schema = TableSchema<Group>.codable(
                    table: tableName,
                    primaryKey: "id"
                )

                return DAO.make(database: database, schema: schema)
            },
            now: now,
            log: log
        )
    }

    func upsertMetadata(_ values: [GroupMetadataUpsert]) throws {
        try upsert(values.map(GroupUpsertEvent.metadata))
    }

    func upsertMembership(_ values: [GroupMembershipUpsert]) throws {
        try upsert(values.map(GroupUpsertEvent.membership))
    }

    private static func resolveUpsert(
        existing: Group?,
        upsert: GroupUpsertEvent,
        timestamp: Date
    ) -> DomainMergeDecision<Group> {
        switch upsert {
        case .metadata(let metadata):
            return .upsert(makeGroup(existing: existing, metadata: metadata, timestamp: timestamp))
        case .membership(let membership):
            return .upsert(makeGroup(existing: existing, membership: membership, timestamp: timestamp))
        }
    }

    private static func makeGroup(
        existing: Group?,
        metadata: GroupMetadataUpsert,
        timestamp: Date
    ) -> Group {
        let memberIdentifiers = existing?.memberIdentifiers.uniquePreservingOrder() ?? []

        return Group(
            id: metadata.id,
            name: metadata.name,
            usage: metadata.usage,
            picto: metadata.picto,
            isGroupUser: metadata.isGroupUser,
            isGroupAll: metadata.isGroupAll,
            memberIdentifiers: memberIdentifiers,
            isFavorite: existing?.isFavorite ?? false,
            dashboardOrder: existing?.dashboardOrder,
            updatedAt: timestamp
        )
    }

    private static func makeGroup(
        existing: Group?,
        membership: GroupMembershipUpsert,
        timestamp: Date
    ) -> Group {
        let memberIdentifiers = membership.memberIdentifiers.uniquePreservingOrder()

        let isGroupUser = existing?.isGroupUser ?? false

        return Group(
            id: membership.id,
            name: existing?.name ?? "Group \(membership.id)",
            usage: existing?.usage ?? "unknown",
            picto: existing?.picto,
            isGroupUser: isGroupUser,
            isGroupAll: existing?.isGroupAll ?? false,
            memberIdentifiers: memberIdentifiers,
            isFavorite: existing?.isFavorite ?? false,
            dashboardOrder: existing?.dashboardOrder,
            updatedAt: timestamp
        )
    }

    private static let tableName = "groups"

    private static let createTableSQL = """
    CREATE TABLE IF NOT EXISTS \(tableName) (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        usage TEXT NOT NULL,
        picto TEXT,
        isGroupUser INTEGER NOT NULL,
        isGroupAll INTEGER NOT NULL,
        memberIdentifiers TEXT NOT NULL,
        isFavorite INTEGER NOT NULL,
        dashboardOrder INTEGER,
        updatedAt REAL NOT NULL
    );
    """

    private static let createDashboardOrderIndexSQL = """
    CREATE INDEX IF NOT EXISTS groups_favorites_order_idx
    ON \(tableName) (isFavorite, dashboardOrder);
    """
}
