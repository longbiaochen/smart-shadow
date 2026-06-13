import Foundation
import Testing
@testable import SmartShadowMenuCore

@Test func statusSummaryClassifiesHealthyService() throws {
    let status = try ServiceStatus(jsonData: Data(SelfFixtures.healthy.utf8))

    #expect(status.summary == .running)
    #expect(status.launchd.loaded)
    #expect(status.lastRunReport?.fresh == true)
    #expect(status.attention.isEmpty)
}

@Test func statusSummaryClassifiesAttentionWithoutCallingItStopped() throws {
    let status = try ServiceStatus(jsonData: Data(SelfFixtures.attention.utf8))

    #expect(status.summary == .attention)
    #expect(status.launchd.loaded)
    #expect(status.attention.map(\.code) == ["audit_report_missing", "source_blocked"])
    #expect(status.sourceDoctor.sources.last?.name == "apple_reminders_inbox")
}

@Test func statusSummaryClassifiesStoppedLaunchAgent() throws {
    let status = try ServiceStatus(jsonData: Data(SelfFixtures.stopped.utf8))

    #expect(status.summary == .stopped)
    #expect(status.launchd.loaded == false)
}

@Test func commandFailureCreatesUnknownSnapshot() {
    let snapshot = MenuSnapshot.failure(
        CommandExecutionError(command: "bin/smart-shadow service-status", status: 1, output: "not json")
    )

    #expect(snapshot.summary == .unknown)
    #expect(snapshot.errorMessage?.contains("service-status") == true)
}

@Test func controlClientDefaultsToProjectRootInsteadOfLaunchDirectory() {
    let client = SmartShadowControlClient()

    #expect(client.projectRoot == "/Users/longbiao/Projects/smart-shadow")
}

enum SelfFixtures {
    static let healthy = """
    {
      "status": "ok",
      "overall_state": "ok",
      "poll_seconds": 10,
      "eventkit": {"calendar": "authorized_legacy", "reminders": "authorized_legacy", "mode": "swift-native-eventkit"},
      "launchd": {"loaded": true, "detail": "loaded", "target": "gui/501/me.longbiaochen.smart-shadow", "launchctl_status": 0},
      "last_run_report": {"timestamp": "2026-06-02T07:47:48Z", "processed_count": 2, "error_count": 0, "fresh": true, "age_seconds": 3, "stale_after_seconds": 30, "path": "/tmp/run.json"},
      "attention": [],
      "logs": {"audit": "/tmp/audit.jsonl", "launchd_stdout": "/tmp/out.log", "launchd_stderr": "/tmp/err.log"},
      "source_doctor": {"sources": []}
    }
    """

    static let attention = """
    {
      "status": "ok",
      "overall_state": "attention_required",
      "poll_seconds": 10,
      "eventkit": {"calendar": "authorized_legacy", "reminders": "authorized_legacy", "mode": "swift-native-eventkit"},
      "launchd": {"loaded": true, "detail": "loaded", "target": "gui/501/me.longbiaochen.smart-shadow", "launchctl_status": 0},
      "last_run_report": {"timestamp": "2026-06-02T07:47:48Z", "processed_count": 0, "error_count": 0, "fresh": true, "age_seconds": 2, "stale_after_seconds": 30, "path": "/tmp/run.json"},
      "attention": [
        {"code": "audit_report_missing", "message": "Last audit event references a report path that no longer exists.", "suggested_command": "bin/smart-shadow service-status"},
        {"code": "source_blocked", "message": "A sensing source is not ready to enable.", "source": "apple_reminders_inbox", "suggested_command": "bin/smart-shadow accept-source apple_reminders_inbox"}
      ],
      "logs": {"audit": "/tmp/audit.jsonl", "launchd_stdout": "/tmp/out.log", "launchd_stderr": "/tmp/err.log"},
      "source_doctor": {
        "sources": [
          {"name": "file_metadata", "enabled": false, "ready_to_enable": true, "blockers": [], "acceptance_status": "ok"},
          {"name": "apple_reminders_inbox", "enabled": false, "ready_to_enable": false, "blockers": ["missing_acceptance_report"]}
        ]
      }
    }
    """

    static let stopped = """
    {
      "status": "ok",
      "overall_state": "ok",
      "poll_seconds": 10,
      "eventkit": {"calendar": "authorized_legacy", "reminders": "authorized_legacy", "mode": "swift-native-eventkit"},
      "launchd": {"loaded": false, "detail": "not_loaded", "target": "gui/501/me.longbiaochen.smart-shadow", "launchctl_status": 113},
      "last_run_report": null,
      "attention": [],
      "logs": {"audit": "/tmp/audit.jsonl", "launchd_stdout": "/tmp/out.log", "launchd_stderr": "/tmp/err.log"},
      "source_doctor": {"sources": []}
    }
    """
}
