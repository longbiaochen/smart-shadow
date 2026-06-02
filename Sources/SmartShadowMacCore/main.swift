import EventKit
import Foundation
import CryptoKit
import SQLite3

let launchdLabel = "me.longbiaochen.smart-shadow"
let launchdTarget = "\(NSHomeDirectory())/Library/LaunchAgents/\(launchdLabel).plist"
let configurableSources = ["file_metadata", "lark_daily_context", "chrome_bookmarks", "apple_reminders_inbox", "apple_mail_summary", "apple_mail_app"]

enum AppError: Error, CustomStringConvertible {
    case usage(String)
    case runtime(String)

    var description: String {
        switch self {
        case let .usage(message), let .runtime(message):
            return message
        }
    }
}

struct Signal {
    let source: String
    let sourceID: String
    let title: String
    let body: String
    let kind: String
    let occurredAt: String
    let metadata: [String: Any]

    var dedupeKey: String { "\(source):\(sourceID)" }
}

struct Decision: Codable {
    let domain: String
    let priority: String
    let risk: String
    let needsReview: Bool
    let action: String
    let reason: String
    let confidence: String
}

struct ActionResult {
    let action: String
    let status: String
    let detail: String
    let externalID: String?
}

struct ProjectionRecord {
    let canonicalKey: String
    let reminderExternalID: String?
    let calendarExternalID: String?
}

struct RuleRegistry: Codable {
    let version: Int
    let domainRules: [String: [String]]
    let sourceDefaultDomains: [String: String]
    let rules: [Rule]

    enum CodingKeys: String, CodingKey {
        case version
        case domainRules = "domain_rules"
        case sourceDefaultDomains = "source_default_domains"
        case rules
    }
}

struct Rule: Codable {
    let ruleID: String
    let scope: String
    let sources: [String]?
    let triggers: [String]
    let domain: String?
    let priority: String
    let risk: String
    let needsReview: Bool
    let action: String
    let confidence: String
    let rationale: String

    enum CodingKeys: String, CodingKey {
        case ruleID = "rule_id"
        case scope
        case sources
        case triggers
        case domain
        case priority
        case risk
        case needsReview = "needs_review"
        case action
        case confidence
        case rationale
    }
}

struct AppConfig {
    let raw: [String: Any]
    let configPath: String
    let projectRoot: String
    let runtimeRoot: String
    let eventInbox: String
    let dbPath: String
    let auditLog: String
    let reports: String
    let rulesFile: String
    let pollSeconds: UInt32
    let remindersEnabled: Bool
    let domainLists: [String: String]
    let autoCreateReviewReminders: Bool
    let autoArchiveLowValue: Bool

    func sourceConfig(_ name: String) -> [String: Any] {
        let sources = raw["sources"] as? [String: Any] ?? [:]
        return sources[name] as? [String: Any] ?? [:]
    }
}

struct ProjectionInput {
    var title = "智能影子工作项验收"
    var domain = "work"
    var due: String?
    var start: String?
    var end: String?
    var priority = "high"
    var flagged = true
    var review = true
    var notes = "这是智能影子生成的人类可读工作说明。"
}

final class EventKitRequestResult: @unchecked Sendable {
    private let lock = NSLock()
    private var grantedValue = false
    private var errorValue: Error?

    func complete(granted: Bool, error: Error?) {
        lock.lock()
        grantedValue = granted
        errorValue = error
        lock.unlock()
    }

    var granted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return grantedValue
    }

    var error: Error? {
        lock.lock()
        defer { lock.unlock() }
        return errorValue
    }
}

final class ReminderFetchResult: @unchecked Sendable {
    private let lock = NSLock()
    private var remindersValue: [EKReminder] = []
    private var errorValue: Error?

    func complete(reminders: [EKReminder]?, error: Error?) {
        lock.lock()
        remindersValue = reminders ?? []
        errorValue = error
        lock.unlock()
    }

    var reminders: [EKReminder] {
        lock.lock()
        defer { lock.unlock() }
        return remindersValue
    }

    var error: Error? {
        lock.lock()
        defer { lock.unlock() }
        return errorValue
    }
}

@main
struct SmartShadowMacCore {
    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            fputs("smart-shadow: \(error)\n", stderr)
            exit(1)
        }
    }
}

func run(_ originalArguments: [String]) throws {
    var arguments = originalArguments
    var configPath = defaultConfigPath()
    if arguments.first == "--config" {
        guard arguments.count >= 3 else { throw AppError.usage("--config requires a path and command") }
        configPath = arguments[1]
        arguments.removeFirst(2)
    }
    guard let command = arguments.first else {
        printUsage()
        return
    }
    let rest = Array(arguments.dropFirst())

    switch command {
    case "help", "--help", "-h":
        printUsage()
    case "init":
        let config = try loadConfig(configPath)
        try ensureRuntime(config)
        printJSON(["status": "initialized", "runtime_root": config.runtimeRoot])
    case "eventkit-status", "status-eventkit":
        printJSON(eventKitStatus())
    case "eventkit-request-access", "request-eventkit-access":
        let target = rest.first ?? "all"
        printJSON(try requestEventKitAccess(target: target))
    case "eventkit-list", "list-eventkit":
        try listCalendarsAndReminderLists()
    case "plan-sample":
        let input = try parseProjectionInput(rest)
        printJSON(planProjection(input))
    case "sample-event":
        let config = try loadConfig(configPath)
        try ensureRuntime(config)
        let sample = optionValue(rest, "--sample") ?? "\(config.projectRoot)/samples/review-request.json"
        let target = "\(config.eventInbox)/\(URL(fileURLWithPath: sample).lastPathComponent)"
        try FileManager.default.copyItemReplacingIfNeeded(atPath: sample, toPath: target)
        printJSON(["status": "queued", "event": target])
    case "rules":
        let config = try loadConfig(configPath)
        let registry = try loadRuleRegistry(config.rulesFile)
        printJSON(registry.rules)
    case "validate-rules":
        let config = try loadConfig(configPath)
        let registry = try loadRuleRegistry(config.rulesFile)
        printJSON(["status": "ok", "version": registry.version, "rule_count": registry.rules.count])
    case "run-once":
        let config = try loadConfig(configPath)
        let noReminders = rest.contains("--no-reminders")
        let dryRun = rest.contains("--dry-run")
        printJSON(try runOnce(config, dryRun: dryRun, noReminders: noReminders))
    case "accept-source":
        let config = try loadConfig(configPath)
        let name = rest.first ?? ""
        let limit = Int(optionValue(rest, "--limit") ?? "25") ?? 25
        printJSON(try acceptSource(config, name: name, limit: limit))
    case "sources":
        let config = try loadConfig(configPath)
        try ensureRuntime(config)
        printJSON(try sourceStatus(config))
    case "source-doctor":
        let config = try loadConfig(configPath)
        try ensureRuntime(config)
        printJSON(sourceDoctor(config))
    case "service-status":
        let config = try loadConfig(configPath)
        try ensureRuntime(config)
        printJSON(try serviceStatus(config))
    case "enable-source":
        let config = try loadConfig(configPath)
        try ensureRuntime(config)
        let name = rest.first ?? ""
        let result = try updateSourceEnabled(config, name: name, enabled: true, force: rest.contains("--force"))
        try appendAudit(config, ["type": "source_config_updated"].merging(result) { _, new in new })
        printJSON(result)
    case "disable-source":
        let config = try loadConfig(configPath)
        try ensureRuntime(config)
        let name = rest.first ?? ""
        let result = try updateSourceEnabled(config, name: name, enabled: false, force: true)
        try appendAudit(config, ["type": "source_config_updated"].merging(result) { _, new in new })
        printJSON(result)
    case "health":
        let config = try loadConfig(configPath)
        try ensureRuntime(config)
        let state = try StateStore(path: config.dbPath)
        defer { state.close() }
        printJSON([
            "status": "ok",
            "runtime_root": config.runtimeRoot,
            "eventkit": eventKitStatus(),
            "counts": try state.counts(),
            "recent": try state.recent(limit: 10),
            "recent_projections": try state.projections(limit: 10)
        ] as [String: Any])
    case "reviews":
        let config = try loadConfig(configPath)
        let state = try StateStore(path: config.dbPath)
        defer { state.close() }
        let limit = Int(optionValue(rest, "--limit") ?? "20") ?? 20
        printJSON(try state.reviewQueue(limit: limit))
    case "rebuild-projections":
        let config = try loadConfig(configPath)
        try ensureRuntime(config)
        let state = try StateStore(path: config.dbPath)
        defer { state.close() }
        let result = try state.rebuildProjectionsFromActions()
        try appendAudit(config, ["type": "projections_rebuilt"].merging(result) { _, new in new })
        printJSON(result)
    case "report":
        let config = try loadConfig(configPath)
        let state = try StateStore(path: config.dbPath)
        defer { state.close() }
        let limit = Int(optionValue(rest, "--limit") ?? "50") ?? 50
        let path = try writeUserReport(config, items: state.reportItems(limit: limit))
        printJSON(["status": "written", "report_path": path])
    case "rule-feedback":
        let config = try loadConfig(configPath)
        try ensureRuntime(config)
        let limit = Int(optionValue(rest, "--limit") ?? "50") ?? 50
        printJSON(try summarizeRuleFeedback(config, limit: limit))
    case "record-rule-feedback":
        let config = try loadConfig(configPath)
        try ensureRuntime(config)
        let result = try recordRuleFeedbackCommand(config, arguments: rest)
        try appendAudit(config, ["type": "rule_feedback_recorded"].merging(result) { _, new in new })
        printJSON(["status": "ok", "entry": result, "recent": try listRuleFeedback(config, limit: 5)] as [String: Any])
    case "daemon":
        let config = try loadConfig(configPath)
        try ensureRuntime(config)
        try appendAudit(config, ["type": "daemon_started", "poll_seconds": config.pollSeconds])
        while true {
            _ = try runOnce(config, dryRun: false, noReminders: false)
            sleep(config.pollSeconds)
        }
    case "install-launchd":
        let config = try loadConfig(configPath)
        try ensureRuntime(config)
        let exe = try executablePath()
        let plist = launchdPlist(executable: exe, configPath: config.configPath, projectRoot: config.projectRoot)
        try FileManager.default.createDirectory(atPath: URL(fileURLWithPath: launchdTarget).deletingLastPathComponent().path, withIntermediateDirectories: true)
        try plist.write(toFile: launchdTarget, atomically: true, encoding: .utf8)
        printJSON(["status": "installed", "plist": launchdTarget])
    case "start":
        let config = try loadConfig(configPath)
        try ensureRuntime(config)
        let exe = try executablePath()
        let plist = launchdPlist(executable: exe, configPath: config.configPath, projectRoot: config.projectRoot)
        try FileManager.default.createDirectory(atPath: URL(fileURLWithPath: launchdTarget).deletingLastPathComponent().path, withIntermediateDirectories: true)
        try plist.write(toFile: launchdTarget, atomically: true, encoding: .utf8)
        let uid = try shellOutput(["id", "-u"]).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try? shellOutput(["launchctl", "bootstrap", "gui/\(uid)", launchdTarget])
        _ = try? shellOutput(["launchctl", "kickstart", "-k", "gui/\(uid)/\(launchdLabel)"])
        printJSON(["status": "started", "label": launchdLabel])
    case "stop":
        let uid = try shellOutput(["id", "-u"]).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try? shellOutput(["launchctl", "bootout", "gui/\(uid)/\(launchdLabel)"])
        printJSON(["status": "stopped", "label": launchdLabel])
    default:
        throw AppError.usage("Unknown command: \(command)")
    }
}

func printUsage() {
    print("""
    smart-shadow [--config PATH] init
    smart-shadow [--config PATH] run-once [--dry-run] [--no-reminders]
    smart-shadow [--config PATH] accept-source file_metadata|lark_daily_context|chrome_bookmarks|apple_reminders_inbox|apple_mail_summary|apple_mail_app [--limit N]
    smart-shadow [--config PATH] sources
    smart-shadow [--config PATH] source-doctor
    smart-shadow [--config PATH] service-status
    smart-shadow [--config PATH] enable-source file_metadata|lark_daily_context|chrome_bookmarks|apple_reminders_inbox|apple_mail_summary|apple_mail_app [--force]
    smart-shadow [--config PATH] disable-source file_metadata|lark_daily_context|chrome_bookmarks|apple_reminders_inbox|apple_mail_summary|apple_mail_app
    smart-shadow [--config PATH] daemon
    smart-shadow [--config PATH] health
    smart-shadow [--config PATH] reviews [--limit N]
    smart-shadow [--config PATH] rebuild-projections
    smart-shadow [--config PATH] report [--limit N]
    smart-shadow [--config PATH] rule-feedback [--limit N]
    smart-shadow [--config PATH] record-rule-feedback RULE_ID accepted|adjusted|retired|rejected --note TEXT [--evidence PATH] [--source TEXT]
    smart-shadow [--config PATH] rules
    smart-shadow [--config PATH] validate-rules
    smart-shadow [--config PATH] sample-event [--sample PATH]
    smart-shadow eventkit-status
    smart-shadow eventkit-request-access [calendar|reminders|all]
    smart-shadow eventkit-list
    smart-shadow plan-sample [--title TEXT] [--domain work|money|health|relationship] [--due YYYY-MM-DD] [--start ISO8601] [--end ISO8601] [--priority low|medium|high] [--flagged true|false] [--review true|false] [--notes TEXT]
    smart-shadow [--config PATH] install-launchd
    smart-shadow [--config PATH] start
    smart-shadow stop
    """)
}

func nowISO() -> String {
    isoString(Date())
}

func isoString(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}

func loadConfig(_ path: String) throws -> AppConfig {
    let configPath = absolutePath(path, base: FileManager.default.currentDirectoryPath)
    let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
    guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw AppError.runtime("Config must be a JSON object.")
    }
    let configDirectory = URL(fileURLWithPath: configPath).deletingLastPathComponent().path
    let inferredProjectRoot = URL(fileURLWithPath: configDirectory).deletingLastPathComponent().path
    let projectRoot = absolutePath(raw["project_root"] as? String ?? inferredProjectRoot, base: FileManager.default.currentDirectoryPath)
    let runtimeRoot = absolutePath(raw["runtime_root"] as? String ?? "var", base: projectRoot)
    let sources = raw["sources"] as? [String: Any] ?? [:]
    let reminders = raw["reminders"] as? [String: Any] ?? [:]
    let actions = raw["actions"] as? [String: Any] ?? [:]
    return AppConfig(
        raw: raw,
        configPath: configPath,
        projectRoot: projectRoot,
        runtimeRoot: runtimeRoot,
        eventInbox: absolutePath(sources["event_inbox"] as? String ?? "inbox/events", base: runtimeRoot),
        dbPath: "\(runtimeRoot)/state.sqlite",
        auditLog: "\(runtimeRoot)/logs/audit.jsonl",
        reports: "\(runtimeRoot)/reports",
        rulesFile: absolutePath(raw["rules_file"] as? String ?? "config/rules.json", base: projectRoot),
        pollSeconds: UInt32(raw["poll_seconds"] as? Int ?? 10),
        remindersEnabled: reminders["enabled"] as? Bool ?? true,
        domainLists: reminders["domain_lists"] as? [String: String] ?? [:],
        autoCreateReviewReminders: actions["auto_create_review_reminders"] as? Bool ?? true,
        autoArchiveLowValue: actions["auto_archive_low_value"] as? Bool ?? true
    )
}

func defaultConfigPath() -> String {
    "\(FileManager.default.currentDirectoryPath)/config/smart-shadow.json"
}

func absolutePath(_ rawPath: String, base: String) -> String {
    let expanded = (rawPath as NSString).expandingTildeInPath
    if expanded.hasPrefix("/") { return expanded }
    return URL(fileURLWithPath: expanded, relativeTo: URL(fileURLWithPath: base)).standardizedFileURL.path
}

func configuredPath(_ rawPath: String, config: AppConfig) -> String {
    absolutePath(rawPath, base: config.projectRoot)
}

func ensureRuntime(_ config: AppConfig) throws {
    for path in [config.runtimeRoot, config.eventInbox, URL(fileURLWithPath: config.auditLog).deletingLastPathComponent().path, config.reports] {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }
}

func loadRuleRegistry(_ path: String) throws -> RuleRegistry {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let decoder = JSONDecoder()
    let registry = try decoder.decode(RuleRegistry.self, from: data)
    try validate(registry)
    return registry
}

func validate(_ registry: RuleRegistry) throws {
    var seen = Set<String>()
    for rule in registry.rules {
        if seen.contains(rule.ruleID) { throw AppError.runtime("Duplicate rule_id: \(rule.ruleID)") }
        seen.insert(rule.ruleID)
        if !["global", "source"].contains(rule.scope) { throw AppError.runtime("Invalid scope for \(rule.ruleID)") }
        if !["low", "normal", "high"].contains(rule.priority) { throw AppError.runtime("Invalid priority for \(rule.ruleID)") }
        if !["low", "medium", "high"].contains(rule.risk) { throw AppError.runtime("Invalid risk for \(rule.ruleID)") }
        if !["record_only", "archive_low_value", "create_review_reminder"].contains(rule.action) { throw AppError.runtime("Invalid action for \(rule.ruleID)") }
        if rule.scope == "source", (rule.sources ?? []).isEmpty { throw AppError.runtime("Source rule missing sources: \(rule.ruleID)") }
    }
}

func inferDomain(_ signal: Signal, _ registry: RuleRegistry) -> String {
    if let expected = signal.metadata["expected_domain"] as? String,
       ["money", "health", "relationship", "work"].contains(expected) {
        return expected
    }
    let text = "\(signal.title)\n\(signal.body)\n\(signal.kind)".lowercased()
    var bestDomain = registry.sourceDefaultDomains[signal.source] ?? "work"
    var bestScore = 0
    let orderedDomains = ["money", "health", "relationship", "work"] + registry.domainRules.keys.sorted().filter { !["money", "health", "relationship", "work"].contains($0) }
    for domain in orderedDomains {
        guard let words = registry.domainRules[domain] else { continue }
        let score = words.filter { text.contains($0.lowercased()) }.count
        if score > bestScore {
            bestScore = score
            bestDomain = domain
        }
    }
    return bestDomain
}

func decide(_ signal: Signal, _ registry: RuleRegistry) -> Decision {
    let text = "\(signal.title)\n\(signal.body)\n\(signal.kind)".lowercased()
    let domain = inferDomain(signal, registry)
    for rule in registry.rules {
        if let sources = rule.sources, !sources.isEmpty, !sources.contains(signal.source) {
            continue
        }
        if rule.triggers.isEmpty || rule.triggers.contains(where: { text.contains($0.lowercased()) }) {
            return Decision(
                domain: rule.domain ?? domain,
                priority: rule.priority,
                risk: rule.risk,
                needsReview: rule.needsReview,
                action: rule.action,
                reason: "\(rule.ruleID): \(rule.rationale)",
                confidence: rule.confidence
            )
        }
    }
    return Decision(domain: domain, priority: "normal", risk: "low", needsReview: false, action: "record_only", reason: "fallback.record_only: 普通低风险信号，先记录审计，等待更多上下文。", confidence: "low")
}

func runOnce(_ config: AppConfig, dryRun: Bool, noReminders: Bool) throws -> [String: Any] {
    try ensureRuntime(config)
    let state = try StateStore(path: config.dbPath)
    defer { state.close() }
    let registry = try loadRuleRegistry(config.rulesFile)
    var processed: [[String: Any]] = []
    var errors: [[String: Any]] = []

    for signal in try collectEnabledSources(config) {
        do {
            let result = try processSignal(config, state: state, registry: registry, signal: signal, dryRun: dryRun, noReminders: noReminders)
            processed.append(result)
        } catch {
            errors.append(["source": signal.source, "source_id": signal.sourceID, "error": "\(error)"])
            try? appendAudit(config, ["type": "source_signal_error", "source": signal.source, "source_id": signal.sourceID, "error": "\(error)"])
        }
    }

    let files = (try? FileManager.default.contentsOfDirectory(atPath: config.eventInbox)) ?? []
    for name in files.sorted() where name.hasSuffix(".json") {
        let path = "\(config.eventInbox)/\(name)"
        do {
            let signal = try loadSignal(path)
            let result = try processSignal(config, state: state, registry: registry, signal: signal, dryRun: dryRun, noReminders: noReminders)
            processed.append(result)
            try quarantine(config, path: path, folder: "processed")
        } catch {
            errors.append(["path": path, "error": "\(error)"])
            try? appendAudit(config, ["type": "processing_error", "path": path, "error": "\(error)"])
            try? quarantine(config, path: path, folder: "failed")
        }
    }

    let report: [String: Any] = [
        "timestamp": nowISO(),
        "processed_count": processed.count,
        "error_count": errors.count,
        "processed": processed,
        "errors": errors,
        "counts": try state.counts()
    ]
    let reportPath = "\(config.reports)/run-\(Int(Date().timeIntervalSince1970)).json"
    try writeJSON(report, to: reportPath)
    var output = report
    output["report_path"] = reportPath
    return output
}

func collectEnabledSources(_ config: AppConfig) throws -> [Signal] {
    var signals: [Signal] = []
    let fileConfig = config.sourceConfig("file_metadata")
    if fileConfig["enabled"] as? Bool == true {
        signals.append(contentsOf: try collectFileMetadata(config, limit: nil))
    }
    let larkConfig = config.sourceConfig("lark_daily_context")
    if larkConfig["enabled"] as? Bool == true {
        signals.append(contentsOf: try collectLarkDailyContext(config))
    }
    let bookmarksConfig = config.sourceConfig("chrome_bookmarks")
    if bookmarksConfig["enabled"] as? Bool == true {
        signals.append(contentsOf: try collectChromeBookmarks(config, limit: nil))
    }
    let remindersConfig = config.sourceConfig("apple_reminders_inbox")
    if remindersConfig["enabled"] as? Bool == true {
        signals.append(contentsOf: try collectAppleRemindersInbox(config, limit: nil))
    }
    let mailConfig = config.sourceConfig("apple_mail_summary")
    if mailConfig["enabled"] as? Bool == true {
        signals.append(contentsOf: try collectAppleMailSummary(config, limit: nil))
    }
    let mailAppConfig = config.sourceConfig("apple_mail_app")
    if mailAppConfig["enabled"] as? Bool == true {
        signals.append(contentsOf: try collectAppleMailApp(config, limit: nil))
    }
    return signals
}

func sourceStatus(_ config: AppConfig) throws -> [String: Any] {
    let sources = configurableSources.map { name -> [String: Any] in
        let sourceConfig = config.sourceConfig(name)
        let report = latestAcceptanceReport(config, source: name)
        return [
            "name": name,
            "enabled": sourceConfig["enabled"] as? Bool ?? false,
            "acceptance_report": report ?? NSNull(),
            "acceptance_status": report.map { sourceAcceptanceStatus(reportPath: $0) } ?? NSNull()
        ]
    }
    return ["status": "ok", "sources": sources]
}

func sourceDoctor(_ config: AppConfig) -> [String: Any] {
    let sources = configurableSources.map { sourceDoctorItem(config, name: $0) }
    return [
        "status": "ok",
        "eventkit": eventKitStatus(),
        "sources": sources
    ] as [String: Any]
}

func sourceDoctorItem(_ config: AppConfig, name: String) -> [String: Any] {
    let sourceConfig = config.sourceConfig(name)
    let enabled = sourceConfig["enabled"] as? Bool ?? false
    let report = latestAcceptanceReport(config, source: name)
    let acceptanceStatus = report.map { sourceAcceptanceStatus(reportPath: $0) }
    var blockers: [String] = []
    if report == nil {
        blockers.append("missing_acceptance_report")
    } else if acceptanceStatus != "ok" {
        blockers.append("acceptance_not_ok")
    }
    blockers.append(contentsOf: authorizationBlockersForSource(name))
    return [
        "name": name,
        "enabled": enabled,
        "acceptance_report": report ?? NSNull(),
        "acceptance_status": acceptanceStatus ?? NSNull(),
        "ready_to_enable": blockers.isEmpty,
        "blockers": blockers
    ] as [String: Any]
}

func authorizationBlockersForSource(_ name: String) -> [String] {
    switch name {
    case "apple_reminders_inbox":
        let status = EKEventStore.authorizationStatus(for: .reminder)
        return isEventKitAuthorized(status, for: .reminder) ? [] : ["eventkit_reminders_\(authorizationDescription(status))"]
    default:
        return []
    }
}

func serviceStatus(_ config: AppConfig) throws -> [String: Any] {
    let launchd = try launchdStatus()
    let runReport = latestRunReport(config)
    let auditEvent = latestAuditEvent(config)
    let sourceState = sourceDoctor(config)
    let attention = serviceAttention(launchd: launchd, runReport: runReport, auditEvent: auditEvent, sourceState: sourceState)
    let logs: [String: Any] = [
        "audit": config.auditLog,
        "launchd_stdout": "\(config.projectRoot)/var/logs/launchd.out.log",
        "launchd_stderr": "\(config.projectRoot)/var/logs/launchd.err.log"
    ]
    return [
        "status": "ok",
        "label": launchdLabel,
        "plist_path": launchdTarget,
        "plist_installed": FileManager.default.fileExists(atPath: launchdTarget),
        "runtime_root": config.runtimeRoot,
        "event_inbox": config.eventInbox,
        "poll_seconds": config.pollSeconds,
        "logs": logs,
        "launchd": launchd,
        "last_run_report": runReport,
        "last_audit_event": auditEvent,
        "eventkit": eventKitStatus(),
        "source_doctor": sourceState,
        "overall_state": attention.isEmpty ? "ok" : "attention_required",
        "attention": attention
    ] as [String: Any]
}

func serviceAttention(launchd: [String: Any], runReport: Any, auditEvent: Any, sourceState: [String: Any]) -> [[String: Any]] {
    var items: [[String: Any]] = []
    if launchd["loaded"] as? Bool != true {
        items.append(["code": "launchd_not_loaded", "message": "LaunchAgent is not loaded.", "suggested_command": "bin/smart-shadow start"])
    }
    if runReport is NSNull {
        items.append(["code": "missing_run_report", "message": "No run report found under var/reports.", "suggested_command": "bin/smart-shadow run-once --dry-run --no-reminders"])
    } else if let run = runReport as? [String: Any], run["fresh"] as? Bool == false {
        items.append([
            "code": "last_run_stale",
            "message": "Latest run report is older than the configured freshness window.",
            "age_seconds": run["age_seconds"] ?? NSNull(),
            "stale_after_seconds": run["stale_after_seconds"] ?? NSNull(),
            "suggested_command": "bin/smart-shadow service-status"
        ])
    }
    if let audit = auditEvent as? [String: Any],
       audit["report_path"] is String,
       audit["report_exists"] as? Bool == false {
        items.append([
            "code": "audit_report_missing",
            "message": "Last audit event references a report path that no longer exists.",
            "report_path": audit["report_path"] ?? NSNull(),
            "suggested_command": "bin/smart-shadow service-status"
        ])
    }
    if let sources = sourceState["sources"] as? [[String: Any]] {
        for source in sources {
            if source["ready_to_enable"] as? Bool == false {
                items.append([
                    "code": "source_blocked",
                    "message": "A sensing source is not ready to enable.",
                    "source": source["name"] ?? NSNull(),
                    "blockers": source["blockers"] ?? [],
                    "suggested_command": suggestedCommandForSourceBlocker(source)
                ])
            }
        }
    }
    return items
}

func suggestedCommandForSourceBlocker(_ source: [String: Any]) -> String {
    let name = source["name"] as? String ?? ""
    let blockers = source["blockers"] as? [String] ?? []
    if blockers.contains(where: { $0.hasPrefix("eventkit_reminders_") }) {
        return "bin/smart-shadow eventkit-request-access reminders"
    }
    if blockers.contains("missing_acceptance_report") {
        return "bin/smart-shadow accept-source \(name)"
    }
    return "bin/smart-shadow source-doctor"
}

func latestRunReport(_ config: AppConfig) -> Any {
    let files = (try? FileManager.default.contentsOfDirectory(atPath: config.reports)) ?? []
    guard let newest = files.filter({ $0.hasPrefix("run-") && $0.hasSuffix(".json") }).sorted().last else {
        return NSNull()
    }
    let path = "\(config.reports)/\(newest)"
    var output: [String: Any] = ["path": path]
    if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
       let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        for key in ["timestamp", "processed_count", "error_count"] {
            output[key] = payload[key] ?? NSNull()
        }
        let staleAfter = Int(config.pollSeconds) * 3
        output["stale_after_seconds"] = staleAfter
        if let timestamp = payload["timestamp"] as? String, let date = parseDate(timestamp) {
            let age = max(0, Int(Date().timeIntervalSince(date)))
            output["age_seconds"] = age
            output["fresh"] = age <= staleAfter
        } else {
            output["age_seconds"] = NSNull()
            output["fresh"] = false
        }
    }
    return output
}

func latestAuditEvent(_ config: AppConfig) -> Any {
    guard let text = try? String(contentsOfFile: config.auditLog, encoding: .utf8) else {
        return NSNull()
    }
    guard let line = text.components(separatedBy: .newlines).last(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
        return NSNull()
    }
    guard let data = line.data(using: .utf8),
          var event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return ["raw": line]
    }
    if let reportPath = event["report_path"] as? String {
        event["report_exists"] = FileManager.default.fileExists(atPath: reportPath)
    }
    return event
}

func launchdStatus() throws -> [String: Any] {
    let uid = try shellOutput(["id", "-u"]).trimmingCharacters(in: .whitespacesAndNewlines)
    let target = "gui/\(uid)/\(launchdLabel)"
    let result = try shellResult(["launchctl", "print", target])
    let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    return [
        "target": target,
        "loaded": result.status == 0,
        "launchctl_status": result.status,
        "detail": result.status == 0 ? "loaded" : (detail.isEmpty ? "not_loaded" : firstLine(detail))
    ] as [String: Any]
}

func updateSourceEnabled(_ config: AppConfig, name: String, enabled: Bool, force: Bool) throws -> [String: Any] {
    guard configurableSources.contains(name) else {
        throw AppError.usage("Unsupported configurable source: \(name)")
    }
    if enabled && !force {
        guard let report = latestAcceptanceReport(config, source: name) else {
            throw AppError.runtime("No source acceptance report found for \(name); run `bin/smart-shadow accept-source \(name)` first or pass --force.")
        }
        let status = sourceAcceptanceStatus(reportPath: report)
        guard status == "ok" else {
            throw AppError.runtime("Latest source acceptance report for \(name) is not ok (status: \(status)): \(report)")
        }
    }
    if enabled {
        try requireAuthorizationForSource(name)
    }
    var raw = config.raw
    guard var sources = raw["sources"] as? [String: Any],
          var sourceConfig = sources[name] as? [String: Any]
    else {
        throw AppError.runtime("Missing source config: \(name)")
    }
    let before = sourceConfig["enabled"] as? Bool ?? false
    if before == enabled {
        return [
            "status": "ok",
            "source": name,
            "enabled_before": before,
            "enabled_after": enabled,
            "config_backup": NSNull(),
            "message": "Source already in requested state."
        ]
    }
    let backup = try backupConfig(config)
    sourceConfig["enabled"] = enabled
    sources[name] = sourceConfig
    raw["sources"] = sources
    try writeJSONObject(raw, to: config.configPath)
    return [
        "status": "ok",
        "source": name,
        "enabled_before": before,
        "enabled_after": enabled,
        "config_backup": backup,
        "acceptance_report": latestAcceptanceReport(config, source: name) ?? NSNull()
    ]
}

func backupConfig(_ config: AppConfig) throws -> String {
    let stamp = nowISO().replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "/", with: "-")
    let backup = "\(config.configPath).bak-\(stamp)"
    try FileManager.default.copyItemReplacingIfNeeded(atPath: config.configPath, toPath: backup)
    return backup
}

func latestAcceptanceReport(_ config: AppConfig, source: String) -> String? {
    let prefix = "source-acceptance-\(source)-"
    let files = (try? FileManager.default.contentsOfDirectory(atPath: config.reports)) ?? []
    guard let newest = files.filter({ $0.hasPrefix(prefix) && $0.hasSuffix(".md") }).sorted().last else {
        return nil
    }
    return "\(config.reports)/\(newest)"
}

func requireAuthorizationForSource(_ name: String) throws {
    switch name {
    case "apple_reminders_inbox":
        try requireEventKitAuthorization(for: .reminder, operation: "enable Apple Reminders Inbox sensing")
    default:
        return
    }
}

func sourceAcceptanceStatus(reportPath: String) -> String {
    guard let text = try? String(contentsOfFile: reportPath, encoding: .utf8) else {
        return "missing"
    }
    for line in text.components(separatedBy: .newlines) {
        if line.hasPrefix("状态：") {
            return String(line.dropFirst("状态：".count)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        if line.lowercased().hasPrefix("status:") {
            return String(line.dropFirst("status:".count)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }
    return "unknown"
}

func collectSource(_ config: AppConfig, name: String, limit: Int?) throws -> [Signal] {
    switch name {
    case "file_metadata":
        return try collectFileMetadata(config, limit: limit)
    case "lark_daily_context":
        return try collectLarkDailyContext(config)
    case "chrome_bookmarks":
        return try collectChromeBookmarks(config, limit: limit)
    case "apple_reminders_inbox":
        return try collectAppleRemindersInbox(config, limit: limit)
    case "apple_mail_summary":
        return try collectAppleMailSummary(config, limit: limit)
    case "apple_mail_app":
        return try collectAppleMailApp(config, limit: limit)
    default:
        throw AppError.usage("Unsupported source acceptance target: \(name)")
    }
}

func collectFileMetadata(_ config: AppConfig, limit: Int?) throws -> [Signal] {
    let sourceConfig = config.sourceConfig("file_metadata")
    let paths = sourceConfig["paths"] as? [String] ?? []
    let maxItems = limit ?? sourceConfig["max_items"] as? Int ?? 25
    let maxAgeHours = sourceConfig["max_age_hours"] as? Double ?? Double(sourceConfig["max_age_hours"] as? Int ?? 24)
    let ignoreNames = Set(sourceConfig["ignore_names"] as? [String] ?? [])
    let cutoff = Date().addingTimeInterval(-maxAgeHours * 3600)
    var candidates: [(date: Date, url: URL, size: UInt64)] = []

    for rawPath in paths {
        let root = URL(fileURLWithPath: configuredPath(rawPath, config: config))
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            continue
        }
        let contents = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles])) ?? []
        for url in contents {
            if ignoreNames.contains(url.lastPathComponent) || url.lastPathComponent.hasPrefix(".") {
                continue
            }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey])
            guard values?.isRegularFile == true, let modified = values?.contentModificationDate, modified >= cutoff else {
                continue
            }
            candidates.append((date: modified, url: url, size: UInt64(values?.fileSize ?? 0)))
        }
    }

    candidates.sort { $0.date > $1.date }
    return candidates.prefix(maxItems).map { item in
        let sourceID = "\(item.url.path):\(Int(item.date.timeIntervalSince1970)):\(item.size)"
        let body = [
            "路径: \(item.url.path)",
            "大小: \(item.size) bytes",
            "修改时间: \(isoString(item.date))",
            "内容: 未读取"
        ].joined(separator: "\n")
        return Signal(
            source: "file_metadata",
            sourceID: sourceID,
            title: "新文件: \(item.url.lastPathComponent)",
            body: body,
            kind: "local_file_metadata",
            occurredAt: isoString(item.date),
            metadata: [
                "path": item.url.path,
                "size": item.size,
                "modified_at": isoString(item.date),
                "readonly_metadata": true,
                "content_read": false
            ]
        )
    }
}

func collectLarkDailyContext(_ config: AppConfig) throws -> [Signal] {
    let sourceConfig = config.sourceConfig("lark_daily_context")
    guard let commands = sourceConfig["commands"] as? [[String: Any]] else {
        throw AppError.runtime("lark_daily_context.commands must be a list.")
    }
    let timeout = TimeInterval(sourceConfig["timeout_seconds"] as? Double ?? Double(sourceConfig["timeout_seconds"] as? Int ?? 20))
    let maxItems = sourceConfig["max_items_per_command"] as? Int ?? 20
    let maxBodyChars = sourceConfig["max_body_chars"] as? Int ?? 4000
    var signals: [Signal] = []

    for (index, command) in commands.enumerated() {
        let label = command["label"] as? String ?? "command-\(index + 1)"
        guard let argv = command["argv"] as? [String], !argv.isEmpty else {
            throw AppError.runtime("lark_daily_context command \(label) must define argv.")
        }
        let raw = try runExternalCommand(argv, timeout: timeout)
        let parsed = compactLarkCommandOutput(raw, label: label, maxItems: maxItems, maxBodyChars: maxBodyChars)
        let rawHash = sha256Prefix(raw)
        signals.append(
            Signal(
                source: "lark_daily_context",
                sourceID: "\(label):\(rawHash)",
                title: "飞书日上下文: \(label)",
                body: parsed.body,
                kind: "lark_daily_context",
                occurredAt: nowISO(),
                metadata: [
                    "label": label,
                    "item_count": parsed.count,
                    "readonly_external_command": true,
                    "argv0": argv[0]
                ]
            )
        )
    }
    return signals
}

func compactLarkCommandOutput(_ raw: String, label: String, maxItems: Int, maxBodyChars: Int) -> (body: String, count: Int) {
    let parsed = (try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as Any?
    let records = jsonRecords(parsed)
    var lines = ["来源: 飞书 \(label)", "模式: 只读日上下文", ""]
    for record in records.prefix(maxItems) {
        lines.append("- \(compactRecord(record))")
    }
    if records.count > maxItems {
        lines.append("- 另有 \(records.count - maxItems) 条未展开")
    }
    var body = lines.joined(separator: "\n")
    if body.count > maxBodyChars {
        body = String(body.prefix(max(0, maxBodyChars - 12))) + "\n...(已截断)"
    }
    return (body, records.count)
}

func jsonRecords(_ value: Any?) -> [[String: Any]] {
    if let items = value as? [[String: Any]] {
        return items
    }
    guard let object = value as? [String: Any] else {
        return []
    }
    for key in ["items", "events", "tasks", "records"] {
        if let items = object[key] as? [[String: Any]] {
            return items
        }
    }
    if let data = object["data"] {
        let nested = jsonRecords(data)
        if !nested.isEmpty {
            return nested
        }
    }
    return [object]
}

func compactRecord(_ record: [String: Any]) -> String {
    let title = record["summary"] ?? record["title"] ?? record["name"] ?? record["task_summary"] ?? record["content"] ?? record["event_id"] ?? record["guid"] ?? "(untitled)"
    var fields = [String(describing: title)]
    for key in ["start_time", "end_time", "due", "due_time", "self_rsvp_status", "free_busy_status", "url"] {
        if let value = record[key], !(value is NSNull) {
            fields.append("\(key)=\(value)")
        }
    }
    return fields.joined(separator: " | ")
}

func runExternalCommand(_ argv: [String], timeout: TimeInterval) throws -> String {
    try runExternalCommand(argv, timeout: timeout, environment: nil)
}

func runExternalCommand(_ argv: [String], timeout: TimeInterval, environment: [String: String]?) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = argv
    if let environment {
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
    }
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    try process.run()
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    if process.isRunning {
        process.terminate()
        throw AppError.runtime("External command timed out: \(argv.joined(separator: " "))")
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let text = String(data: data, encoding: .utf8) ?? ""
    guard process.terminationStatus == 0 else {
        throw AppError.runtime("External command failed: \(argv.first ?? "command"): \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
    return text
}

func sha256Prefix(_ text: String) -> String {
    let digest = SHA256.hash(data: Data(text.utf8))
    return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
}

func collectChromeBookmarks(_ config: AppConfig, limit: Int?) throws -> [Signal] {
    let sourceConfig = config.sourceConfig("chrome_bookmarks")
    let rawPath = sourceConfig["bookmarks_file"] as? String ?? "~/Library/Application Support/Google/Chrome/Default/Bookmarks"
    let bookmarksPath = configuredPath(rawPath, config: config)
    let maxItems = limit ?? sourceConfig["max_items"] as? Int ?? 25
    let maxAgeDays = sourceConfig["max_age_days"] as? Double ?? Double(sourceConfig["max_age_days"] as? Int ?? 30)
    let ignoredSchemes = Set(sourceConfig["ignored_schemes"] as? [String] ?? ["chrome", "javascript", "file"])
    let data = try Data(contentsOf: URL(fileURLWithPath: bookmarksPath))
    guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let roots = raw["roots"] as? [String: Any]
    else {
        return []
    }
    let cutoff = Date().addingTimeInterval(-maxAgeDays * 86_400)
    var bookmarks: [[String: Any]] = []
    for (rootName, value) in roots {
        if let node = value as? [String: Any] {
            bookmarks.append(contentsOf: flattenBookmarkNode(node, folderPath: [rootName]))
        }
    }
    bookmarks.sort {
        chromeDate($0["date_added"]) > chromeDate($1["date_added"])
    }

    var signals: [Signal] = []
    for item in bookmarks {
        let added = chromeDate(item["date_added"])
        if added < cutoff {
            continue
        }
        let url = item["url"] as? String ?? ""
        let components = URLComponents(string: url)
        let scheme = components?.scheme ?? ""
        if ignoredSchemes.contains(scheme) {
            continue
        }
        let title = item["name"] as? String ?? "(untitled bookmark)"
        let domain = components?.host ?? ""
        let folderPath = item["folder_path"] as? String ?? ""
        let bookmarkID = item["id"] as? String ?? sha256Prefix(url)
        let addedAt = isoString(added)
        let body = [
            "标题: \(title)",
            "域名: \(domain)",
            "文件夹: \(folderPath)",
            "加入时间: \(addedAt)",
            "网页内容: 未读取"
        ].joined(separator: "\n")
        signals.append(
            Signal(
                source: "chrome_bookmarks",
                sourceID: "\(bookmarkID):\(item["date_added"] ?? "")",
                title: "新书签: \(title)",
                body: body,
                kind: "chrome_bookmark_metadata",
                occurredAt: addedAt,
                metadata: [
                    "url": url,
                    "domain": domain,
                    "folder_path": folderPath,
                    "readonly_bookmarks_file": true,
                    "content_read": false
                ]
            )
        )
        if signals.count >= maxItems {
            break
        }
    }
    return signals
}

func collectAppleRemindersInbox(_ config: AppConfig, limit: Int?) throws -> [Signal] {
    try requireEventKitAuthorization(for: .reminder, operation: "read Apple Reminders Inbox source")
    let sourceConfig = config.sourceConfig("apple_reminders_inbox")
    let listName = sourceConfig["list"] as? String ?? "Inbox"
    let maxItems = limit ?? sourceConfig["max_items"] as? Int ?? 10
    let store = EKEventStore()
    guard let list = store.calendars(for: .reminder).first(where: { $0.title == listName }) ?? store.defaultCalendarForNewReminders() else {
        throw AppError.runtime("No Reminder list found for apple_reminders_inbox: \(listName)")
    }

    let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [list])
    let fetch = ReminderFetchResult()
    let semaphore = DispatchSemaphore(value: 0)
    store.fetchReminders(matching: predicate) { reminders in
        fetch.complete(reminders: reminders, error: nil)
        semaphore.signal()
    }
    semaphore.wait()
    if let error = fetch.error {
        throw AppError.runtime("Failed to fetch Apple Reminders Inbox: \(error.localizedDescription)")
    }

    let reminders = fetch.reminders.sorted { left, right in
        reminderSortDate(left) > reminderSortDate(right)
    }

    return reminders.prefix(maxItems).map { reminder in
        let sourceID = "x-apple-reminder://\(reminder.calendarItemIdentifier)"
        let reminderTitle = reminder.title ?? "(untitled reminder)"
        let due = reminder.dueDateComponents.flatMap { Calendar(identifier: .gregorian).date(from: $0) }
        let start = reminder.startDateComponents.flatMap { Calendar(identifier: .gregorian).date(from: $0) }
        let occurredAt = isoString(reminderSortDate(reminder))
        let body = [
            "标题: \(reminderTitle)",
            "列表: \(list.title)",
            "截止: \(due.map(isoString) ?? "无")",
            "开始: \(start.map(isoString) ?? "无")",
            "优先级: \(reminder.priority)",
            "状态: 未完成",
            "备注: \(reminder.notes ?? "")"
        ].joined(separator: "\n")
        var metadata: [String: Any] = [
            "calendar_item_identifier": reminder.calendarItemIdentifier,
            "list": list.title,
            "priority": reminder.priority,
            "completed": reminder.isCompleted,
            "readonly_eventkit": true,
            "canonical_key": "apple_reminders_inbox:\(sourceID)"
        ]
        if let due {
            metadata["due_date"] = isoString(due)
        }
        if let start {
            metadata["start_date"] = isoString(start)
        }
        return Signal(
            source: "apple_reminders_inbox",
            sourceID: sourceID,
            title: "提醒事项: \(reminderTitle)",
            body: body,
            kind: "apple_reminder_inbox_item",
            occurredAt: occurredAt,
            metadata: metadata
        )
    }
}

func reminderSortDate(_ reminder: EKReminder) -> Date {
    if let due = reminder.dueDateComponents.flatMap({ Calendar(identifier: .gregorian).date(from: $0) }) {
        return due
    }
    if let start = reminder.startDateComponents.flatMap({ Calendar(identifier: .gregorian).date(from: $0) }) {
        return start
    }
    return reminder.creationDate ?? Date.distantPast
}

func collectAppleMailSummary(_ config: AppConfig, limit: Int?) throws -> [Signal] {
    let sourceConfig = config.sourceConfig("apple_mail_summary")
    guard let rawPath = sourceConfig["messages_file"] as? String else {
        throw AppError.runtime("apple_mail_summary.messages_file must point to a local JSON summary file.")
    }
    let messagesPath = configuredPath(rawPath, config: config)
    let maxItems = limit ?? sourceConfig["max_items"] as? Int ?? 25
    let maxSummaryChars = sourceConfig["max_summary_chars"] as? Int ?? 1200
    let data = try Data(contentsOf: URL(fileURLWithPath: messagesPath))
    let parsed = try JSONSerialization.jsonObject(with: data)
    let messages = mailSummaryRecords(parsed)

    return messages.prefix(maxItems).enumerated().map { index, message in
        let subject = stringField(message, ["subject", "title"]) ?? "(no subject)"
        let sender = stringField(message, ["sender", "from"]) ?? "(unknown sender)"
        let mailbox = stringField(message, ["mailbox", "folder"]) ?? "unknown"
        let receivedAt = stringField(message, ["received_at", "date", "occurred_at"]) ?? nowISO()
        let summary = stringField(message, ["summary", "snippet", "preview"]) ?? ""
        let sourceID = stringField(message, ["source_id", "message_id", "id"]) ?? sha256Prefix("\(sender)\n\(subject)\n\(receivedAt)\n\(index)")
        let bodySummary = summary.count > maxSummaryChars ? String(summary.prefix(max(0, maxSummaryChars - 12))) + "\n...(已截断)" : summary
        let body = [
            "发件人: \(sender)",
            "主题: \(subject)",
            "邮箱: \(mailbox)",
            "收信时间: \(receivedAt)",
            "摘要: \(bodySummary)",
            "正文: 未读取"
        ].joined(separator: "\n")
        return Signal(
            source: "apple_mail_summary",
            sourceID: sourceID,
            title: "邮件摘要: \(subject)",
            body: body,
            kind: "apple_mail_summary_metadata",
            occurredAt: receivedAt,
            metadata: [
                "sender": sender,
                "subject": subject,
                "mailbox": mailbox,
                "received_at": receivedAt,
                "readonly_summary_file": true,
                "body_read": false
            ]
        )
    }
}

func collectAppleMailApp(_ config: AppConfig, limit: Int?) throws -> [Signal] {
    let sourceConfig = config.sourceConfig("apple_mail_app")
    guard let argv = sourceConfig["reader_argv"] as? [String], !argv.isEmpty else {
        throw AppError.runtime("apple_mail_app.reader_argv must define a Mail.app reader command.")
    }
    let timeout = TimeInterval(sourceConfig["timeout_seconds"] as? Double ?? Double(sourceConfig["timeout_seconds"] as? Int ?? 20))
    let maxItems = limit ?? sourceConfig["max_items"] as? Int ?? 25
    let maxBodyChars = sourceConfig["max_body_chars"] as? Int ?? 4000
    let raw = try runExternalCommand(argv, timeout: timeout)
    let parsed = try JSONSerialization.jsonObject(with: Data(raw.utf8))
    let messages = mailSummaryRecords(parsed)

    return messages.prefix(maxItems).enumerated().map { index, message in
        let subject = stringField(message, ["subject", "title"]) ?? "(no subject)"
        let sender = stringField(message, ["sender", "from"]) ?? "(unknown sender)"
        let mailbox = stringField(message, ["mailbox", "folder"]) ?? "unknown"
        let receivedAt = stringField(message, ["received_at", "date", "occurred_at"]) ?? nowISO()
        let summary = stringField(message, ["summary", "snippet", "preview"]) ?? ""
        let bodyText = stringField(message, ["body", "content", "text"])
        let sourceID = stringField(message, ["source_id", "message_id", "id"]) ?? sha256Prefix("\(sender)\n\(subject)\n\(receivedAt)\n\(index)")
        let readableBody = bodyText ?? summary
        let trimmedBody = readableBody.count > maxBodyChars ? String(readableBody.prefix(max(0, maxBodyChars - 12))) + "\n...(已截断)" : readableBody
        let body = [
            "发件人: \(sender)",
            "主题: \(subject)",
            "邮箱: \(mailbox)",
            "收信时间: \(receivedAt)",
            summary.isEmpty ? nil : "摘要: \(summary)",
            trimmedBody.isEmpty ? nil : "正文: \(trimmedBody)"
        ].compactMap { $0 }.joined(separator: "\n")
        return Signal(
            source: "apple_mail_app",
            sourceID: sourceID,
            title: "邮件: \(subject)",
            body: body,
            kind: "apple_mail_app_message",
            occurredAt: receivedAt,
            metadata: [
                "sender": sender,
                "subject": subject,
                "mailbox": mailbox,
                "received_at": receivedAt,
                "mail_app_surface": true,
                "body_read": bodyText != nil,
                "canonical_key": "apple_mail:\(sourceID)"
            ]
        )
    }
}

func mailSummaryRecords(_ value: Any) -> [[String: Any]] {
    if let records = value as? [[String: Any]] {
        return records
    }
    guard let object = value as? [String: Any] else {
        return []
    }
    for key in ["messages", "items", "records"] {
        if let records = object[key] as? [[String: Any]] {
            return records
        }
    }
    return [object]
}

func stringField(_ object: [String: Any], _ keys: [String]) -> String? {
    for key in keys {
        if let value = object[key] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
    }
    return nil
}

func flattenBookmarkNode(_ node: [String: Any], folderPath: [String]) -> [[String: Any]] {
    if node["type"] as? String == "url" {
        var item = node
        item["folder_path"] = folderPath.joined(separator: " / ")
        return [item]
    }
    guard let children = node["children"] as? [[String: Any]] else {
        return []
    }
    let name = (node["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let nextPath = name.isEmpty ? folderPath : folderPath + [name]
    return children.flatMap { flattenBookmarkNode($0, folderPath: nextPath) }
}

func chromeDate(_ value: Any?) -> Date {
    let raw: Int64
    if let string = value as? String, let parsed = Int64(string) {
        raw = parsed
    } else if let number = value as? NSNumber {
        raw = number.int64Value
    } else {
        raw = 0
    }
    // Chrome timestamps are microseconds since 1601-01-01 UTC.
    return Date(timeIntervalSince1970: Double(raw) / 1_000_000 - 11_644_473_600)
}

func acceptSource(_ config: AppConfig, name: String, limit: Int) throws -> [String: Any] {
    try ensureRuntime(config)
    let registry = try loadRuleRegistry(config.rulesFile)
    let signals = try collectSource(config, name: name, limit: limit)
    let items = signals.map { signal -> [String: Any] in
        let decision = decide(signal, registry)
        return [
            "source_id": signal.sourceID,
            "title": signal.title,
            "kind": signal.kind,
            "occurred_at": signal.occurredAt,
            "metadata": signal.metadata,
            "decision": encodableDictionary(decision)
        ]
    }
    let result: [String: Any] = [
        "status": "ok",
        "source": name,
        "collected_count": items.count,
        "review_count": items.filter { (($0["decision"] as? [String: Any])?["needsReview"] as? Bool) == true }.count,
        "items": items
    ]
    let reportPath = try writeSourceAcceptanceReport(config, payload: result)
    var output = result
    output["report_path"] = reportPath
    try appendAudit(config, ["type": "source_acceptance_previewed"].merging(output) { _, new in new })
    return output
}

func processSignal(_ config: AppConfig, state: StateStore, registry: RuleRegistry, signal: Signal, dryRun: Bool, noReminders: Bool) throws -> [String: Any] {
    let ingest = try state.ingest(signal)
    if !ingest.created {
        let result: [String: Any] = ["signal_id": ingest.id, "dedupe_key": signal.dedupeKey, "status": "duplicate", "action": "none"]
        try appendAudit(config, ["type": "duplicate_signal"].merging(result) { _, new in new })
        return result
    }
    let decision = decide(signal, registry)
    let decisionID = try state.recordDecision(signalID: ingest.id, decision: decision)
    let actionResult = try executeDecision(config, state: state, signal: signal, decision: decision, dryRun: dryRun, noReminders: noReminders)
    let actionID = try state.recordAction(decisionID: decisionID, result: actionResult)
    let result: [String: Any] = [
        "signal_id": ingest.id,
        "decision_id": decisionID,
        "action_id": actionID,
        "dedupe_key": signal.dedupeKey,
        "decision": encodableDictionary(decision),
        "action_result": actionResult.dictionary
    ]
    try appendAudit(config, ["type": "processed_signal"].merging(result) { _, new in new })
    return result
}

func executeDecision(_ config: AppConfig, state: StateStore, signal: Signal, decision: Decision, dryRun: Bool, noReminders: Bool) throws -> ActionResult {
    if dryRun {
        return ActionResult(action: decision.action, status: "dry_run", detail: "No external action executed.", externalID: nil)
    }
    if decision.action == "create_review_reminder", config.autoCreateReviewReminders, config.remindersEnabled, !noReminders {
        let canonicalKey = projectionCanonicalKey(signal)
        if let existing = try state.projection(for: canonicalKey) {
            return ActionResult(
                action: decision.action,
                status: "done",
                detail: "Existing EventKit projection reused for canonical work item.",
                externalID: projectionExternalID(existing)
            )
        }
        let listName = config.domainLists[decision.domain] ?? "WORK"
        var externalIDs: [String] = []
        let reminderID = try createReminder(listName: listName, signal: signal, decision: decision)
        externalIDs.append(reminderID)
        var calendarID: String?
        var details = ["Created Reminders item in \(listName) through EventKit."]
        if let eventID = try createCalendarEventIfScheduled(signal: signal, decision: decision) {
            externalIDs.append(eventID)
            calendarID = eventID
            details.append("Created Calendar time block through EventKit.")
        }
        try state.recordProjection(canonicalKey: canonicalKey, reminderExternalID: reminderID, calendarExternalID: calendarID)
        return ActionResult(action: decision.action, status: "done", detail: details.joined(separator: " "), externalID: externalIDs.joined(separator: " "))
    }
    if decision.action == "archive_low_value", config.autoArchiveLowValue {
        if signal.source == "apple_mail_app" {
            let externalID = try archiveAppleMailAppMessage(config, signal: signal)
            return ActionResult(action: decision.action, status: "done", detail: "Archived low-value Mail.app message through configured executor.", externalID: externalID)
        }
        return ActionResult(action: decision.action, status: "done", detail: "Low-value signal archived in audit log only.", externalID: nil)
    }
    return ActionResult(action: decision.action, status: "done", detail: "Recorded without user-visible action.", externalID: nil)
}

func archiveAppleMailAppMessage(_ config: AppConfig, signal: Signal) throws -> String {
    let sourceConfig = config.sourceConfig("apple_mail_app")
    guard let argv = sourceConfig["archive_argv"] as? [String], !argv.isEmpty else {
        throw AppError.runtime("apple_mail_app.archive_argv must define a Mail.app archive executor before archive_low_value can mutate Mail.app.")
    }
    let timeout = TimeInterval(sourceConfig["timeout_seconds"] as? Double ?? Double(sourceConfig["timeout_seconds"] as? Int ?? 20))
    let environment: [String: String] = [
        "SMART_SHADOW_MAIL_SOURCE_ID": signal.sourceID,
        "SMART_SHADOW_MAIL_SUBJECT": signal.metadata["subject"] as? String ?? "",
        "SMART_SHADOW_MAIL_SENDER": signal.metadata["sender"] as? String ?? "",
        "SMART_SHADOW_MAILBOX": signal.metadata["mailbox"] as? String ?? "",
        "SMART_SHADOW_ARCHIVE_LOG": (sourceConfig["archive_log"] as? String ?? "\(config.runtimeRoot)/logs/mail-archive.log")
    ]
    let output = try runExternalCommand(argv, timeout: timeout, environment: environment).trimmingCharacters(in: .whitespacesAndNewlines)
    return output.isEmpty ? "mail-app://\(signal.sourceID)" : output
}

func projectionCanonicalKey(_ signal: Signal) -> String {
    for key in ["canonical_key", "canonicalKey", "work_item_id", "workItemID"] {
        if let value = signal.metadata[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    return signal.dedupeKey
}

func canonicalKeyFromStoredSignal(dedupeKey: String, metadataJSON: String) -> String {
    guard let data = metadataJSON.data(using: .utf8),
          let metadata = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return dedupeKey
    }
    for key in ["canonical_key", "canonicalKey", "work_item_id", "workItemID"] {
        if let value = metadata[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    return dedupeKey
}

func projectionExternalID(_ record: ProjectionRecord) -> String {
    [record.reminderExternalID, record.calendarExternalID]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

func createReminder(listName: String, signal: Signal, decision: Decision) throws -> String {
    try requireEventKitAuthorization(for: .reminder, operation: "create Apple Reminders review card")
    let store = EKEventStore()
    let reminder = EKReminder(eventStore: store)
    reminder.title = signal.title
    reminder.notes = reminderBody(signal: signal, decision: decision)
    reminder.calendar = try findReminderCalendar(named: listName, store: store)
    reminder.priority = reminderPriority(decision.priority)
    if let due = signalMetadataDate(signal, keys: ["due_date", "dueDate"]) ?? reminderDueDate(decision.risk, decision.priority) {
        reminder.dueDateComponents = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: due)
    }
    try store.save(reminder, commit: true)
    return "x-apple-reminder://\(reminder.calendarItemIdentifier)"
}

func createCalendarEventIfScheduled(signal: Signal, decision: Decision) throws -> String? {
    guard let start = signalMetadataDate(signal, keys: ["calendar_start", "start", "start_at"]),
          let end = signalMetadataDate(signal, keys: ["calendar_end", "end", "end_at"]) ?? Calendar.current.date(byAdding: .minute, value: 30, to: start)
    else {
        return nil
    }
    try requireEventKitAuthorization(for: .event, operation: "create Apple Calendar time block")
    let store = EKEventStore()
    guard let calendar = store.defaultCalendarForNewEvents, calendar.allowsContentModifications else {
        throw AppError.runtime("No writable default Calendar found.")
    }
    let event = EKEvent(eventStore: store)
    event.title = signal.title
    event.notes = calendarNotes(signal: signal, decision: decision)
    event.startDate = start
    event.endDate = max(end, start.addingTimeInterval(60))
    event.calendar = calendar
    try store.save(event, span: .thisEvent, commit: true)
    return "x-apple-calendar://\(event.calendarItemIdentifier)"
}

func calendarNotes(signal: Signal, decision: Decision) -> String {
    let summary = signal.body.isEmpty ? "智能影子为该事项预留的时间块。" : signal.body
    return """
    \(summary)

    时间块用途：处理或审核该工作项。
    """
}

func signalMetadataDate(_ signal: Signal, keys: [String]) -> Date? {
    for key in keys {
        if let raw = signal.metadata[key] as? String, let date = parseDate(raw) {
            return date
        }
    }
    return nil
}

func parseDate(_ raw: String) -> Date? {
    let iso = ISO8601DateFormatter()
    if let date = iso.date(from: raw) {
        return date
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: raw)
}

func findReminderCalendar(named name: String, store: EKEventStore) throws -> EKCalendar {
    if let found = store.calendars(for: .reminder).first(where: { $0.title == name && $0.allowsContentModifications }) {
        return found
    }
    if let fallback = store.defaultCalendarForNewReminders(), fallback.allowsContentModifications {
        return fallback
    }
    throw AppError.runtime("No writable Reminder list found for \(name).")
}

func reminderBody(signal: Signal, decision: Decision) -> String {
    let summary = signal.body.isEmpty ? "请审核这个事项，并决定下一步是否需要智能影子继续处理。" : signal.body
    return """
    \(summary)

    建议动作：请根据当前上下文审核是否继续推进。
    """
}

func reminderPriority(_ priority: String) -> Int {
    switch priority {
    case "high": return 1
    case "normal": return 5
    case "low": return 9
    default: return 0
    }
}

func reminderDueDate(_ risk: String, _ priority: String) -> Date? {
    var components = DateComponents()
    components.day = (risk == "high" || priority == "high") ? 0 : 2
    return Calendar.current.date(byAdding: components, to: Date())
}

func loadSignal(_ path: String) throws -> Signal {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw AppError.runtime("Signal must be a JSON object: \(path)")
    }
    return Signal(
        source: raw["source"] as? String ?? "file",
        sourceID: raw["source_id"] as? String ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
        title: raw["title"] as? String ?? "(untitled signal)",
        body: raw["body"] as? String ?? "",
        kind: raw["kind"] as? String ?? "generic",
        occurredAt: raw["occurred_at"] as? String ?? nowISO(),
        metadata: raw["metadata"] as? [String: Any] ?? [:]
    )
}

func quarantine(_ config: AppConfig, path: String, folder: String) throws {
    let targetDir = "\(config.runtimeRoot)/inbox/\(folder)"
    try FileManager.default.createDirectory(atPath: targetDir, withIntermediateDirectories: true)
    var target = "\(targetDir)/\(URL(fileURLWithPath: path).lastPathComponent)"
    if FileManager.default.fileExists(atPath: target) {
        target = "\(targetDir)/\(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)-\(Int(Date().timeIntervalSince1970)).json"
    }
    try FileManager.default.moveItem(atPath: path, toPath: target)
}

func writeUserReport(_ config: AppConfig, items: [[String: Any]]) throws -> String {
    try ensureRuntime(config)
    let path = "\(config.reports)/user-report-\(nowISO().replacingOccurrences(of: ":", with: "")).md"
    var lines = ["# 智能影子汇报", "", "生成时间：\(nowISO())", "", "## 规则反馈"]
    let feedback = try listRuleFeedback(config, limit: 5)
    if feedback.isEmpty {
        lines.append("- 无")
    } else {
        for item in feedback {
            let evidence = item["evidence"] is NSNull ? "" : "｜证据：\(item["evidence"] ?? "")"
            lines.append("- \(item["rule_id"] ?? "")｜\(feedbackOutcomeLabel(String(describing: item["outcome"] ?? "")))｜\(item["note"] ?? "")\(evidence)")
        }
    }
    lines.append(contentsOf: ["", "## 已记录事项"])
    if items.isEmpty {
        lines.append("- 暂无事项。")
    } else {
        for item in items {
            lines.append("- \(item["title"] ?? "")｜\(item["domain"] ?? "")｜\(item["priority"] ?? "")｜\(item["risk"] ?? "")｜\(item["detail"] ?? "")")
        }
    }
    try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    return path
}

func writeSourceAcceptanceReport(_ config: AppConfig, payload: [String: Any]) throws -> String {
    try ensureRuntime(config)
    let source = String(describing: payload["source"] ?? "unknown").replacingOccurrences(of: "/", with: "-")
    let path = "\(config.reports)/source-acceptance-\(source)-\(nowISO().replacingOccurrences(of: ":", with: "")).md"
    let items = payload["items"] as? [[String: Any]] ?? []
    var lines = [
        "# 感知源验收报告",
        "",
        "生成时间：\(nowISO())",
        "感知源：\(payload["source"] ?? "")",
        "状态：\(payload["status"] ?? "")",
        "采集数量：\(payload["collected_count"] ?? 0)",
        "需审核数量：\(payload["review_count"] ?? 0)",
        "",
        "## 决策预览"
    ]
    if items.isEmpty {
        lines.append("- 无")
    } else {
        for item in items.prefix(20) {
            let decision = item["decision"] as? [String: Any] ?? [:]
            let review = (decision["needsReview"] as? Bool == true) ? "需审核" : "后台记录"
            lines.append("- \(item["title"] ?? "")｜\(decision["domain"] ?? "")/\(decision["priority"] ?? "")/\(decision["risk"] ?? "")｜\(review)｜\(decision["action"] ?? "")")
        }
    }
    lines.append(contentsOf: [
        "",
        "## 安全边界",
        "- 本验收只采集指定来源并预览规则决策，不写入 SQLite 信号/决策/动作表。",
        "- 本验收不创建 Apple Reminders 或 Apple Calendar 项，不发送外部消息，不移动或删除文件。",
        "- file_metadata 只读取文件名、路径、大小和修改时间；文件内容默认未读取。",
        "- lark_daily_context 只运行配置中的本机只读命令并保存 compact 摘要；本项目不保存飞书凭证。",
        "- chrome_bookmarks 只读取 Chrome 书签元数据；网页内容、历史记录、Cookies 和登录态默认未读取。",
        "- apple_mail_summary 读取配置指定的本地邮件摘要 JSON，用于离线回放和规则验收。",
        "- apple_mail_app 通过配置的 Mail.app 读取器采集真实邮件；本验收不写 Mail.app，正式运行可按配置执行低风险动作。",
        "- 启用后台感知仍需单独修改配置并重新验收。",
        ""
    ])
    try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    return path
}

let validRuleFeedbackOutcomes: Set<String> = ["accepted", "adjusted", "retired", "rejected"]

func ruleFeedbackPath(_ config: AppConfig) -> String {
    "\(config.runtimeRoot)/rule-feedback.jsonl"
}

func recordRuleFeedbackCommand(_ config: AppConfig, arguments: [String]) throws -> [String: Any] {
    guard arguments.count >= 2 else {
        throw AppError.usage("record-rule-feedback requires RULE_ID and outcome.")
    }
    let ruleID = arguments[0].trimmingCharacters(in: .whitespacesAndNewlines)
    let outcome = arguments[1]
    guard !ruleID.isEmpty else { throw AppError.usage("rule_id is required.") }
    guard validRuleFeedbackOutcomes.contains(outcome) else { throw AppError.usage("Invalid rule feedback outcome: \(outcome)") }
    guard let note = optionValue(arguments, "--note")?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else {
        throw AppError.usage("record-rule-feedback requires --note TEXT.")
    }
    let entry: [String: Any] = [
        "timestamp": nowISO(),
        "rule_id": ruleID,
        "outcome": outcome,
        "source": optionValue(arguments, "--source") ?? "manual",
        "note": note,
        "evidence": optionValue(arguments, "--evidence") ?? NSNull()
    ]
    try appendJSONLine(entry, to: ruleFeedbackPath(config))
    return entry
}

func listRuleFeedback(_ config: AppConfig, limit: Int) throws -> [[String: Any]] {
    let path = ruleFeedbackPath(config)
    guard FileManager.default.fileExists(atPath: path) else { return [] }
    let raw = try String(contentsOfFile: path, encoding: .utf8)
    var rows: [[String: Any]] = []
    for line in raw.split(separator: "\n") {
        guard let data = String(line).data(using: .utf8),
              let row = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { continue }
        rows.append(row)
    }
    return Array(rows.suffix(limit).reversed())
}

func summarizeRuleFeedback(_ config: AppConfig, limit: Int) throws -> [String: Any] {
    let rows = try listRuleFeedback(config, limit: limit)
    var outcomes = Dictionary(uniqueKeysWithValues: validRuleFeedbackOutcomes.sorted().map { ($0, 0) })
    for row in rows {
        let outcome = String(describing: row["outcome"] ?? "")
        outcomes[outcome, default: 0] += 1
    }
    return [
        "status": "ok",
        "ledger": ruleFeedbackPath(config),
        "count": rows.count,
        "outcomes": outcomes,
        "recent": Array(rows.prefix(10))
    ]
}

func feedbackOutcomeLabel(_ outcome: String) -> String {
    switch outcome {
    case "accepted": return "接受"
    case "adjusted": return "调整"
    case "retired": return "废弃"
    case "rejected": return "拒绝"
    default: return outcome
    }
}

func appendJSONLine(_ value: [String: Any], to path: String) throws {
    try FileManager.default.createDirectory(atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path, withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    let line = Data((String(data: data, encoding: .utf8)! + "\n").utf8)
    if !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path, contents: nil)
    }
    let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: line)
}

func appendAudit(_ config: AppConfig, _ event: [String: Any]) throws {
    try FileManager.default.createDirectory(atPath: URL(fileURLWithPath: config.auditLog).deletingLastPathComponent().path, withIntermediateDirectories: true)
    var payload = event
    payload["timestamp"] = nowISO()
    try appendJSONLine(payload, to: config.auditLog)
}

final class StateStore {
    private var db: OpaquePointer?

    init(path: String) throws {
        try FileManager.default.createDirectory(atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path, withIntermediateDirectories: true)
        guard sqlite3_open(path, &db) == SQLITE_OK else { throw AppError.runtime("Unable to open SQLite database.") }
        try exec(Self.schema)
    }

    func close() {
        sqlite3_close(db)
        db = nil
    }

    static let schema = """
    create table if not exists signals (
      id integer primary key autoincrement,
      dedupe_key text not null unique,
      source text not null,
      source_id text not null,
      title text not null,
      body text not null,
      kind text not null,
      occurred_at text not null,
      metadata_json text not null,
      ingested_at text not null
    );
    create table if not exists decisions (
      id integer primary key autoincrement,
      signal_id integer not null,
      domain text not null,
      priority text not null,
      risk text not null,
      needs_review integer not null,
      action text not null,
      reason text not null,
      confidence text not null,
      decided_at text not null
    );
    create table if not exists actions (
      id integer primary key autoincrement,
      decision_id integer not null,
      action text not null,
      status text not null,
      detail text not null,
      external_id text,
      acted_at text not null
    );
    create table if not exists executions (
      id integer primary key autoincrement,
      decision_id integer not null,
      external_id text not null,
      executor text not null,
      status text not null,
      detail text not null,
      artifact_path text,
      executed_at text not null,
      unique(decision_id, executor)
    );
    create table if not exists projections (
      id integer primary key autoincrement,
      canonical_key text not null unique,
      reminder_external_id text,
      calendar_external_id text,
      created_at text not null,
      updated_at text not null
    );
    """

    func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "unknown SQLite error"
            sqlite3_free(error)
            throw AppError.runtime(message)
        }
    }

    func ingest(_ signal: Signal) throws -> (id: Int64, created: Bool) {
        if let existing = try queryOne("select id from signals where dedupe_key=?", [signal.dedupeKey]) {
            return (existing["id"] as? Int64 ?? 0, false)
        }
        let metadata = String(data: try JSONSerialization.data(withJSONObject: signal.metadata, options: [.sortedKeys]), encoding: .utf8) ?? "{}"
        try execPrepared(
            """
            insert into signals (dedupe_key, source, source_id, title, body, kind, occurred_at, metadata_json, ingested_at)
            values (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [signal.dedupeKey, signal.source, signal.sourceID, signal.title, signal.body, signal.kind, signal.occurredAt, metadata, nowISO()]
        )
        return (sqlite3_last_insert_rowid(db), true)
    }

    func recordDecision(signalID: Int64, decision: Decision) throws -> Int64 {
        try execPrepared(
            """
            insert into decisions (signal_id, domain, priority, risk, needs_review, action, reason, confidence, decided_at)
            values (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [signalID, decision.domain, decision.priority, decision.risk, decision.needsReview ? 1 : 0, decision.action, decision.reason, decision.confidence, nowISO()]
        )
        return sqlite3_last_insert_rowid(db)
    }

    func recordAction(decisionID: Int64, result: ActionResult) throws -> Int64 {
        if let existing = try queryOne("select id from actions where decision_id=? order by id limit 1", [decisionID]) {
            return existing["id"] as? Int64 ?? 0
        }
        try execPrepared(
            "insert into actions (decision_id, action, status, detail, external_id, acted_at) values (?, ?, ?, ?, ?, ?)",
            [decisionID, result.action, result.status, result.detail, result.externalID ?? NSNull(), nowISO()]
        )
        return sqlite3_last_insert_rowid(db)
    }

    func counts() throws -> [String: Int64] {
        [
            "signals": try scalar("select count(*) from signals"),
            "decisions": try scalar("select count(*) from decisions"),
            "actions": try scalar("select count(*) from actions"),
            "executions": try scalar("select count(*) from executions"),
            "projections": try scalar("select count(*) from projections"),
            "pending_actions": try scalar("select count(*) from decisions d left join actions a on a.decision_id=d.id where a.id is null")
        ]
    }

    func projection(for canonicalKey: String) throws -> ProjectionRecord? {
        guard let row = try queryOne("select canonical_key, reminder_external_id, calendar_external_id from projections where canonical_key=?", [canonicalKey]) else {
            return nil
        }
        return ProjectionRecord(
            canonicalKey: row["canonical_key"] as? String ?? canonicalKey,
            reminderExternalID: row["reminder_external_id"] as? String,
            calendarExternalID: row["calendar_external_id"] as? String
        )
    }

    func recordProjection(canonicalKey: String, reminderExternalID: String?, calendarExternalID: String?) throws {
        try execPrepared(
            """
            insert into projections (canonical_key, reminder_external_id, calendar_external_id, created_at, updated_at)
            values (?, ?, ?, ?, ?)
            on conflict(canonical_key) do update set
              reminder_external_id=coalesce(excluded.reminder_external_id, projections.reminder_external_id),
              calendar_external_id=coalesce(excluded.calendar_external_id, projections.calendar_external_id),
              updated_at=excluded.updated_at
            """,
            [canonicalKey, reminderExternalID ?? NSNull(), calendarExternalID ?? NSNull(), nowISO(), nowISO()]
        )
    }

    func projections(limit: Int) throws -> [[String: Any]] {
        try query(
            """
            select canonical_key, reminder_external_id, calendar_external_id, created_at, updated_at
            from projections
            order by updated_at desc, id desc
            limit ?
            """,
            [limit]
        )
    }

    func rebuildProjectionsFromActions() throws -> [String: Any] {
        let rows = try query(
            """
            select s.dedupe_key, s.metadata_json, a.external_id
            from actions a
            join decisions d on d.id=a.decision_id
            join signals s on s.id=d.signal_id
            where a.external_id is not null and a.external_id <> ''
            order by a.id
            """,
            []
        )
        var rebuilt = 0
        for row in rows {
            let externalID = row["external_id"] as? String ?? ""
            let canonicalKey = canonicalKeyFromStoredSignal(dedupeKey: row["dedupe_key"] as? String ?? "", metadataJSON: row["metadata_json"] as? String ?? "{}")
            let reminderID = externalID.split(separator: " ").map(String.init).first { $0.hasPrefix("x-apple-reminder://") }
            let calendarID = externalID.split(separator: " ").map(String.init).first { $0.hasPrefix("x-apple-calendar://") }
            if reminderID != nil || calendarID != nil {
                try recordProjection(canonicalKey: canonicalKey, reminderExternalID: reminderID, calendarExternalID: calendarID)
                rebuilt += 1
            }
        }
        return ["status": "ok", "scanned": rows.count, "rebuilt": rebuilt]
    }

    func recent(limit: Int) throws -> [[String: Any]] {
        try query("select s.id as signal_id, s.title, d.domain, d.priority, d.risk, d.action as decision_action, a.status, a.detail, a.external_id from signals s left join decisions d on d.signal_id=s.id left join actions a on a.id=(select max(id) from actions where decision_id=d.id) order by s.id desc limit ?", [limit])
    }

    func reviewQueue(limit: Int) throws -> [[String: Any]] {
        try query("select s.id as signal_id, s.title, s.source, s.source_id, s.body, d.domain, d.priority, d.risk, d.reason, a.status, a.detail, a.external_id from decisions d join signals s on s.id=d.signal_id left join actions a on a.id=(select max(id) from actions where decision_id=d.id) where d.needs_review=1 order by d.id desc limit ?", [limit])
    }

    func reportItems(limit: Int) throws -> [[String: Any]] {
        try query("select s.id as signal_id, s.title, s.source, s.body, d.domain, d.priority, d.risk, d.needs_review, d.action as decision_action, d.reason, a.status, a.detail, a.external_id from signals s left join decisions d on d.signal_id=s.id left join actions a on a.id=(select max(id) from actions where decision_id=d.id) order by s.id desc limit ?", [limit])
    }

    func scalar(_ sql: String) throws -> Int64 {
        let row = try queryOne(sql, []) ?? [:]
        return row.values.first as? Int64 ?? 0
    }

    func queryOne(_ sql: String, _ values: [Any]) throws -> [String: Any]? {
        try query(sql, values).first
    }

    func query(_ sql: String, _ values: [Any]) throws -> [[String: Any]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw AppError.runtime(sqliteError()) }
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        var rows: [[String: Any]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: Any] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER:
                    row[name] = sqlite3_column_int64(statement, index)
                case SQLITE_TEXT:
                    row[name] = String(cString: sqlite3_column_text(statement, index))
                case SQLITE_NULL:
                    row[name] = NSNull()
                default:
                    row[name] = String(cString: sqlite3_column_text(statement, index))
                }
            }
            rows.append(row)
        }
        return rows
    }

    func execPrepared(_ sql: String, _ values: [Any]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw AppError.runtime(sqliteError()) }
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw AppError.runtime(sqliteError()) }
    }

    func bind(_ values: [Any], to statement: OpaquePointer?) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            if value is NSNull {
                sqlite3_bind_null(statement, index)
            } else if let value = value as? Int64 {
                sqlite3_bind_int64(statement, index, value)
            } else if let value = value as? Int {
                sqlite3_bind_int64(statement, index, Int64(value))
            } else if let value = value as? Bool {
                sqlite3_bind_int(statement, index, value ? 1 : 0)
            } else {
                sqlite3_bind_text(statement, index, String(describing: value), -1, SQLITE_TRANSIENT)
            }
        }
    }

    func sqliteError() -> String {
        db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown SQLite error"
    }
}

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension ActionResult {
    var dictionary: [String: Any] {
        ["action": action, "status": status, "detail": detail, "external_id": externalID ?? NSNull()]
    }
}

func eventKitStatus() -> [String: String] {
    [
        "calendar": authorizationDescription(EKEventStore.authorizationStatus(for: .event)),
        "reminders": authorizationDescription(EKEventStore.authorizationStatus(for: .reminder)),
        "mode": "swift-native-eventkit"
    ]
}

func requestEventKitAccess(target: String) throws -> [String: Any] {
    guard ["calendar", "reminders", "all"].contains(target) else {
        throw AppError.usage("eventkit-request-access expects calendar, reminders, or all.")
    }
    let store = EKEventStore()
    var results: [String: Any] = ["status": "ok", "requested": target]
    if target == "calendar" || target == "all" {
        results["calendar"] = try requestEventKitAccess(store: store, entityType: .event)
    }
    if target == "reminders" || target == "all" {
        results["reminders"] = try requestEventKitAccess(store: store, entityType: .reminder)
    }
    results["current_status"] = eventKitStatus()
    return results
}

func requestEventKitAccess(store: EKEventStore, entityType: EKEntityType) throws -> [String: Any] {
    let before = EKEventStore.authorizationStatus(for: entityType)
    if isEventKitAuthorized(before, for: entityType) {
        return ["status": "already_authorized", "before": authorizationDescription(before), "after": authorizationDescription(before)]
    }

    let semaphore = DispatchSemaphore(value: 0)
    let result = EventKitRequestResult()
    if entityType == .event {
        store.requestFullAccessToEvents { ok, error in
            result.complete(granted: ok, error: error)
            semaphore.signal()
        }
    } else {
        store.requestFullAccessToReminders { ok, error in
            result.complete(granted: ok, error: error)
            semaphore.signal()
        }
    }
    semaphore.wait()
    if let requestError = result.error {
        throw AppError.runtime("EventKit access request failed: \(requestError.localizedDescription)")
    }
    let after = EKEventStore.authorizationStatus(for: entityType)
    return [
        "status": result.granted ? "granted" : "not_granted",
        "before": authorizationDescription(before),
        "after": authorizationDescription(after)
    ]
}

func requireEventKitAuthorization(for entityType: EKEntityType, operation: String) throws {
    let status = EKEventStore.authorizationStatus(for: entityType)
    guard isEventKitAuthorized(status, for: entityType) else {
        let scope = entityType == .event ? "calendar" : "reminders"
        throw AppError.runtime("EventKit \(scope) access is \(authorizationDescription(status)); run `bin/smart-shadow eventkit-request-access \(scope)` in the foreground before \(operation).")
    }
}

func isEventKitAuthorized(_ status: EKAuthorizationStatus, for entityType: EKEntityType) -> Bool {
    switch status {
    case .fullAccess, .authorized:
        return true
    case .writeOnly:
        return entityType == .event
    default:
        return false
    }
}

func authorizationDescription(_ status: EKAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "not_determined"
    case .restricted: return "restricted"
    case .denied: return "denied"
    case .authorized: return "authorized_legacy"
    case .fullAccess: return "full_access"
    case .writeOnly: return "write_only"
    @unknown default: return "unknown"
    }
}

func listCalendarsAndReminderLists() throws {
    let store = EKEventStore()
    printJSON([
        "calendar_authorization": authorizationDescription(EKEventStore.authorizationStatus(for: .event)),
        "reminders_authorization": authorizationDescription(EKEventStore.authorizationStatus(for: .reminder)),
        "event_calendars": describeCalendars(store.calendars(for: .event)),
        "reminder_lists": describeCalendars(store.calendars(for: .reminder)),
        "default_event_calendar": describeCalendar(store.defaultCalendarForNewEvents) ?? NSNull(),
        "default_reminder_list": describeCalendar(store.defaultCalendarForNewReminders()) ?? NSNull()
    ] as [String: Any])
}

func describeCalendars(_ calendars: [EKCalendar]) -> [[String: Any]] {
    calendars.map { describeCalendar($0) ?? [:] }
}

func describeCalendar(_ calendar: EKCalendar?) -> [String: Any]? {
    guard let calendar else { return nil }
    return [
        "title": calendar.title,
        "identifier": calendar.calendarIdentifier,
        "allows_content_modifications": calendar.allowsContentModifications,
        "type": calendar.type.rawValue,
        "source": calendar.source.title
    ]
}

func parseProjectionInput(_ arguments: [String]) throws -> ProjectionInput {
    var input = ProjectionInput()
    var index = 0
    while index < arguments.count {
        let key = arguments[index]
        guard key.hasPrefix("--"), index + 1 < arguments.count else { throw AppError.usage("Bad option: \(key)") }
        let value = arguments[index + 1]
        switch key {
        case "--title": input.title = value
        case "--domain": input.domain = value
        case "--due": input.due = value
        case "--start": input.start = value
        case "--end": input.end = value
        case "--priority": input.priority = value
        case "--flagged": input.flagged = parseBool(value)
        case "--review": input.review = parseBool(value)
        case "--notes": input.notes = value
        default: throw AppError.usage("Unknown option: \(key)")
        }
        index += 2
    }
    return input
}

func planProjection(_ input: ProjectionInput) -> [String: Any] {
    let hasTimeBlock = input.start != nil || input.end != nil
    let hasDueOnly = input.due != nil && !hasTimeBlock
    var rationale: [String] = []
    var payload: [String: Any] = ["title": input.title]
    if input.review || hasDueOnly {
        rationale.append("Reminders carries the completable action, review state, priority, due date, and flag intent when an official API supports it.")
        payload["reminder"] = ["title": input.title, "listDomain": input.domain, "dueDate": jsonValue(input.due), "priority": input.priority, "flagged": input.flagged, "notes": input.notes]
    }
    if hasTimeBlock {
        rationale.append("Calendar carries the scheduled time block and user-visible time occupancy.")
        payload["calendar"] = ["title": input.title, "calendarDomain": input.domain, "start": jsonValue(input.start), "end": jsonValue(input.end), "allDay": false, "notes": input.notes]
    } else if hasDueOnly && input.priority == "high" {
        rationale.append("Calendar may carry a high-priority deadline as an all-day milestone.")
        payload["calendar"] = ["title": input.title, "calendarDomain": input.domain, "start": jsonValue(input.due), "end": jsonValue(input.due), "allDay": true, "notes": input.notes]
    }
    payload["dedupeKey"] = "\(input.domain):\(input.title.lowercased()):\(input.due ?? ""):\(input.start ?? "")"
    payload["rationale"] = rationale
    return payload
}

func launchdPlist(executable: String, configPath: String, projectRoot: String) -> String {
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key>
      <string>\(launchdLabel)</string>
      <key>ProgramArguments</key>
      <array>
        <string>\(executable)</string>
        <string>--config</string>
        <string>\(configPath)</string>
        <string>daemon</string>
      </array>
      <key>WorkingDirectory</key>
      <string>\(projectRoot)</string>
      <key>KeepAlive</key>
      <true/>
      <key>RunAtLoad</key>
      <true/>
      <key>WatchPaths</key>
      <array>
        <string>\(projectRoot)/var/inbox/events</string>
      </array>
      <key>StandardOutPath</key>
      <string>\(projectRoot)/var/logs/launchd.out.log</string>
      <key>StandardErrorPath</key>
      <string>\(projectRoot)/var/logs/launchd.err.log</string>
    </dict>
    </plist>
    """
}

func executablePath() throws -> String {
    let path = CommandLine.arguments[0]
    if path.hasPrefix("/") { return path }
    return "\(FileManager.default.currentDirectoryPath)/\(path)"
}

func shellOutput(_ args: [String]) throws -> String {
    try shellResult(args).output
}

func shellResult(_ args: [String]) throws -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = args
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    process.waitUntilExit()
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (process.terminationStatus, output)
}

func firstLine(_ text: String) -> String {
    text.components(separatedBy: .newlines).first ?? text
}

func optionValue(_ args: [String], _ option: String) -> String? {
    guard let index = args.firstIndex(of: option), index + 1 < args.count else { return nil }
    return args[index + 1]
}

func parseBool(_ value: String) -> Bool {
    ["1", "true", "yes", "y"].contains(value.lowercased())
}

func jsonValue(_ value: String?) -> Any {
    value ?? NSNull()
}

func encodableDictionary<T: Encodable>(_ value: T) -> [String: Any] {
    let data = try! JSONEncoder().encode(value)
    return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
}

func printJSON(_ value: Any) {
    let data = try! JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    print(String(data: data, encoding: .utf8)!)
}

func writeJSON(_ value: Any, to path: String) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: URL(fileURLWithPath: path))
}

func writeJSONObject(_ value: Any, to path: String) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    var text = String(data: data, encoding: .utf8) ?? "{}"
    text.append("\n")
    try text.write(toFile: path, atomically: true, encoding: .utf8)
}

extension FileManager {
    func copyItemReplacingIfNeeded(atPath source: String, toPath target: String) throws {
        if fileExists(atPath: target) {
            try removeItem(atPath: target)
        }
        try copyItem(atPath: source, toPath: target)
    }
}
