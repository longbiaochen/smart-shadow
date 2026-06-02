import AppKit
import Foundation
import SmartShadowMenuCore

@MainActor
final class StatusPanelStore: ObservableObject {
    @Published private(set) var snapshot = MenuSnapshot.failure(
        CommandExecutionError(command: "initial refresh", status: 1, output: "waiting")
    )
    @Published private(set) var isWorking = false
    @Published var lastActionMessage: String?

    private let client = SmartShadowControlClient()

    func refresh() async {
        let client = self.client
        await runAction(successMessage: nil) {
            try client.refreshSnapshot()
        }
    }

    func startService() async {
        let client = self.client
        await runAction(successMessage: "服务已启动") {
            _ = try client.startService()
            return try client.refreshSnapshot()
        }
    }

    func stopService() async {
        let client = self.client
        await runAction(successMessage: "服务已停止") {
            _ = try client.stopService()
            return try client.refreshSnapshot()
        }
    }

    func writeReport() async {
        let client = self.client
        await runAction(successMessage: "用户报告已生成") {
            _ = try client.writeReport()
            return try client.refreshSnapshot()
        }
    }

    func openProject() {
        openPath(client.projectRoot)
    }

    func openLogs() {
        let logsDir = SmartShadowFormatters.compactPathDirectory(snapshot.serviceStatus?.logs.audit)
            ?? "\(client.projectRoot)/var/logs"
        openPath(logsDir)
    }

    private func openPath(_ path: String) {
        do {
            _ = try client.openPath(path)
            lastActionMessage = "已打开 \(URL(fileURLWithPath: path).lastPathComponent)"
        } catch {
            snapshot = .failure(error)
        }
    }

    private func runAction(successMessage: String?, _ work: @escaping @Sendable () throws -> MenuSnapshot) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let next = try await Task.detached(priority: .userInitiated) {
                try work()
            }.value
            snapshot = next
            lastActionMessage = successMessage
        } catch {
            snapshot = .failure(error)
            lastActionMessage = nil
        }
    }
}
