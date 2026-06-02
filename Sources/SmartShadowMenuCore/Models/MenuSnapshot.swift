import Foundation

public struct MenuSnapshot: Sendable {
    public let serviceStatus: ServiceStatus?
    public let healthStatus: HealthStatus?
    public let refreshedAt: Date
    public let errorMessage: String?

    public var summary: ServiceSummary {
        if serviceStatus == nil {
            return .unknown
        }
        return serviceStatus?.summary ?? .unknown
    }

    public static func success(serviceStatus: ServiceStatus, healthStatus: HealthStatus?) -> MenuSnapshot {
        MenuSnapshot(
            serviceStatus: serviceStatus,
            healthStatus: healthStatus,
            refreshedAt: Date(),
            errorMessage: nil
        )
    }

    public static func failure(_ error: Error) -> MenuSnapshot {
        MenuSnapshot(
            serviceStatus: nil,
            healthStatus: nil,
            refreshedAt: Date(),
            errorMessage: String(describing: error)
        )
    }
}

