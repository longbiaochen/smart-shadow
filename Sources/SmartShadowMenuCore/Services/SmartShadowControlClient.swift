import Foundation

public struct CommandExecutionError: Error, CustomStringConvertible, Sendable {
    public let command: String
    public let status: Int32
    public let output: String

    public init(command: String, status: Int32, output: String) {
        self.command = command
        self.status = status
        self.output = output
    }

    public var description: String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "\(command) failed with status \(status)"
        }
        return "\(command) failed with status \(status): \(trimmed)"
    }
}

public struct SmartShadowControlClient: Sendable {
    public let projectRoot: String

    public init(projectRoot: String = SmartShadowControlClient.defaultProjectRoot()) {
        self.projectRoot = projectRoot
    }

    public func refreshSnapshot() throws -> MenuSnapshot {
        let service = try serviceStatus()
        let health = try? healthStatus()
        return .success(serviceStatus: service, healthStatus: health)
    }

    public func serviceStatus() throws -> ServiceStatus {
        try ServiceStatus(jsonData: runSmartShadow(["service-status"]))
    }

    public func healthStatus() throws -> HealthStatus {
        try HealthStatus(jsonData: runSmartShadow(["health"]))
    }

    @discardableResult
    public func startService() throws -> Data {
        try runSmartShadow(["start"])
    }

    @discardableResult
    public func stopService() throws -> Data {
        try runSmartShadow(["stop"])
    }

    @discardableResult
    public func writeReport() throws -> Data {
        try runSmartShadow(["report"])
    }

    @discardableResult
    public func openPath(_ path: String) throws -> Data {
        try runCommand("/usr/bin/open", arguments: [path])
    }

    private func runSmartShadow(_ arguments: [String]) throws -> Data {
        try runCommand("\(projectRoot)/bin/smart-shadow", arguments: arguments)
    }

    private func runCommand(_ executable: String, arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: projectRoot)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus == 0 {
            return data
        }

        let output = String(data: data, encoding: .utf8) ?? ""
        let command = ([executable] + arguments).joined(separator: " ")
        throw CommandExecutionError(command: command, status: process.terminationStatus, output: output)
    }

    public static func defaultProjectRoot() -> String {
        if let configured = ProcessInfo.processInfo.environment["SMART_SHADOW_PROJECT_ROOT"],
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return configured
        }

        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app",
           bundleURL.deletingLastPathComponent().lastPathComponent == "dist" {
            return bundleURL.deletingLastPathComponent().deletingLastPathComponent().path
        }

        return "/Users/longbiao/Projects/smart-shadow"
    }
}
