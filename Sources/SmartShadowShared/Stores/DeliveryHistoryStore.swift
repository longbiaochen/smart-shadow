import Foundation

public final class DeliveryHistoryStore {
    public private(set) var deliveries: [VoicePacketDelivery]

    private let defaults: UserDefaults
    private let key: String
    private let limit: Int

    public init(defaults: UserDefaults = .standard, key: String = "voicePacketDeliveryHistory", limit: Int = 10) {
        self.defaults = defaults
        self.key = key
        self.limit = limit
        deliveries = Self.load(defaults: defaults, key: key)
    }

    public func record(_ delivery: VoicePacketDelivery) {
        deliveries.insert(delivery, at: 0)
        deliveries = Array(deliveries.prefix(limit))
        if let data = try? JSONEncoder().encode(deliveries) {
            defaults.set(data, forKey: key)
        }
    }

    public func clear() {
        deliveries = []
        defaults.removeObject(forKey: key)
    }

    private static func load(defaults: UserDefaults, key: String) -> [VoicePacketDelivery] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([VoicePacketDelivery].self, from: data)) ?? []
    }
}
