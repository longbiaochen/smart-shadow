import XCTest
@testable import SmartShadowShared

final class DeliveryHistoryStoreTests: XCTestCase {
    func testRecordPersistsMostRecentDeliveriesFirstWithLimit() throws {
        let defaults = UserDefaults(suiteName: "SmartShadowSharedTests.\(UUID().uuidString)")!
        let store = DeliveryHistoryStore(defaults: defaults, limit: 2)

        store.record(.fixture(packetID: "old"))
        store.record(.fixture(packetID: "middle"))
        store.record(.fixture(packetID: "new"))

        let restored = DeliveryHistoryStore(defaults: defaults, limit: 2)
        XCTAssertEqual(restored.deliveries.map(\.packetID), ["new", "middle"])
    }
}

private extension VoicePacketDelivery {
    static func fixture(packetID: String) -> VoicePacketDelivery {
        VoicePacketDelivery(
            packetID: packetID,
            repositoryPath: "inbox/pending/2026-06-08/\(packetID)",
            uploadedAt: "2026-06-08T09:10:11Z",
            status: .uploaded,
            errorMessage: nil
        )
    }
}
