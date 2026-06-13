import Contacts
import EventKit
import Foundation
import CryptoKit
import Security
import SQLite3
import SmartShadowShared

let launchdLabel = "me.longbiaochen.smart-shadow"
let launchdTarget = "\(NSHomeDirectory())/Library/LaunchAgents/\(launchdLabel).plist"
let configurableSources = ["file_metadata", "lark_daily_context", "lark_calendar_events", "lark_tasks", "google_calendar_events", "google_tasks", "google_contacts", "chrome_bookmarks", "apple_reminders_inbox", "apple_mail_summary"]
let larkStructuredSources = Set(["lark_calendar_events", "lark_tasks"])
let googleSyncSources = Set(["google_calendar_events", "google_tasks", "google_contacts"])
let sharedEventStoreBox = EventKitStoreBox()
let sharedContactStoreBox = ContactStoreBox()
let googleKeychainService = "me.longbiaochen.smart-shadow.google-oauth"

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
    let projectionTarget: String?

    enum CodingKeys: String, CodingKey {
        case domain
        case priority
        case risk
        case needsReview
        case action
        case reason
        case confidence
        case projectionTarget = "projection_target"
    }

    init(
        domain: String,
        priority: String,
        risk: String,
        needsReview: Bool,
        action: String,
        reason: String,
        confidence: String,
        projectionTarget: String? = nil
    ) {
        self.domain = domain
        self.priority = priority
        self.risk = risk
        self.needsReview = needsReview
        self.action = action
        self.reason = reason
        self.confidence = confidence
        self.projectionTarget = projectionTarget
    }
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
    let larkTaskGUID: String?
    let larkTaskURL: String?
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
    let calendarDomainCalendars: [String: String]
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

final class EventKitStoreBox: @unchecked Sendable {
    let store = EKEventStore()
}

final class ContactStoreBox: @unchecked Sendable {
    let store = CNContactStore()
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
struct ShadowD {
    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch {
            fputs("shadowd: \(error)\n", stderr)
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
    case "reminders-plan-quadrants":
        let config = try loadConfig(configPath)
        printJSON(try remindersPlanQuadrants(config: config, arguments: rest))
    case "reminders-db-doctor":
        printJSON(try remindersDBDoctor(arguments: rest))
    case "contacts-status":
        printJSON(contactsStatus())
    case "contacts-request-access", "request-contacts-access":
        printJSON(try requestContactsAccess())
    case "google-auth":
        let config = try loadConfig(configPath)
        let subcommand = rest.first ?? "status"
        printJSON(try googleAuthCommand(config, subcommand: subcommand, arguments: Array(rest.dropFirst())))
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
    case "project-mail-decision":
        let config = try loadConfig(configPath)
        let input = optionValue(rest, "--input") ?? ""
        let dryRun = rest.contains("--dry-run")
        let noReminders = rest.contains("--no-reminders")
        printJSON(try projectMailDecision(config, inputPath: input, dryRun: dryRun, noReminders: noReminders))
    case "once", "run", "github-issue", "inspect-issue":
        let config = try loadConfig(configPath)
        try ensureRuntime(config)
        printJSON(try handleShadowDCommand(config, arguments: arguments))
    case "shadowd":
        let config = try loadConfig(configPath)
        try ensureRuntime(config)
        printJSON(try handleShadowDCommand(config, arguments: rest))
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
            do {
                let daemonNoReminders = !isEventKitAuthorized(EKEventStore.authorizationStatus(for: .reminder), for: .reminder)
                _ = try runOnce(config, dryRun: false, noReminders: daemonNoReminders)
            } catch {
                try? writeDaemonErrorReport(config, error: error)
                try? appendAudit(config, ["type": "daemon_run_error", "error": "\(error)"])
                fputs("smart-shadow: daemon run failed: \(error)\n", stderr)
            }
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
    smart-shadow [--config PATH] accept-source file_metadata|lark_daily_context|lark_calendar_events|lark_tasks|google_calendar_events|google_tasks|google_contacts|chrome_bookmarks|apple_reminders_inbox|apple_mail_summary [--limit N]
    smart-shadow [--config PATH] sources
    smart-shadow [--config PATH] source-doctor
    smart-shadow [--config PATH] service-status
    smart-shadow [--config PATH] enable-source file_metadata|lark_daily_context|lark_calendar_events|lark_tasks|google_calendar_events|google_tasks|google_contacts|chrome_bookmarks|apple_reminders_inbox|apple_mail_summary [--force]
    smart-shadow [--config PATH] disable-source file_metadata|lark_daily_context|lark_calendar_events|lark_tasks|google_calendar_events|google_tasks|google_contacts|chrome_bookmarks|apple_reminders_inbox|apple_mail_summary
    smart-shadow [--config PATH] daemon
    smart-shadow [--config PATH] health
    smart-shadow [--config PATH] reviews [--limit N]
    smart-shadow [--config PATH] rebuild-projections
    smart-shadow [--config PATH] report [--limit N]
    smart-shadow [--config PATH] rule-feedback [--limit N]
    smart-shadow [--config PATH] record-rule-feedback RULE_ID accepted|adjusted|retired|rejected --note TEXT [--evidence PATH] [--source TEXT]
    smart-shadow [--config PATH] rules
    smart-shadow [--config PATH] validate-rules
    smart-shadow [--config PATH] project-mail-decision --input PATH [--dry-run] [--no-reminders]
    shadowd [--config PATH] once|run|inspect-issue [--dry-run] [--fixture PATH]
    shadowd [--config PATH] github-issue --payload PATH --event issues|issue_comment [--dry-run] [--write]
    smart-shadow [--config PATH] sample-event [--sample PATH]
    smart-shadow [--config PATH] google-auth login|status|logout
    smart-shadow eventkit-status
    smart-shadow eventkit-request-access [calendar|reminders|all]
    smart-shadow eventkit-list
    smart-shadow [--config PATH] reminders-plan-quadrants --dry-run
    smart-shadow reminders-db-doctor [--store-root PATH]
    smart-shadow contacts-status
    smart-shadow contacts-request-access
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
    let calendars = raw["calendars"] as? [String: Any] ?? [:]
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
        calendarDomainCalendars: calendars["domain_calendars"] as? [String: String] ?? [:],
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

let reminderQuadrants = ["IMPORTANT", "URGENT", "DOING", "TODO"]

func remindersPlanQuadrants(config: AppConfig, arguments: [String]) throws -> [String: Any] {
    guard arguments.contains("--dry-run") else {
        throw AppError.usage("reminders-plan-quadrants is read-only and requires --dry-run.")
    }
    try requireEventKitAuthorization(for: .reminder, operation: "reminders-plan-quadrants")
    let store = sharedEventStoreBox.store
    let configuredDomains = ["money", "health", "relationship", "work"]
    let configuredLists = configuredDomains.map { domain in
        (domain: domain, listName: config.domainLists[domain] ?? domain.uppercased())
    }
    let calendars = store.calendars(for: .reminder)
    var outputLists: [[String: Any]] = []
    var warnings: [String] = [
        "This command does not create, rename, or move Reminders sections.",
        "Quadrants are suggestions derived only from public EventKit fields."
    ]
    for configured in configuredLists {
        guard let calendar = calendars.first(where: { $0.title == configured.listName }) else {
            warnings.append("Reminder list not found: \(configured.listName)")
            outputLists.append([
                "domain": configured.domain,
                "list": configured.listName,
                "found": false,
                "item_count": 0,
                "counts": Dictionary(uniqueKeysWithValues: reminderQuadrants.map { ($0, 0) }),
                "items": []
            ])
            continue
        }
        let reminders = try fetchIncompleteReminders(store: store, calendars: [calendar])
        let planned = reminders.map { reminderQuadrantPlan($0, listName: configured.listName, domain: configured.domain) }
        var counts = Dictionary(uniqueKeysWithValues: reminderQuadrants.map { ($0, 0) })
        for item in planned {
            let quadrant = item["quadrant"] as? String ?? "TODO"
            counts[quadrant, default: 0] += 1
        }
        outputLists.append([
            "domain": configured.domain,
            "list": configured.listName,
            "found": true,
            "item_count": planned.count,
            "counts": counts,
            "items": planned
        ])
    }
    return [
        "status": "ok",
        "mode": "dry_run",
        "generated_at": nowISO(),
        "policy": [
            "lists": "life_domains",
            "sections": reminderQuadrants,
            "section_write_path": "Reminders App UI or supervised Accessibility only",
            "eventkit_mutates_sections": false
        ],
        "lists": outputLists,
        "warnings": warnings
    ] as [String: Any]
}

func fetchIncompleteReminders(store: EKEventStore, calendars: [EKCalendar]) throws -> [EKReminder] {
    let fetch = ReminderFetchResult()
    let semaphore = DispatchSemaphore(value: 0)
    let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
    store.fetchReminders(matching: predicate) { reminders in
        fetch.complete(reminders: reminders, error: nil)
        semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + 30) == .success else {
        throw AppError.runtime("Timed out fetching Reminders through EventKit.")
    }
    if let error = fetch.error {
        throw AppError.runtime("Failed to fetch Reminders through EventKit: \(error.localizedDescription)")
    }
    return fetch.reminders.sorted {
        let leftDate = reminderPlanningDate($0) ?? .distantFuture
        let rightDate = reminderPlanningDate($1) ?? .distantFuture
        if leftDate != rightDate { return leftDate < rightDate }
        return ($0.title ?? "") < ($1.title ?? "")
    }
}

func reminderQuadrantPlan(_ reminder: EKReminder, listName: String, domain: String) -> [String: Any] {
    let now = Date()
    let due = reminder.dueDateComponents?.date
    let remind = reminder.alarms?.compactMap { $0.absoluteDate }.sorted().first
    let planningDate = [due, remind].compactMap { $0 }.min()
    let priority = reminder.priority
    var quadrant = "TODO"
    var confidence = "low"
    var reasons: [String] = []
    if let planningDate, planningDate <= endOfToday(from: now) {
        quadrant = "URGENT"
        confidence = planningDate <= now ? "high" : "medium"
        reasons.append(planningDate <= now ? "due_or_reminder_elapsed" : "due_or_reminder_today")
    } else if (1...4).contains(priority) {
        quadrant = "IMPORTANT"
        confidence = "medium"
        reasons.append("high_priority")
    } else if priority == 5 {
        quadrant = "DOING"
        confidence = "low"
        reasons.append("medium_priority")
    } else {
        reasons.append("default_backlog")
    }
    return [
        "domain": domain,
        "list": listName,
        "external_id": "x-apple-reminder://\(reminder.calendarItemIdentifier)",
        "title": reminder.title ?? "",
        "priority": priority,
        "due": due.map(isoString) ?? NSNull(),
        "remind": remind.map(isoString) ?? NSNull(),
        "quadrant": quadrant,
        "confidence": confidence,
        "reasons": reasons
    ]
}

func reminderPlanningDate(_ reminder: EKReminder) -> Date? {
    [reminder.dueDateComponents?.date, reminder.alarms?.compactMap { $0.absoluteDate }.sorted().first]
        .compactMap { $0 }
        .min()
}

func endOfToday(from date: Date) -> Date {
    let calendar = Calendar.current
    return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
}

func remindersDBDoctor(arguments: [String]) throws -> [String: Any] {
    let defaultRoot = "\(NSHomeDirectory())/Library/Group Containers/group.com.apple.reminders/Container_v1/Stores"
    let storeRoot = absolutePath(optionValue(arguments, "--store-root") ?? defaultRoot, base: FileManager.default.currentDirectoryPath)
    let urls = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: storeRoot), includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "sqlite" }
        .sorted { $0.path < $1.path }
    let databases = try urls.map { try inspectReminderDatabase(path: $0.path) }
    let totals = databases.reduce(into: ["databases": databases.count, "sections": 0, "lists": 0, "reminders": 0]) { totals, db in
        let counts = db["row_counts"] as? [String: Int] ?? [:]
        totals["sections", default: 0] += counts["ZREMCDBASESECTION"] ?? 0
        totals["lists", default: 0] += counts["ZREMCDBASELIST"] ?? 0
        totals["reminders", default: 0] += counts["ZREMCDREMINDER"] ?? 0
    }
    return [
        "status": "ok",
        "mode": "read_only",
        "store_root": storeRoot,
        "write_api": false,
        "databases": databases,
        "totals": totals,
        "warnings": [
            "This command opens SQLite databases with SQLITE_OPEN_READONLY.",
            "Private Reminders tables are diagnostic only and must not be used for production writes."
        ]
    ] as [String: Any]
}

func inspectReminderDatabase(path: String) throws -> [String: Any] {
    var db: OpaquePointer?
    guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        let message = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unable to open database"
        sqlite3_close(db)
        throw AppError.runtime("Unable to open Reminders database read-only: \(path): \(message)")
    }
    defer { sqlite3_close(db) }
    let tables = try sqliteStringRows(db, "select name from sqlite_master where type='table' order by name")
    let interestingTables = ["ZREMCDBASESECTION", "ZREMCDBASELIST", "ZREMCDREMINDER"]
    var counts: [String: Int] = [:]
    for table in interestingTables where tables.contains(table) {
        counts[table] = try sqliteScalarInt(db, "select count(*) from \(table)")
    }
    return [
        "path": path,
        "read_only": true,
        "has_section_table": tables.contains("ZREMCDBASESECTION"),
        "has_list_table": tables.contains("ZREMCDBASELIST"),
        "has_reminder_table": tables.contains("ZREMCDREMINDER"),
        "row_counts": counts,
        "interesting_tables": tables.filter { $0.contains("SECTION") || $0.contains("LIST") || $0.contains("REMINDER") }.sorted()
    ] as [String: Any]
}

func sqliteStringRows(_ db: OpaquePointer?, _ sql: String) throws -> [String] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        throw AppError.runtime(sqliteReadOnlyError(db))
    }
    defer { sqlite3_finalize(statement) }
    var rows: [String] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        if let text = sqlite3_column_text(statement, 0) {
            rows.append(String(cString: text))
        }
    }
    return rows
}

func sqliteScalarInt(_ db: OpaquePointer?, _ sql: String) throws -> Int {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
        throw AppError.runtime(sqliteReadOnlyError(db))
    }
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
    return Int(sqlite3_column_int64(statement, 0))
}

func sqliteReadOnlyError(_ db: OpaquePointer?) -> String {
    db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "unknown SQLite read-only error"
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
        if !["record_only", "archive_low_value", "create_review_reminder", "sync_projection"].contains(rule.action) { throw AppError.runtime("Invalid action for \(rule.ruleID)") }
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
    for rule in registry.rules where rule.ruleID == "safety.high_risk_boundary" {
        if rule.triggers.contains(where: { text.contains($0.lowercased()) }) {
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
    for rule in registry.rules {
        if rule.ruleID == "safety.high_risk_boundary" {
            continue
        }
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

func mailSender(_ signal: Signal) -> String {
    for key in ["sender", "from"] {
        if let value = signal.metadata[key] as? String {
            return normalizeMailIdentity(value)
        }
    }
    return normalizeMailIdentity(signal.body.components(separatedBy: .newlines).first(where: { $0.hasPrefix("发件人:") }) ?? "")
}

func normalizeMailIdentity(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if let start = trimmed.firstIndex(of: "<"), let end = trimmed[start...].firstIndex(of: ">") {
        return String(trimmed[trimmed.index(after: start)..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return trimmed.replacingOccurrences(of: "发件人:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
}

func runOnce(_ config: AppConfig, dryRun: Bool, noReminders: Bool) throws -> [String: Any] {
    try ensureRuntime(config)
    let state = try StateStore(path: config.dbPath)
    defer { state.close() }
    let registry = try loadRuleRegistry(config.rulesFile)
    var processed: [[String: Any]] = []
    var errors: [[String: Any]] = []

    for source in googleSyncSources.sorted() where config.sourceConfig(source)["enabled"] as? Bool == true {
        do {
            processed.append(try runGoogleSyncSource(config: config, state: state, source: source, dryRun: dryRun))
        } catch {
            errors.append(["source": source, "error": "\(error)"])
            try? appendAudit(config, ["type": "google_sync_error", "source": source, "error": "\(error)"])
        }
    }

    let collected = collectEnabledSourceResults(config)
    errors.append(contentsOf: collected.errors)
    for signal in collected.signals {
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

func writeDaemonErrorReport(_ config: AppConfig, error: Error) throws {
    try ensureRuntime(config)
    let report: [String: Any] = [
        "timestamp": nowISO(),
        "processed_count": 0,
        "error_count": 1,
        "processed": [],
        "errors": [["source": "daemon", "error": "\(error)"]]
    ]
    let reportPath = "\(config.reports)/run-\(Int(Date().timeIntervalSince1970)).json"
    try writeJSON(report, to: reportPath)
}

func collectEnabledSourceResults(_ config: AppConfig) -> (signals: [Signal], errors: [[String: Any]]) {
    var signals: [Signal] = []
    var errors: [[String: Any]] = []
    let collectors: [(name: String, collect: () throws -> [Signal])] = [
        ("file_metadata", { try collectFileMetadata(config, limit: nil) }),
        ("lark_daily_context", { try collectLarkDailyContext(config) }),
        ("lark_calendar_events", { try collectLarkCalendarEvents(config, limit: nil) }),
        ("lark_tasks", { try collectLarkTasks(config, limit: nil) }),
        ("chrome_bookmarks", { try collectChromeBookmarks(config, limit: nil) }),
        ("apple_reminders_inbox", { try collectAppleRemindersInbox(config, limit: nil) }),
        ("apple_mail_summary", { try collectAppleMailSummary(config, limit: nil) })
    ]
    for collector in collectors where config.sourceConfig(collector.name)["enabled"] as? Bool == true {
        do {
            signals.append(contentsOf: try collector.collect())
        } catch {
            errors.append(["source": collector.name, "error": "\(error)"])
            try? appendAudit(config, ["type": "source_collection_error", "source": collector.name, "error": "\(error)"])
        }
    }
    return (signals, errors)
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
    let larkCalendarConfig = config.sourceConfig("lark_calendar_events")
    if larkCalendarConfig["enabled"] as? Bool == true {
        signals.append(contentsOf: try collectLarkCalendarEvents(config, limit: nil))
    }
    let larkTasksConfig = config.sourceConfig("lark_tasks")
    if larkTasksConfig["enabled"] as? Bool == true {
        signals.append(contentsOf: try collectLarkTasks(config, limit: nil))
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
    blockers.append(contentsOf: authorizationBlockersForSource(config, name: name))
    return [
        "name": name,
        "enabled": enabled,
        "acceptance_report": report ?? NSNull(),
        "acceptance_status": acceptanceStatus ?? NSNull(),
        "ready_to_enable": blockers.isEmpty,
        "blockers": blockers,
        "suggested_command": suggestedCommandForSourceBlocker(["name": name, "blockers": blockers])
    ] as [String: Any]
}

func authorizationBlockersForSource(_ config: AppConfig, name: String) -> [String] {
    switch name {
    case "apple_reminders_inbox":
        let status = EKEventStore.authorizationStatus(for: .reminder)
        return isEventKitAuthorized(status, for: .reminder) ? [] : ["eventkit_reminders_\(authorizationDescription(status))"]
    case "lark_calendar_events":
        var blockers = larkCLIBlockers()
        let status = EKEventStore.authorizationStatus(for: .event)
        if !isEventKitAuthorized(status, for: .event) {
            blockers.append("eventkit_calendar_\(authorizationDescription(status))")
        }
        return blockers
    case "lark_tasks":
        var blockers = larkCLIBlockers()
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if !isEventKitAuthorized(status, for: .reminder) {
            blockers.append("eventkit_reminders_\(authorizationDescription(status))")
        }
        return blockers
    case "google_calendar_events":
        var blockers = googleAuthBlockers(config: config, source: name)
        let status = EKEventStore.authorizationStatus(for: .event)
        if !isEventKitAuthorized(status, for: .event) {
            blockers.append("eventkit_calendar_\(authorizationDescription(status))")
        }
        return blockers
    case "google_tasks":
        var blockers = googleAuthBlockers(config: config, source: name)
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if !isEventKitAuthorized(status, for: .reminder) {
            blockers.append("eventkit_reminders_\(authorizationDescription(status))")
        }
        return blockers
    case "google_contacts":
        var blockers = googleAuthBlockers(config: config, source: name)
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if !isContactsAuthorized(status) {
            blockers.append("contacts_\(contactsAuthorizationDescription(status))")
        }
        return blockers
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
    if let run = runReport as? [String: Any],
       let errorCount = run["error_count"] as? Int,
       errorCount > 0 {
        items.append([
            "code": "last_run_errors",
            "message": "Latest run report contains processing errors.",
            "error_count": errorCount,
            "report_path": run["path"] ?? NSNull(),
            "suggested_command": "bin/smart-shadow report"
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
            if source["enabled"] as? Bool == true, source["ready_to_enable"] as? Bool == false {
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
    if blockers.contains(where: { $0.hasPrefix("eventkit_calendar_") }) {
        return "bin/smart-shadow eventkit-request-access calendar"
    }
    if blockers.contains(where: { $0.hasPrefix("contacts_") }) {
        return "bin/smart-shadow contacts-request-access"
    }
    if blockers.contains(where: { $0.hasPrefix("google_auth_") || $0 == "google_oauth_client_id_missing" }) {
        return "bin/smart-shadow google-auth login"
    }
    if blockers.contains("lark_cli_missing") {
        return "install lark-cli and run lark-cli auth login --domain calendar/task as needed"
    }
    if blockers.contains("missing_acceptance_report") {
        return "bin/smart-shadow accept-source \(name)"
    }
    return "bin/smart-shadow source-doctor"
}

func latestRunReport(_ config: AppConfig) -> Any {
    let files = (try? FileManager.default.contentsOfDirectory(atPath: config.reports)) ?? []
    let candidates = files.filter { $0.hasPrefix("run-") && $0.hasSuffix(".json") }
    guard let newest = candidates.max(by: { left, right in
        runReportSortDate(config: config, fileName: left) < runReportSortDate(config: config, fileName: right)
    }) else {
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

func runReportSortDate(config: AppConfig, fileName: String) -> Date {
    let path = "\(config.reports)/\(fileName)"
    if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
       let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let timestamp = payload["timestamp"] as? String,
       let date = parseDate(timestamp) {
        return date
    }
    let attributes = try? FileManager.default.attributesOfItem(atPath: path)
    return attributes?[.modificationDate] as? Date ?? .distantPast
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
        try requireAuthorizationForSource(config, name: name)
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

func requireAuthorizationForSource(_ config: AppConfig, name: String) throws {
    switch name {
    case "apple_reminders_inbox":
        try requireEventKitAuthorization(for: .reminder, operation: "enable Apple Reminders Inbox sensing")
    case "google_calendar_events":
        try requireGoogleAuthorization(config: config, operation: "enable Google Calendar sync")
        try requireEventKitAuthorization(for: .event, operation: "enable Google Calendar sync")
    case "google_tasks":
        try requireGoogleAuthorization(config: config, operation: "enable Google Tasks sync")
        try requireEventKitAuthorization(for: .reminder, operation: "enable Google Tasks sync")
    case "google_contacts":
        try requireGoogleAuthorization(config: config, operation: "enable Google Contacts sync")
        try requireContactsAuthorization(operation: "enable Google Contacts sync")
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
    case "lark_calendar_events":
        return try collectLarkCalendarEvents(config, limit: limit)
    case "lark_tasks":
        return try collectLarkTasks(config, limit: limit)
    case "google_calendar_events":
        return try collectGoogleCalendarPreview(config, limit: limit)
    case "google_tasks":
        return try collectGoogleTasksPreview(config, limit: limit)
    case "google_contacts":
        return try collectGoogleContactsPreview(config, limit: limit)
    case "chrome_bookmarks":
        return try collectChromeBookmarks(config, limit: limit)
    case "apple_reminders_inbox":
        return try collectAppleRemindersInbox(config, limit: limit)
    case "apple_mail_summary":
        return try collectAppleMailSummary(config, limit: limit)
    default:
        throw AppError.usage("Unsupported source acceptance target: \(name)")
    }
}

func collectFileMetadata(_ config: AppConfig, limit: Int?) throws -> [Signal] {
    let sourceConfig = config.sourceConfig("file_metadata")
    let paths = sourceConfig["paths"] as? [String] ?? []
    let maxItems = limit ?? sourceConfig["max_items"] as? Int ?? 25
    let maxAgeHours = sourceConfig["max_age_hours"] as? Double ?? Double(sourceConfig["max_age_hours"] as? Int ?? 24)
    let timeout = TimeInterval(sourceConfig["timeout_seconds"] as? Double ?? Double(sourceConfig["timeout_seconds"] as? Int ?? 5))
    let ignoreNames = Set(sourceConfig["ignore_names"] as? [String] ?? [])
    let cutoff = Date().addingTimeInterval(-maxAgeHours * 3600)
    var candidates: [(date: Date, url: URL, size: UInt64)] = []

    for rawPath in paths {
        let root = URL(fileURLWithPath: configuredPath(rawPath, config: config))
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            continue
        }
        let listing: String
        do {
            listing = try runExternalCommand(["find", root.path, "-maxdepth", "1", "-type", "f", "-print"], timeout: timeout)
        } catch {
            try? appendAudit(config, ["type": "file_metadata_scan_error", "path": root.path, "error": "\(error)"])
            continue
        }
        let contents = listing
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { URL(fileURLWithPath: $0) }
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

func collectLarkCalendarEvents(_ config: AppConfig, limit: Int?) throws -> [Signal] {
    let sourceConfig = config.sourceConfig("lark_calendar_events")
    let timeout = TimeInterval(sourceConfig["timeout_seconds"] as? Double ?? Double(sourceConfig["timeout_seconds"] as? Int ?? 20))
    let maxItems = limit ?? sourceConfig["max_items"] as? Int ?? 100
    var records: [[String: Any]] = []
    for command in try larkCalendarCommands(sourceConfig, timeout: timeout) {
        let raw = try runExternalCommand(command.argv, timeout: timeout)
        let parsed = try JSONSerialization.jsonObject(with: Data(raw.utf8))
        let commandRecords = jsonRecords(parsed).map { record -> [String: Any] in
            var annotated = record
            if let sourceCalendarID = command.sourceCalendarID {
                annotated["source_calendar_id"] = sourceCalendarID
            }
            if let sourceCalendarSummary = command.sourceCalendarSummary {
                annotated["source_calendar_summary"] = sourceCalendarSummary
            }
            return annotated
        }
        records.append(contentsOf: commandRecords)
        if records.count >= maxItems {
            break
        }
    }

    return records.prefix(maxItems).compactMap { record in
        guard let eventID = larkString(record, ["instance_id", "event_id", "id", "uid"]) else {
            return nil
        }
        let title = larkString(record, ["summary", "title", "name"]) ?? "(untitled Lark event)"
        let start = larkDateString(record, ["start_time", "start", "start_at"])
        let end = larkDateString(record, ["end_time", "end", "end_at"])
        let location = larkString(record, ["location", "meeting_room", "room"])
        let url = larkString(record, ["url", "share_url", "app_link", "applink", "vchat"])
        let description = larkString(record, ["description", "notes", "content"])
        let rsvp = larkString(record, ["self_rsvp_status", "rsvp_status"])
        let sourceCalendarID = larkString(record, ["source_calendar_id"])
        let organizerCalendarID = larkString(record, ["calendar_id", "organizer_calendar_id"])
        let sourceCalendarSummary = larkString(record, ["source_calendar_summary"])
        let sourceID = "\(eventID):\(sha256Prefix(stableJSON(record)))"
        let body = description ?? ""
        let canonicalKey = sourceCalendarID.map { "lark:calendar:\($0):\(eventID)" } ?? "lark:calendar:\(eventID)"
        var metadata: [String: Any] = [
            "canonical_key": canonicalKey,
            "lark_event_id": eventID,
            "readonly_external_command": true,
            "argv0": "lark-cli",
            "projection_target": "calendar"
        ]
        if let start { metadata["calendar_start"] = start }
        if let end { metadata["calendar_end"] = end }
        if let location { metadata["location"] = location }
        if let url { metadata["url"] = url }
        if let description { metadata["description"] = description }
        if let rsvp { metadata["self_rsvp_status"] = rsvp }
        if let sourceCalendarID { metadata["source_calendar_id"] = sourceCalendarID }
        if let organizerCalendarID { metadata["organizer_calendar_id"] = organizerCalendarID }
        if let sourceCalendarSummary {
            metadata["source_calendar_summary"] = sourceCalendarSummary
            if let domain = larkCalendarDomain(sourceCalendarSummary, sourceConfig: sourceConfig) {
                metadata["expected_domain"] = domain
            }
        }
        return Signal(
            source: "lark_calendar_events",
            sourceID: sourceID,
            title: title,
            body: body,
            kind: "lark_calendar_event",
            occurredAt: start ?? nowISO(),
            metadata: metadata
        )
    }
}

func collectLarkTasks(_ config: AppConfig, limit: Int?) throws -> [Signal] {
    let sourceConfig = config.sourceConfig("lark_tasks")
    let timeout = TimeInterval(sourceConfig["timeout_seconds"] as? Double ?? Double(sourceConfig["timeout_seconds"] as? Int ?? 20))
    let maxItems = limit ?? sourceConfig["max_items"] as? Int ?? 100
    let raw = try runExternalCommand(larkTasksArgv(sourceConfig), timeout: timeout)
    let parsed = try JSONSerialization.jsonObject(with: Data(raw.utf8))
    let records = jsonRecords(parsed)

    return records.prefix(maxItems).compactMap { record in
        if larkBool(record, ["completed", "is_completed", "complete"]) == true {
            return nil
        }
        guard let guid = larkString(record, ["guid", "task_guid", "id"]) else {
            return nil
        }
        let title = larkString(record, ["summary", "title", "name", "task_summary"]) ?? "(untitled Lark task)"
        let due = larkString(record, ["due", "due_time", "due_at", "deadline"])
        let start = larkString(record, ["start", "start_time", "start_at"])
        let end = larkString(record, ["end", "end_time", "end_at"])
        let url = larkString(record, ["url", "app_link", "applink"])
        let description = larkString(record, ["description", "notes", "content"])
        let larkPriority = larkString(record, ["priority", "priority_label"])
        let sourceID = "\(guid):\(sha256Prefix(stableJSON(record)))"
        let body = [
            "标题: \(title)",
            due.map { "截止: \($0)" },
            start.map { "开始: \($0)" },
            url.map { "链接: \($0)" },
            description.map { "说明: \($0)" }
        ].compactMap { $0 }.joined(separator: "\n")
        var metadata: [String: Any] = [
            "canonical_key": "lark:task:\(guid)",
            "lark_task_guid": guid,
            "readonly_external_command": true,
            "argv0": "lark-cli",
            "projection_target": "reminder"
        ]
        if let due { metadata["due_date"] = due }
        if let start {
            metadata["start_at"] = start
        }
        if let end { metadata["end_at"] = end }
        if let url { metadata["url"] = url }
        if let description { metadata["description"] = description }
        if let larkPriority { metadata["lark_priority"] = larkPriority }
        return Signal(
            source: "lark_tasks",
            sourceID: sourceID,
            title: "飞书任务: \(title)",
            body: body,
            kind: "lark_task",
            occurredAt: due ?? start ?? nowISO(),
            metadata: metadata
        )
    }
}

struct LarkCalendarReadCommand {
    let argv: [String]
    let sourceCalendarID: String?
    let sourceCalendarSummary: String?
}

func larkCalendarCommands(_ sourceConfig: [String: Any], timeout: TimeInterval) throws -> [LarkCalendarReadCommand] {
    let ranges = larkCalendarWindowRanges(sourceConfig)
    var commands: [LarkCalendarReadCommand] = []
    let extraTargets = try larkExtraCalendarTargets(sourceConfig, timeout: timeout)
    for target in extraTargets {
        for range in ranges {
            commands.append(
                LarkCalendarReadCommand(
                    argv: larkCalendarInstanceViewArgv(calendarID: target.id, start: range.start, end: range.end),
                    sourceCalendarID: target.id,
                    sourceCalendarSummary: target.summary
                )
            )
        }
    }

    let argv = sourceConfig["argv"] as? [String] ?? ["lark-cli", "calendar", "+agenda", "--as", "user", "--format", "json"]
    let primaryCalendarID = sourceConfig["primary_calendar_id"] as? String
    let primaryCalendarSummary = sourceConfig["primary_calendar_summary"] as? String
    if argv.contains("--start") || argv.contains("--end") {
        commands.append(LarkCalendarReadCommand(argv: argv, sourceCalendarID: primaryCalendarID, sourceCalendarSummary: primaryCalendarSummary))
        return commands
    }
    commands.append(contentsOf: ranges.map { range in
        var command = argv
        command.append(contentsOf: ["--start", isoString(range.start), "--end", isoString(range.end)])
        return LarkCalendarReadCommand(argv: command, sourceCalendarID: primaryCalendarID, sourceCalendarSummary: primaryCalendarSummary)
    })
    return commands
}

func larkCalendarDomain(_ sourceCalendarSummary: String, sourceConfig: [String: Any]) -> String? {
    let domains = sourceConfig["source_calendar_domains"] as? [String: String] ?? [:]
    guard let rawDomain = domains[sourceCalendarSummary]?.lowercased() else {
        return nil
    }
    let normalized = rawDomain == "network" ? "relationship" : rawDomain
    return ["money", "health", "relationship", "work"].contains(normalized) ? normalized : nil
}

func larkCalendarWindowRanges(_ sourceConfig: [String: Any]) -> [(start: Date, end: Date)] {
    let pastDays = sourceConfig["window_past_days"] as? Int ?? 7
    let futureDays = sourceConfig["window_future_days"] as? Int ?? 30
    let chunkDays = max(1, sourceConfig["chunk_days"] as? Int ?? 1)
    let calendar = Calendar(identifier: .gregorian)
    let todayStart = calendar.startOfDay(for: Date())
    let windowStart = calendar.date(byAdding: .day, value: -pastDays, to: todayStart) ?? todayStart
    let windowEnd = calendar.date(byAdding: .day, value: futureDays + 1, to: todayStart) ?? todayStart
    var ranges: [(start: Date, end: Date)] = []
    var cursor = windowStart
    while cursor < windowEnd {
        let next = min(calendar.date(byAdding: .day, value: chunkDays, to: cursor) ?? windowEnd, windowEnd)
        ranges.append((start: cursor, end: next))
        cursor = next
    }
    return ranges
}

func larkTasksArgv(_ sourceConfig: [String: Any]) -> [String] {
    sourceConfig["argv"] as? [String] ?? ["lark-cli", "task", "+get-my-tasks", "--as", "user", "--complete=false", "--page-all", "--format", "json"]
}

func larkExtraCalendarTargets(_ sourceConfig: [String: Any], timeout: TimeInterval) throws -> [(id: String, summary: String)] {
    var targets: [(id: String, summary: String)] = []
    if let ids = sourceConfig["extra_calendar_ids"] as? [String] {
        targets.append(contentsOf: ids.map { (id: $0, summary: $0) })
    }
    guard let summaries = sourceConfig["extra_calendar_summaries"] as? [String], !summaries.isEmpty else {
        return targets
    }

    let raw = try runExternalCommand(["lark-cli", "calendar", "calendars", "list", "--as", "user", "--format", "json"], timeout: timeout)
    let parsed = try JSONSerialization.jsonObject(with: Data(raw.utf8))
    let calendars = jsonRecords(parsed)
    for summary in summaries {
        if let calendar = calendars.first(where: { record in
            larkString(record, ["summary"]) == summary || larkString(record, ["summary_alias"]) == summary
        }), let id = larkString(calendar, ["calendar_id"]) {
            targets.append((id: id, summary: summary))
        } else {
            throw AppError.runtime("Lark calendar named \(summary) was not found.")
        }
    }
    return targets
}

func larkCalendarInstanceViewArgv(calendarID: String, start: Date, end: Date) -> [String] {
    let params: [String: String] = [
        "calendar_id": calendarID,
        "start_time": String(Int(start.timeIntervalSince1970)),
        "end_time": String(Int(end.timeIntervalSince1970))
    ]
    let data = try? JSONSerialization.data(withJSONObject: params, options: [.sortedKeys])
    let paramsJSON = data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    return ["lark-cli", "calendar", "events", "instance_view", "--as", "user", "--format", "json", "--params", paramsJSON]
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
    for key in ["items", "events", "tasks", "records", "calendar_list"] {
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

func stableJSON(_ value: Any) -> String {
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
          let text = String(data: data, encoding: .utf8)
    else {
        return String(describing: value)
    }
    return text
}

func larkString(_ record: [String: Any], _ keys: [String]) -> String? {
    for key in keys {
        guard let value = record[key], !(value is NSNull) else { continue }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        } else if let number = value as? NSNumber {
            return number.stringValue
        } else if let object = value as? [String: Any] {
            if let nested = larkString(object, ["datetime", "timestamp", "time", "date_time", "date", "value", "text", "name", "address", "meeting_url"]) {
                return nested
            }
        }
    }
    return nil
}

func larkDateString(_ record: [String: Any], _ keys: [String]) -> String? {
    guard let raw = larkString(record, keys) else {
        return nil
    }
    if let seconds = TimeInterval(raw), seconds > 1_000_000_000 {
        return isoString(Date(timeIntervalSince1970: seconds))
    }
    return raw
}

func larkBool(_ record: [String: Any], _ keys: [String]) -> Bool? {
    for key in keys {
        guard let value = record[key], !(value is NSNull) else { continue }
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["true", "1", "yes", "completed", "complete"].contains(normalized) { return true }
            if ["false", "0", "no", "incomplete", "open"].contains(normalized) { return false }
        }
    }
    return nil
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

func larkCLIBlockers() -> [String] {
    findExecutableInPath("lark-cli") == nil ? ["lark_cli_missing"] : []
}

func findExecutableInPath(_ name: String) -> String? {
    let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
    for path in paths {
        let candidate = "\(path)/\(name)"
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    return nil
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
    guard semaphore.wait(timeout: .now() + 30) == .success else {
        throw AppError.runtime("Timed out fetching Apple Reminders Inbox through EventKit.")
    }
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

enum GoogleHTTPError: Error, CustomStringConvertible {
    case status(Int, String)

    var description: String {
        switch self {
        case let .status(code, body):
            return "Google HTTP \(code): \(body.prefix(240))"
        }
    }
}

struct GoogleToken: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
    }
}

struct GoogleClient {
    let config: AppConfig

    func getJSON(path: String, query: [String: String]) throws -> [String: Any] {
        if let mock = try googleMockPayload(config) {
            return try googleMockResponse(mock, path: path, query: query)
        }
        let token = try googleAccessToken(config)
        var components = URLComponents(string: "https://www.googleapis.com\(path)")!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }.sorted { $0.name < $1.name }
        guard let url = components.url else { throw AppError.runtime("Unable to build Google URL for \(path).") }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let response = try syncHTTPRequest(request)
        guard (200..<300).contains(response.status) else {
            throw GoogleHTTPError.status(response.status, response.body)
        }
        return try parseJSONObject(response.body)
    }

    func postForm(path: String, form: [String: String]) throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncoded(form).data(using: .utf8)
        let response = try syncHTTPRequest(request)
        guard (200..<300).contains(response.status) else {
            throw GoogleHTTPError.status(response.status, response.body)
        }
        return try parseJSONObject(response.body)
    }
}

func runGoogleSyncSource(config: AppConfig, state: StateStore, source: String, dryRun: Bool) throws -> [String: Any] {
    switch source {
    case "google_calendar_events":
        return try syncGoogleCalendar(config: config, state: state, dryRun: dryRun)
    case "google_tasks":
        return try syncGoogleTasks(config: config, state: state, dryRun: dryRun)
    case "google_contacts":
        return try syncGoogleContacts(config: config, state: state, dryRun: dryRun)
    default:
        throw AppError.runtime("Unsupported Google sync source: \(source)")
    }
}

func collectGoogleCalendarPreview(_ config: AppConfig, limit: Int?) throws -> [Signal] {
    let client = GoogleClient(config: config)
    let calendarList = try googleCalendarList(config: config, client: client)
    let maxItems = limit ?? config.sourceConfig("google_calendar_events")["max_items"] as? Int ?? 25
    var signals: [Signal] = []
    for calendar in calendarList.prefix(max(1, maxItems)) {
        let calendarID = stringField(calendar, ["id"]) ?? "primary"
        let summary = stringField(calendar, ["summary"]) ?? calendarID
        let events = try googleCalendarEvents(config: config, client: client, calendarID: calendarID, syncToken: nil)
        for event in events.items.prefix(maxItems - signals.count) {
            signals.append(googleCalendarSignal(event: event, calendarID: calendarID, calendarSummary: summary))
        }
        if signals.count >= maxItems { break }
    }
    return signals
}

func collectGoogleTasksPreview(_ config: AppConfig, limit: Int?) throws -> [Signal] {
    let client = GoogleClient(config: config)
    let lists = try googleTaskLists(config: config, client: client)
    let maxItems = limit ?? config.sourceConfig("google_tasks")["max_items"] as? Int ?? 25
    var signals: [Signal] = []
    for list in lists.prefix(max(1, maxItems)) {
        let listID = stringField(list, ["id"]) ?? "@default"
        let title = stringField(list, ["title"]) ?? listID
        let tasks = try googleTasks(config: config, client: client, taskListID: listID)
        for task in tasks.prefix(maxItems - signals.count) {
            signals.append(googleTaskSignal(task: task, taskListID: listID, taskListTitle: title))
        }
        if signals.count >= maxItems { break }
    }
    return signals
}

func collectGoogleContactsPreview(_ config: AppConfig, limit: Int?) throws -> [Signal] {
    let client = GoogleClient(config: config)
    let payload = try googlePeopleConnections(config: config, client: client, syncToken: nil)
    let people = payload["connections"] as? [[String: Any]] ?? []
    let maxItems = limit ?? config.sourceConfig("google_contacts")["max_items"] as? Int ?? 25
    return people.prefix(maxItems).map { googleContactSignal($0) }
}

func syncGoogleCalendar(config: AppConfig, state: StateStore, dryRun: Bool) throws -> [String: Any] {
    if !dryRun {
        try requireGoogleAuthorization(config: config, operation: "sync Google Calendar")
        try requireEventKitAuthorization(for: .event, operation: "sync Google Calendar")
    }
    let client = GoogleClient(config: config)
    let calendars = try googleCalendarList(config: config, client: client)
    var counts = syncCounts()
    var details: [[String: Any]] = []
    for calendar in calendars {
        let calendarID = stringField(calendar, ["id"]) ?? "primary"
        let summary = stringField(calendar, ["summary"]) ?? calendarID
        let cursor = try state.syncCursor(source: "google_calendar_events", collectionID: calendarID, cursorType: "syncToken")
        let page: GooglePagedItems
        do {
            page = try googleCalendarEvents(config: config, client: client, calendarID: calendarID, syncToken: cursor)
        } catch GoogleHTTPError.status(410, _) {
            try state.clearSyncCursor(source: "google_calendar_events", collectionID: calendarID, cursorType: "syncToken")
            page = try googleCalendarEvents(config: config, client: client, calendarID: calendarID, syncToken: nil)
            details.append(["collection": calendarID, "cursor_reset": true])
        }
        for event in page.items {
            let itemResult = try syncGoogleCalendarEvent(config: config, state: state, event: event, calendarID: calendarID, calendarSummary: summary, dryRun: dryRun)
            incrementSyncCounts(&counts, itemResult)
        }
        if !dryRun {
            try state.recordSyncCursor(source: "google_calendar_events", collectionID: calendarID, cursorType: "syncToken", value: page.nextSyncToken)
        }
        details.append(["collection": calendarID, "summary": summary, "items": page.items.count, "next_sync_token": page.nextSyncToken == nil ? NSNull() : "stored"])
    }
    return googleSyncResult(source: "google_calendar_events", dryRun: dryRun, counts: counts, details: details)
}

func syncGoogleTasks(config: AppConfig, state: StateStore, dryRun: Bool) throws -> [String: Any] {
    if !dryRun {
        try requireGoogleAuthorization(config: config, operation: "sync Google Tasks")
        try requireEventKitAuthorization(for: .reminder, operation: "sync Google Tasks")
    }
    let client = GoogleClient(config: config)
    let lists = try googleTaskLists(config: config, client: client)
    var counts = syncCounts()
    var details: [[String: Any]] = []
    for list in lists {
        let listID = stringField(list, ["id"]) ?? "@default"
        let title = stringField(list, ["title"]) ?? listID
        let tasks = try googleTasks(config: config, client: client, taskListID: listID)
        for task in tasks {
            let itemResult = try syncGoogleTask(config: config, state: state, task: task, taskListID: listID, taskListTitle: title, dryRun: dryRun)
            incrementSyncCounts(&counts, itemResult)
        }
        details.append(["collection": listID, "title": title, "items": tasks.count])
    }
    return googleSyncResult(source: "google_tasks", dryRun: dryRun, counts: counts, details: details)
}

func syncGoogleContacts(config: AppConfig, state: StateStore, dryRun: Bool) throws -> [String: Any] {
    if !dryRun {
        try requireGoogleAuthorization(config: config, operation: "sync Google Contacts")
        try requireContactsAuthorization(operation: "sync Google Contacts")
    }
    let client = GoogleClient(config: config)
    let cursor = try state.syncCursor(source: "google_contacts", collectionID: "people/me/connections", cursorType: "syncToken")
    let payload: [String: Any]
    do {
        payload = try googlePeopleConnections(config: config, client: client, syncToken: cursor)
    } catch GoogleHTTPError.status(410, _) {
        try state.clearSyncCursor(source: "google_contacts", collectionID: "people/me/connections", cursorType: "syncToken")
        payload = try googlePeopleConnections(config: config, client: client, syncToken: nil)
    }
    let people = payload["connections"] as? [[String: Any]] ?? []
    var counts = syncCounts()
    for person in people {
        let itemResult = try syncGoogleContact(state: state, person: person, dryRun: dryRun)
        incrementSyncCounts(&counts, itemResult)
    }
    if !dryRun {
        try state.recordSyncCursor(source: "google_contacts", collectionID: "people/me/connections", cursorType: "syncToken", value: payload["nextSyncToken"] as? String)
    }
    return googleSyncResult(source: "google_contacts", dryRun: dryRun, counts: counts, details: [["collection": "people/me/connections", "items": people.count, "next_sync_token": payload["nextSyncToken"] == nil ? NSNull() : "stored"]])
}

func syncCounts() -> [String: Int] {
    ["created": 0, "updated": 0, "deleted": 0, "completed": 0, "skipped": 0, "errors": 0]
}

func incrementSyncCounts(_ counts: inout [String: Int], _ key: String) {
    counts[key, default: 0] += 1
}

func googleSyncResult(source: String, dryRun: Bool, counts: [String: Int], details: [[String: Any]]) -> [String: Any] {
    [
        "source": source,
        "action": "google_sync",
        "status": dryRun ? "dry_run" : "done",
        "counts": counts,
        "details": details
    ] as [String: Any]
}

struct GooglePagedItems {
    let items: [[String: Any]]
    let nextSyncToken: String?
}

func googleCalendarList(config: AppConfig, client: GoogleClient) throws -> [[String: Any]] {
    let sourceConfig = config.sourceConfig("google_calendar_events")
    if let configured = sourceConfig["calendar_ids"] as? [String], !configured.isEmpty {
        return configured.map { ["id": $0, "summary": $0] }
    }
    let payload = try client.getJSON(path: "/calendar/v3/users/me/calendarList", query: [:])
    return payload["items"] as? [[String: Any]] ?? []
}

func googleCalendarEvents(config: AppConfig, client: GoogleClient, calendarID: String, syncToken: String?) throws -> GooglePagedItems {
    let sourceConfig = config.sourceConfig("google_calendar_events")
    var query: [String: String] = ["singleEvents": "true", "showDeleted": "true", "maxResults": "\(sourceConfig["page_size"] as? Int ?? 250)"]
    if let syncToken {
        query["syncToken"] = syncToken
    } else {
        query["timeMin"] = sourceConfig["time_min"] as? String ?? isoString(Date().addingTimeInterval(-7 * 24 * 3600))
        query["timeMax"] = sourceConfig["time_max"] as? String ?? isoString(Date().addingTimeInterval(60 * 24 * 3600))
    }
    let payload = try client.getJSON(path: "/calendar/v3/calendars/\(urlPathEscape(calendarID))/events", query: query)
    return GooglePagedItems(items: payload["items"] as? [[String: Any]] ?? [], nextSyncToken: payload["nextSyncToken"] as? String)
}

func googleTaskLists(config: AppConfig, client: GoogleClient) throws -> [[String: Any]] {
    let sourceConfig = config.sourceConfig("google_tasks")
    if let configured = sourceConfig["task_list_ids"] as? [String], !configured.isEmpty {
        return configured.map { ["id": $0, "title": $0] }
    }
    let payload = try client.getJSON(path: "/tasks/v1/users/@me/lists", query: ["maxResults": "\(sourceConfig["page_size"] as? Int ?? 100)"])
    return payload["items"] as? [[String: Any]] ?? []
}

func googleTasks(config: AppConfig, client: GoogleClient, taskListID: String) throws -> [[String: Any]] {
    let sourceConfig = config.sourceConfig("google_tasks")
    let payload = try client.getJSON(
        path: "/tasks/v1/lists/\(urlPathEscape(taskListID))/tasks",
        query: [
            "maxResults": "\(sourceConfig["page_size"] as? Int ?? 100)",
            "showCompleted": "true",
            "showDeleted": "true",
            "showHidden": "true"
        ]
    )
    return payload["items"] as? [[String: Any]] ?? []
}

func googlePeopleConnections(config: AppConfig, client: GoogleClient, syncToken: String?) throws -> [String: Any] {
    let sourceConfig = config.sourceConfig("google_contacts")
    var query: [String: String] = [
        "pageSize": "\(sourceConfig["page_size"] as? Int ?? 100)",
        "personFields": sourceConfig["person_fields"] as? String ?? "names,emailAddresses,phoneNumbers,organizations,birthdays,addresses,metadata",
        "requestSyncToken": "true"
    ]
    if let syncToken { query["syncToken"] = syncToken }
    return try client.getJSON(path: "/v1/people/me/connections", query: query)
}

func syncGoogleCalendarEvent(config: AppConfig, state: StateStore, event: [String: Any], calendarID: String, calendarSummary: String, dryRun: Bool) throws -> String {
    guard let googleID = stringField(event, ["id"]) else { return "skipped" }
    let mapping = try state.syncMapping(source: "google_calendar_events", googleID: "\(calendarID):\(googleID)", appleKind: "calendar_event")
    if stringField(event, ["status"]) == "cancelled" {
        if !dryRun, let externalID = mapping?["apple_external_id"] as? String {
            try deleteAppleCalendarEvent(externalID)
            try state.markSyncMappingDeleted(source: "google_calendar_events", googleID: "\(calendarID):\(googleID)", appleKind: "calendar_event")
            return "deleted"
        }
        return mapping == nil ? "skipped" : "deleted"
    }
    if dryRun { return mapping == nil ? "created" : "updated" }
    let appleID = try upsertGoogleCalendarEvent(config: config, event: event, calendarID: calendarID, calendarSummary: calendarSummary, existingExternalID: mapping?["apple_external_id"] as? String)
    try state.recordSyncMapping(source: "google_calendar_events", googleID: "\(calendarID):\(googleID)", appleKind: "calendar_event", appleExternalID: appleID, googleETag: stringField(event, ["etag"]))
    return mapping == nil ? "created" : "updated"
}

func syncGoogleTask(config: AppConfig, state: StateStore, task: [String: Any], taskListID: String, taskListTitle: String, dryRun: Bool) throws -> String {
    guard let googleID = stringField(task, ["id"]) else { return "skipped" }
    let compoundID = "\(taskListID):\(googleID)"
    let mapping = try state.syncMapping(source: "google_tasks", googleID: compoundID, appleKind: "reminder")
    if boolField(task, "deleted") {
        if !dryRun, let externalID = mapping?["apple_external_id"] as? String {
            try deleteAppleReminder(externalID)
            try state.markSyncMappingDeleted(source: "google_tasks", googleID: compoundID, appleKind: "reminder")
            return "deleted"
        }
        return mapping == nil ? "skipped" : "deleted"
    }
    if dryRun { return stringField(task, ["status"]) == "completed" ? "completed" : (mapping == nil ? "created" : "updated") }
    let appleID = try upsertGoogleTaskReminder(task: task, taskListTitle: taskListTitle, existingExternalID: mapping?["apple_external_id"] as? String)
    try state.recordSyncMapping(source: "google_tasks", googleID: compoundID, appleKind: "reminder", appleExternalID: appleID, googleETag: stringField(task, ["etag"]))
    return stringField(task, ["status"]) == "completed" ? "completed" : (mapping == nil ? "created" : "updated")
}

func syncGoogleContact(state: StateStore, person: [String: Any], dryRun: Bool) throws -> String {
    guard let resourceName = stringField(person, ["resourceName"]) else { return "skipped" }
    let mapping = try state.syncMapping(source: "google_contacts", googleID: resourceName, appleKind: "contact")
    if googlePersonDeleted(person) {
        if !dryRun, let externalID = mapping?["apple_external_id"] as? String {
            try deleteAppleContact(externalID)
            try state.markSyncMappingDeleted(source: "google_contacts", googleID: resourceName, appleKind: "contact")
            return "deleted"
        }
        return mapping == nil ? "skipped" : "deleted"
    }
    if dryRun { return mapping == nil ? "created" : "updated" }
    let appleID = try upsertGoogleContact(person: person, existingExternalID: mapping?["apple_external_id"] as? String)
    try state.recordSyncMapping(source: "google_contacts", googleID: resourceName, appleKind: "contact", appleExternalID: appleID, googleETag: stringField(person, ["etag"]))
    return mapping == nil ? "created" : "updated"
}

func upsertGoogleCalendarEvent(config: AppConfig, event: [String: Any], calendarID: String, calendarSummary: String, existingExternalID: String?) throws -> String {
    let store = sharedEventStoreBox.store
    let calendar = try findOrCreateGoogleEventCalendar(config: config, calendarID: calendarID, summary: calendarSummary, store: store)
    let item = eventKitItem(existingExternalID, store: store) as? EKEvent ?? EKEvent(eventStore: store)
    item.title = stringField(event, ["summary"]) ?? "(untitled Google event)"
    item.notes = stringField(event, ["description"])
    item.location = stringField(event, ["location"])
    item.url = stringField(event, ["htmlLink"]).flatMap(URL.init(string:))
    let dates = googleEventDates(event)
    item.startDate = dates.start
    item.endDate = max(dates.end, dates.start.addingTimeInterval(60))
    item.isAllDay = dates.allDay
    item.calendar = calendar
    try store.save(item, span: .thisEvent, commit: true)
    return "x-apple-calendar://\(item.calendarItemIdentifier)"
}

func upsertGoogleTaskReminder(task: [String: Any], taskListTitle: String, existingExternalID: String?) throws -> String {
    let store = sharedEventStoreBox.store
    let reminder = eventKitItem(existingExternalID, store: store) as? EKReminder ?? EKReminder(eventStore: store)
    reminder.title = stringField(task, ["title"]) ?? "(untitled Google task)"
    reminder.notes = stringField(task, ["notes"])
    reminder.calendar = try findOrCreateGoogleReminderList(named: "Google Tasks - \(taskListTitle)", store: store)
    reminder.isCompleted = stringField(task, ["status"]) == "completed"
    if let completed = stringField(task, ["completed"]).flatMap(parseDate) {
        reminder.completionDate = completed
    }
    if let due = stringField(task, ["due"]).flatMap(parseDate) {
        reminder.dueDateComponents = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: due)
    } else {
        reminder.dueDateComponents = nil
    }
    try store.save(reminder, commit: true)
    return "x-apple-reminder://\(reminder.calendarItemIdentifier)"
}

func upsertGoogleContact(person: [String: Any], existingExternalID: String?) throws -> String {
    let store = sharedContactStoreBox.store
    let contact: CNMutableContact
    let keys = googleContactKeys()
    if let existingExternalID, let existing = try? store.unifiedContact(withIdentifier: stripAppleURL(existingExternalID), keysToFetch: keys) {
        contact = existing.mutableCopy() as! CNMutableContact
    } else {
        contact = CNMutableContact()
    }
    applyGooglePerson(person, to: contact)
    let request = CNSaveRequest()
    if existingExternalID == nil || contact.identifier.isEmpty {
        if let container = try iCloudContactsContainer(store: store) {
            request.add(contact, toContainerWithIdentifier: container.identifier)
        } else {
            request.add(contact, toContainerWithIdentifier: nil)
        }
    } else {
        request.update(contact)
    }
    try store.execute(request)
    return "x-apple-contact://\(contact.identifier)"
}

func deleteAppleCalendarEvent(_ externalID: String) throws {
    let store = sharedEventStoreBox.store
    if let event = eventKitItem(externalID, store: store) as? EKEvent {
        try store.remove(event, span: .thisEvent, commit: true)
    }
}

func deleteAppleReminder(_ externalID: String) throws {
    let store = sharedEventStoreBox.store
    if let reminder = eventKitItem(externalID, store: store) as? EKReminder {
        try store.remove(reminder, commit: true)
    }
}

func deleteAppleContact(_ externalID: String) throws {
    let store = sharedContactStoreBox.store
    if let existing = try? store.unifiedContact(withIdentifier: stripAppleURL(externalID), keysToFetch: googleContactKeys()) {
        let request = CNSaveRequest()
        request.delete(existing.mutableCopy() as! CNMutableContact)
        try store.execute(request)
    }
}

func findOrCreateGoogleEventCalendar(config: AppConfig, calendarID: String, summary: String, store: EKEventStore) throws -> EKCalendar {
    let sourceConfig = config.sourceConfig("google_calendar_events")
    let names = sourceConfig["apple_calendar_names"] as? [String: String] ?? [:]
    let name = names[calendarID] ?? "Google - \(summary)"
    if let found = store.calendars(for: .event).first(where: { $0.title == name && $0.allowsContentModifications }) {
        return found
    }
    guard let source = iCloudEventSource(store: store) ?? store.defaultCalendarForNewEvents?.source ?? store.sources.first(where: { $0.sourceType == .local }) else {
        throw AppError.runtime("No writable Calendar source available for Google calendar \(summary).")
    }
    let calendar = EKCalendar(for: .event, eventStore: store)
    calendar.title = name
    calendar.source = source
    try store.saveCalendar(calendar, commit: true)
    return calendar
}

func findOrCreateGoogleReminderList(named name: String, store: EKEventStore) throws -> EKCalendar {
    if let found = store.calendars(for: .reminder).first(where: { $0.title == name && $0.allowsContentModifications }) {
        return found
    }
    guard let source = iCloudReminderSource(store: store) ?? store.defaultCalendarForNewReminders()?.source else {
        throw AppError.runtime("No writable Reminders source available for \(name).")
    }
    let list = EKCalendar(for: .reminder, eventStore: store)
    list.title = name
    list.source = source
    try store.saveCalendar(list, commit: true)
    return list
}

func iCloudEventSource(store: EKEventStore) -> EKSource? {
    store.sources.first { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }
}

func iCloudReminderSource(store: EKEventStore) -> EKSource? {
    store.calendars(for: .reminder)
        .filter { $0.allowsContentModifications }
        .map(\.source)
        .first { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") }
    ?? store.calendars(for: .reminder)
        .first { $0.allowsContentModifications }?
        .source
}

func iCloudContactsContainer(store: CNContactStore) throws -> CNContainer? {
    let containers = try store.containers(matching: nil)
    return containers.first { $0.type == .cardDAV && $0.name.lowercased().contains("icloud") } ?? containers.first(where: { $0.type == .local }) ?? containers.first
}

func googleCalendarSignal(event: [String: Any], calendarID: String, calendarSummary: String) -> Signal {
    let googleID = stringField(event, ["id"]) ?? sha256Prefix(String(describing: event))
    let dates = googleEventDates(event)
    return Signal(
        source: "google_calendar_events",
        sourceID: "\(calendarID):\(googleID)",
        title: stringField(event, ["summary"]) ?? "(untitled Google event)",
        body: stringField(event, ["description"]) ?? "",
        kind: "google_calendar_event",
        occurredAt: isoString(dates.start),
        metadata: [
            "canonical_key": "google:calendar:\(calendarID):\(googleID)",
            "calendar_id": calendarID,
            "calendar_summary": calendarSummary,
            "calendar_start": isoString(dates.start),
            "calendar_end": isoString(dates.end),
            "status": stringField(event, ["status"]) ?? "",
            "projection_target": "calendar",
            "strict_mirror": true
        ]
    )
}

func googleTaskSignal(task: [String: Any], taskListID: String, taskListTitle: String) -> Signal {
    let googleID = stringField(task, ["id"]) ?? sha256Prefix(String(describing: task))
    return Signal(
        source: "google_tasks",
        sourceID: "\(taskListID):\(googleID)",
        title: stringField(task, ["title"]) ?? "(untitled Google task)",
        body: stringField(task, ["notes"]) ?? "",
        kind: "google_task",
        occurredAt: stringField(task, ["updated"]) ?? nowISO(),
        metadata: [
            "canonical_key": "google:task:\(taskListID):\(googleID)",
            "task_list_id": taskListID,
            "task_list_title": taskListTitle,
            "due_date": stringField(task, ["due"]) ?? "",
            "status": stringField(task, ["status"]) ?? "",
            "deleted": boolField(task, "deleted"),
            "projection_target": "reminder",
            "strict_mirror": true
        ]
    )
}

func googleContactSignal(_ person: [String: Any]) -> Signal {
    let resourceName = stringField(person, ["resourceName"]) ?? sha256Prefix(String(describing: person))
    let title = googlePersonDisplayName(person) ?? "(unnamed Google contact)"
    return Signal(
        source: "google_contacts",
        sourceID: resourceName,
        title: title,
        body: "Google contact preview: \(title)",
        kind: "google_contact",
        occurredAt: nowISO(),
        metadata: [
            "canonical_key": "google:contact:\(resourceName)",
            "resource_name": resourceName,
            "deleted": googlePersonDeleted(person),
            "projection_target": "contact",
            "strict_mirror": true
        ]
    )
}

func googleEventDates(_ event: [String: Any]) -> (start: Date, end: Date, allDay: Bool) {
    let startObj = event["start"] as? [String: Any] ?? [:]
    let endObj = event["end"] as? [String: Any] ?? [:]
    let startRaw = stringField(startObj, ["dateTime", "date"]) ?? nowISO()
    let endRaw = stringField(endObj, ["dateTime", "date"]) ?? startRaw
    let start = parseDate(startRaw) ?? Date()
    let end = parseDate(endRaw) ?? Calendar.current.date(byAdding: .minute, value: 30, to: start) ?? start.addingTimeInterval(1800)
    return (start, end, startObj["date"] is String)
}

func googlePersonDisplayName(_ person: [String: Any]) -> String? {
    guard let names = person["names"] as? [[String: Any]] else { return nil }
    return names.compactMap { stringField($0, ["displayName", "unstructuredName"]) }.first
}

func googlePersonDeleted(_ person: [String: Any]) -> Bool {
    if let metadata = person["metadata"] as? [String: Any], boolField(metadata, "deleted") {
        return true
    }
    return boolField(person, "deleted")
}

func applyGooglePerson(_ person: [String: Any], to contact: CNMutableContact) {
    if let names = person["names"] as? [[String: Any]], let name = names.first {
        contact.givenName = stringField(name, ["givenName"]) ?? ""
        contact.familyName = stringField(name, ["familyName"]) ?? ""
        contact.middleName = stringField(name, ["middleName"]) ?? ""
        contact.nickname = stringField(name, ["displayName"]) ?? ""
    }
    contact.emailAddresses = (person["emailAddresses"] as? [[String: Any]] ?? []).compactMap { item in
        guard let value = stringField(item, ["value"]) else { return nil }
        return CNLabeledValue(label: googleContactLabel(item), value: value as NSString)
    }
    contact.phoneNumbers = (person["phoneNumbers"] as? [[String: Any]] ?? []).compactMap { item in
        guard let value = stringField(item, ["value", "canonicalForm"]) else { return nil }
        return CNLabeledValue(label: googleContactLabel(item), value: CNPhoneNumber(stringValue: value))
    }
    if let organization = (person["organizations"] as? [[String: Any]])?.first {
        contact.organizationName = stringField(organization, ["name"]) ?? ""
        contact.jobTitle = stringField(organization, ["title"]) ?? ""
        contact.departmentName = stringField(organization, ["department"]) ?? ""
    }
    contact.postalAddresses = (person["addresses"] as? [[String: Any]] ?? []).compactMap { item in
        let address = CNMutablePostalAddress()
        address.street = stringField(item, ["streetAddress"]) ?? ""
        address.city = stringField(item, ["city"]) ?? ""
        address.state = stringField(item, ["region"]) ?? ""
        address.postalCode = stringField(item, ["postalCode"]) ?? ""
        address.country = stringField(item, ["country"]) ?? ""
        guard ![address.street, address.city, address.state, address.postalCode, address.country].joined().isEmpty else { return nil }
        return CNLabeledValue(label: googleContactLabel(item), value: address)
    }
    if let birthday = (person["birthdays"] as? [[String: Any]])?.first?["date"] as? [String: Any] {
        var components = DateComponents()
        components.year = birthday["year"] as? Int
        components.month = birthday["month"] as? Int
        components.day = birthday["day"] as? Int
        contact.birthday = components
    }
}

func googleContactKeys() -> [CNKeyDescriptor] {
    [
        CNContactIdentifierKey,
        CNContactGivenNameKey,
        CNContactFamilyNameKey,
        CNContactMiddleNameKey,
        CNContactNicknameKey,
        CNContactEmailAddressesKey,
        CNContactPhoneNumbersKey,
        CNContactOrganizationNameKey,
        CNContactJobTitleKey,
        CNContactDepartmentNameKey,
        CNContactPostalAddressesKey,
        CNContactBirthdayKey
    ] as [CNKeyDescriptor]
}

func googleContactLabel(_ item: [String: Any]) -> String {
    switch (stringField(item, ["type"]) ?? "").lowercased() {
    case "home": return CNLabelHome
    case "work": return CNLabelWork
    default: return CNLabelOther
    }
}

func contactsStatus() -> [String: String] {
    ["contacts": contactsAuthorizationDescription(CNContactStore.authorizationStatus(for: .contacts)), "mode": "swift-native-contacts"]
}

func requestContactsAccess() throws -> [String: Any] {
    let before = CNContactStore.authorizationStatus(for: .contacts)
    if isContactsAuthorized(before) {
        return ["status": "already_authorized", "before": contactsAuthorizationDescription(before), "after": contactsAuthorizationDescription(before)]
    }
    let semaphore = DispatchSemaphore(value: 0)
    final class ResultBox: @unchecked Sendable {
        var granted = false
        var error: Error?
    }
    let box = ResultBox()
    sharedContactStoreBox.store.requestAccess(for: .contacts) { granted, error in
        box.granted = granted
        box.error = error
        semaphore.signal()
    }
    semaphore.wait()
    if let error = box.error {
        throw AppError.runtime("Contacts access request failed: \(error.localizedDescription)")
    }
    let after = CNContactStore.authorizationStatus(for: .contacts)
    return ["status": box.granted ? "granted" : "not_granted", "before": contactsAuthorizationDescription(before), "after": contactsAuthorizationDescription(after)]
}

func requireContactsAuthorization(operation: String) throws {
    let status = CNContactStore.authorizationStatus(for: .contacts)
    guard isContactsAuthorized(status) else {
        throw AppError.runtime("Contacts access is \(contactsAuthorizationDescription(status)); run `bin/smart-shadow contacts-request-access` in the foreground before \(operation).")
    }
}

func isContactsAuthorized(_ status: CNAuthorizationStatus) -> Bool {
    status == .authorized
}

func contactsAuthorizationDescription(_ status: CNAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "not_determined"
    case .restricted: return "restricted"
    case .denied: return "denied"
    case .authorized: return "authorized"
    case .limited: return "limited"
    @unknown default: return "unknown"
    }
}

func googleAuthCommand(_ config: AppConfig, subcommand: String, arguments: [String]) throws -> [String: Any] {
    switch subcommand {
    case "status":
        return googleAuthStatus(config)
    case "logout":
        try keychainDelete(account: "token")
        return ["status": "logged_out"]
    case "login":
        return try googleAuthLogin(config)
    default:
        throw AppError.usage("google-auth expects login, status, or logout.")
    }
}

func googleAuthStatus(_ config: AppConfig) -> [String: Any] {
    var status: [String: Any] = ["mode": "google-oauth-keychain"]
    status["client_id_configured"] = googleOAuthClientID(config) != nil
    if let token = try? keychainReadToken() {
        status["authorized"] = true
        status["access_token_expires_at"] = isoString(token.expiresAt)
        status["refresh_token_present"] = token.refreshToken != nil
    } else {
        status["authorized"] = false
        status["refresh_token_present"] = false
    }
    return status
}

func googleAuthLogin(_ config: AppConfig) throws -> [String: Any] {
    guard let clientID = googleOAuthClientID(config) else {
        throw AppError.runtime("Google OAuth client id is missing; set google.oauth_client_id in config.")
    }
    let port = try reserveLoopbackPort()
    let redirectURI = "http://127.0.0.1:\(port)/callback"
    let state = sha256Prefix(UUID().uuidString + nowISO())
    let scopes = googleOAuthScopes(config).joined(separator: " ")
    var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    components.queryItems = [
        URLQueryItem(name: "client_id", value: clientID),
        URLQueryItem(name: "redirect_uri", value: redirectURI),
        URLQueryItem(name: "response_type", value: "code"),
        URLQueryItem(name: "scope", value: scopes),
        URLQueryItem(name: "access_type", value: "offline"),
        URLQueryItem(name: "prompt", value: "consent"),
        URLQueryItem(name: "state", value: state)
    ]
    guard let authURL = components.url else { throw AppError.runtime("Unable to build Google auth URL.") }
    _ = try? shellOutput(["open", authURL.absoluteString])
    let callback = try waitForLoopbackCallback(port: port, expectedState: state)
    let payload = try GoogleClient(config: config).postForm(path: "/token", form: [
        "client_id": clientID,
        "client_secret": googleOAuthClientSecret(config) ?? "",
        "code": callback.code,
        "grant_type": "authorization_code",
        "redirect_uri": redirectURI
    ])
    guard let accessToken = payload["access_token"] as? String else {
        throw AppError.runtime("Google token response did not include an access token.")
    }
    let expiresIn = payload["expires_in"] as? Double ?? Double(payload["expires_in"] as? Int ?? 3600)
    let token = GoogleToken(accessToken: accessToken, refreshToken: payload["refresh_token"] as? String, expiresAt: Date().addingTimeInterval(expiresIn))
    try keychainWriteToken(token)
    return ["status": "ok", "authorized": true, "scopes": googleOAuthScopes(config), "token_storage": "keychain"]
}

func requireGoogleAuthorization(config: AppConfig, operation: String) throws {
    if hasGoogleMock(config) { return }
    guard googleOAuthClientID(config) != nil else {
        throw AppError.runtime("Google OAuth client id is missing; set google.oauth_client_id before \(operation).")
    }
    _ = try googleAccessToken(config)
}

func googleAuthBlockers(config: AppConfig, source: String) -> [String] {
    if hasGoogleMock(config, source: source) { return [] }
    var blockers: [String] = []
    if googleOAuthClientID(config) == nil {
        blockers.append("google_oauth_client_id_missing")
    }
    if (try? keychainReadToken()) == nil {
        blockers.append("google_auth_missing")
    }
    return blockers
}

func googleAccessToken(_ config: AppConfig) throws -> String {
    var token = try keychainReadToken()
    if token.expiresAt.timeIntervalSinceNow > 60 {
        return token.accessToken
    }
    guard let refresh = token.refreshToken, let clientID = googleOAuthClientID(config) else {
        throw AppError.runtime("Google access token expired and no refresh token/client id is available; run `bin/smart-shadow google-auth login`.")
    }
    let payload = try GoogleClient(config: config).postForm(path: "/token", form: [
        "client_id": clientID,
        "client_secret": googleOAuthClientSecret(config) ?? "",
        "refresh_token": refresh,
        "grant_type": "refresh_token"
    ])
    guard let access = payload["access_token"] as? String else {
        throw AppError.runtime("Google refresh response did not include an access token.")
    }
    let expiresIn = payload["expires_in"] as? Double ?? Double(payload["expires_in"] as? Int ?? 3600)
    token = GoogleToken(accessToken: access, refreshToken: refresh, expiresAt: Date().addingTimeInterval(expiresIn))
    try keychainWriteToken(token)
    return access
}

func googleOAuthClientID(_ config: AppConfig) -> String? {
    (config.raw["google"] as? [String: Any])?["oauth_client_id"] as? String
}

func googleOAuthClientSecret(_ config: AppConfig) -> String? {
    (config.raw["google"] as? [String: Any])?["oauth_client_secret"] as? String
}

func googleOAuthScopes(_ config: AppConfig) -> [String] {
    if let scopes = (config.raw["google"] as? [String: Any])?["oauth_scopes"] as? [String], !scopes.isEmpty {
        return scopes
    }
    return [
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/tasks.readonly",
        "https://www.googleapis.com/auth/contacts.readonly"
    ]
}

func keychainReadToken() throws -> GoogleToken {
    guard let data = try keychainRead(account: "token") else {
        throw AppError.runtime("Google OAuth token is missing; run `bin/smart-shadow google-auth login`.")
    }
    return try JSONDecoder().decode(GoogleToken.self, from: data)
}

func keychainWriteToken(_ token: GoogleToken) throws {
    try keychainWrite(account: "token", data: JSONEncoder().encode(token))
}

func keychainRead(account: String) throws -> Data? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: googleKeychainService,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw AppError.runtime("Keychain read failed: \(status)") }
    return item as? Data
}

func keychainWrite(account: String, data: Data) throws {
    try keychainDelete(account: account)
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: googleKeychainService,
        kSecAttrAccount as String: account,
        kSecValueData as String: data
    ]
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else { throw AppError.runtime("Keychain write failed: \(status)") }
}

func keychainDelete(account: String) throws {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: googleKeychainService,
        kSecAttrAccount as String: account
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw AppError.runtime("Keychain delete failed: \(status)") }
}

func syncHTTPRequest(_ request: URLRequest) throws -> (status: Int, body: String) {
    let semaphore = DispatchSemaphore(value: 0)
    final class ResponseBox: @unchecked Sendable {
        var data: Data?
        var response: URLResponse?
        var error: Error?
    }
    let box = ResponseBox()
    URLSession.shared.dataTask(with: request) { data, response, error in
        box.data = data
        box.response = response
        box.error = error
        semaphore.signal()
    }.resume()
    semaphore.wait()
    if let error = box.error { throw error }
    let status = (box.response as? HTTPURLResponse)?.statusCode ?? 0
    let body = String(data: box.data ?? Data(), encoding: .utf8) ?? ""
    return (status, body)
}

func parseJSONObject(_ text: String) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
        throw AppError.runtime("Expected JSON object.")
    }
    return object
}

func googleMockPayload(_ config: AppConfig) throws -> [String: Any]? {
    let paths = googleSyncSources.compactMap { config.sourceConfig($0)["mock_file"] as? String }
    guard let rawPath = paths.first else { return nil }
    return try parseJSONObject(String(contentsOfFile: configuredPath(rawPath, config: config), encoding: .utf8))
}

func hasGoogleMock(_ config: AppConfig, source: String? = nil) -> Bool {
    if let source {
        return config.sourceConfig(source)["mock_file"] is String
    }
    return googleSyncSources.contains { config.sourceConfig($0)["mock_file"] is String }
}

func googleMockResponse(_ mock: [String: Any], path: String, query: [String: String]) throws -> [String: Any] {
    if path == "/calendar/v3/users/me/calendarList" {
        return ["items": mock["calendarLists"] as? [[String: Any]] ?? []]
    }
    if path.contains("/calendar/v3/calendars/") {
        let id = path.components(separatedBy: "/calendar/v3/calendars/").last?.components(separatedBy: "/events").first?.removingPercentEncoding ?? "primary"
        if query["syncToken"] == "force-410" { throw GoogleHTTPError.status(410, "mock sync token expired") }
        return ((mock["calendarEvents"] as? [String: Any])?[id] as? [String: Any]) ?? ["items": []]
    }
    if path == "/tasks/v1/users/@me/lists" {
        return ["items": mock["taskLists"] as? [[String: Any]] ?? []]
    }
    if path.contains("/tasks/v1/lists/") {
        let id = path.components(separatedBy: "/tasks/v1/lists/").last?.components(separatedBy: "/tasks").first?.removingPercentEncoding ?? "@default"
        return ((mock["tasks"] as? [String: Any])?[id] as? [String: Any]) ?? ["items": []]
    }
    if path == "/v1/people/me/connections" {
        if query["syncToken"] == "force-410" { throw GoogleHTTPError.status(410, "mock sync token expired") }
        return mock["connections"] as? [String: Any] ?? ["connections": []]
    }
    throw AppError.runtime("No mock response for Google path: \(path)")
}

func formURLEncoded(_ form: [String: String]) -> String {
    form.map { "\(urlQueryEscape($0.key))=\(urlQueryEscape($0.value))" }.sorted().joined(separator: "&")
}

func urlQueryEscape(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
}

func urlPathEscape(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
}

func stripAppleURL(_ externalID: String) -> String {
    externalID
        .replacingOccurrences(of: "x-apple-calendar://", with: "")
        .replacingOccurrences(of: "x-apple-reminder://", with: "")
        .replacingOccurrences(of: "x-apple-contact://", with: "")
}

func boolField(_ object: [String: Any], _ key: String) -> Bool {
    if let value = object[key] as? Bool { return value }
    if let value = object[key] as? String { return parseBool(value) }
    if let value = object[key] as? NSNumber { return value.boolValue }
    return false
}

func reserveLoopbackPort() throws -> Int {
    let socketFD = socket(AF_INET, SOCK_STREAM, 0)
    guard socketFD >= 0 else { throw AppError.runtime("Unable to create loopback socket.") }
    defer { close(socketFD) }
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = in_port_t(0).bigEndian
    addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    var mutableAddr = addr
    let bindStatus = withUnsafePointer(to: &mutableAddr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindStatus == 0 else { throw AppError.runtime("Unable to bind loopback socket.") }
    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    var bound = sockaddr_in()
    let status = withUnsafeMutablePointer(to: &bound) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            getsockname(socketFD, $0, &len)
        }
    }
    guard status == 0 else { throw AppError.runtime("Unable to inspect loopback port.") }
    return Int(UInt16(bigEndian: bound.sin_port))
}

func waitForLoopbackCallback(port: Int, expectedState: String) throws -> (code: String, state: String) {
    let socketFD = socket(AF_INET, SOCK_STREAM, 0)
    guard socketFD >= 0 else { throw AppError.runtime("Unable to create Google callback socket.") }
    defer { close(socketFD) }
    var yes: Int32 = 1
    setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = in_port_t(port).bigEndian
    addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    var mutableAddr = addr
    let bindStatus = withUnsafePointer(to: &mutableAddr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindStatus == 0, listen(socketFD, 1) == 0 else {
        throw AppError.runtime("Unable to listen for Google OAuth callback.")
    }
    let client = accept(socketFD, nil, nil)
    guard client >= 0 else { throw AppError.runtime("Google OAuth callback was not received.") }
    defer { close(client) }
    var buffer = [UInt8](repeating: 0, count: 4096)
    let count = recv(client, &buffer, buffer.count, 0)
    let request = count > 0 ? String(decoding: buffer.prefix(count), as: UTF8.self) : ""
    guard let firstLine = request.components(separatedBy: "\r\n").first,
          let path = firstLine.split(separator: " ").dropFirst().first,
          let components = URLComponents(string: "http://127.0.0.1\(path)") else {
        throw AppError.runtime("Google OAuth callback request was malformed.")
    }
    let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    let html = "<html><body>Google authorization received. You can close this window.</body></html>"
    let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\n\r\n\(html)"
    _ = response.withCString { send(client, $0, strlen($0), 0) }
    guard query["state"] == expectedState, let code = query["code"], !code.isEmpty else {
        throw AppError.runtime("Google OAuth callback did not include the expected state and code.")
    }
    return (code, query["state"] ?? "")
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
            "body": signal.body,
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

func projectMailDecision(_ config: AppConfig, inputPath: String, dryRun: Bool, noReminders: Bool) throws -> [String: Any] {
    guard !inputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw AppError.usage("project-mail-decision requires --input PATH.")
    }
    try ensureRuntime(config)
    let path = absolutePath(inputPath, base: FileManager.default.currentDirectoryPath)
    let payload = try parseJSONObject(String(contentsOfFile: path, encoding: .utf8))
    let (signal, decision) = try explicitMailProjection(payload)

    let state = try StateStore(path: config.dbPath)
    defer { state.close() }
    let ingest = try state.ingest(signal)
    let decisionID = try state.recordDecision(signalID: ingest.id, decision: decision)
    let actionResult = try executeDecision(config, state: state, signal: signal, decision: decision, dryRun: dryRun, noReminders: noReminders)
    let actionID = try state.recordAction(decisionID: decisionID, result: actionResult)
    let result: [String: Any] = [
        "status": "ok",
        "input": path,
        "signal_id": ingest.id,
        "signal_created": ingest.created,
        "decision_id": decisionID,
        "action_id": actionID,
        "dedupe_key": signal.dedupeKey,
        "canonical_key": projectionCanonicalKey(signal),
        "decision": encodableDictionary(decision),
        "action_result": actionResult.dictionary
    ]
    try appendAudit(config, ["type": "explicit_mail_decision_projected"].merging(result) { _, new in new })
    return result
}

func explicitMailProjection(_ payload: [String: Any]) throws -> (Signal, Decision) {
    let canonicalKey = try requiredString(payload, "canonical_key")
    let sourceID = try requiredString(payload, "source_id", fallbackKeys: ["message_id"])
    let subject = try requiredString(payload, "subject")
    let sender = try requiredString(payload, "sender")
    let receivedAt = stringField(payload, ["received_at", "receivedAt"]) ?? nowISO()
    let mailbox = stringField(payload, ["mailbox"]) ?? "INBOX"
    let summary = stringField(payload, ["summary"]) ?? ""
    let projectionTarget = try requiredString(payload, "projection_target")
    let action = try requiredString(payload, "action")
    let domain = try requiredString(payload, "domain")
    let priority = try requiredString(payload, "priority")
    let risk = try requiredString(payload, "risk")
    let reason = try requiredString(payload, "reason")
    let suggestedAction = stringField(payload, ["suggested_action", "suggestedAction"])
    try validateExplicitMailProjectionTarget(projectionTarget, action: action)

    var metadata: [String: Any] = [
        "canonical_key": canonicalKey,
        "mail_app_surface": true,
        "codex_automation_decision": true,
        "sender": sender,
        "subject": subject,
        "mailbox": mailbox,
        "received_at": receivedAt,
        "projection_target": projectionTarget
    ]
    if !summary.isEmpty { metadata["summary"] = summary }
    if let suggestedAction { metadata["suggested_action"] = suggestedAction }

    let body = [
        "发件人: \(sender)",
        "主题: \(subject)",
        "邮箱: \(mailbox)",
        "收信时间: \(receivedAt)",
        summary.isEmpty ? nil : "摘要: \(summary)",
        suggestedAction.map { "建议动作: \($0)" },
        "判定依据: \(reason)"
    ].compactMap { $0 }.joined(separator: "\n")

    let needsReview = projectionTarget == "apple_reminder"
    let decision = Decision(
        domain: domain,
        priority: priority,
        risk: risk,
        needsReview: needsReview,
        action: action,
        reason: reason,
        confidence: stringField(payload, ["confidence"]) ?? "high",
        projectionTarget: projectionTarget
    )
    let signal = Signal(
        source: "apple_mail_app",
        sourceID: sourceID,
        title: "邮件: \(subject)",
        body: body,
        kind: "apple_mail_app_decision",
        occurredAt: receivedAt,
        metadata: metadata
    )
    return (signal, decision)
}

func validateExplicitMailProjectionTarget(_ projectionTarget: String, action: String) throws {
    switch projectionTarget {
    case "apple_reminder":
        guard action == "create_review_reminder" else {
            throw AppError.usage("apple_reminder mail decisions must use action=create_review_reminder.")
        }
    case "record_only":
        guard action == "record_only" else {
            throw AppError.usage("record_only mail decisions must use action=record_only.")
        }
    case "mail_action":
        guard action == "archive_low_value" else {
            throw AppError.usage("mail_action currently supports action=archive_low_value.")
        }
    default:
        throw AppError.usage("Unsupported projection_target for mail decision: \(projectionTarget)")
    }
}

func requiredString(_ payload: [String: Any], _ key: String, fallbackKeys: [String] = []) throws -> String {
    let keys = [key] + fallbackKeys
    if let value = stringField(payload, keys) {
        return value
    }
    throw AppError.usage("Mail decision input missing required field: \(key)")
}

func processSignal(_ config: AppConfig, state: StateStore, registry: RuleRegistry, signal: Signal, dryRun: Bool, noReminders: Bool) throws -> [String: Any] {
    let ingest = try state.ingest(signal)
    if !ingest.created {
        if larkStructuredSources.contains(signal.source) {
            let decision = decide(signal, registry)
            let actionResult = try executeDecision(config, state: state, signal: signal, decision: decision, dryRun: dryRun, noReminders: noReminders)
            let result: [String: Any] = [
                "signal_id": ingest.id,
                "dedupe_key": signal.dedupeKey,
                "status": "refreshed_duplicate",
                "decision": encodableDictionary(decision),
                "action_result": actionResult.dictionary
            ]
            try appendAudit(config, ["type": "refreshed_duplicate_signal"].merging(result) { _, new in new })
            return result
        }
        if !dryRun, let dryRunAttempt = try state.latestDryRunDecision(signalID: ingest.id) {
            let decisionID = try state.recordDecision(signalID: ingest.id, decision: dryRunAttempt.decision)
            let actionResult = try executeDecision(config, state: state, signal: signal, decision: dryRunAttempt.decision, dryRun: dryRun, noReminders: noReminders)
            let actionID = try state.recordAction(decisionID: decisionID, result: actionResult)
            let result: [String: Any] = [
                "signal_id": ingest.id,
                "decision_id": decisionID,
                "action_id": actionID,
                "dedupe_key": signal.dedupeKey,
                "status": "retried_dry_run",
                "decision": encodableDictionary(dryRunAttempt.decision),
                "action_result": actionResult.dictionary
            ]
            try appendAudit(config, ["type": "retried_dry_run_signal"].merging(result) { _, new in new })
            return result
        }
        if let pending = try state.pendingDecision(signalID: ingest.id) {
            let actionResult = try executeDecision(config, state: state, signal: signal, decision: pending.decision, dryRun: dryRun, noReminders: noReminders)
            let actionID = try state.recordAction(decisionID: pending.id, result: actionResult)
            let result: [String: Any] = [
                "signal_id": ingest.id,
                "decision_id": pending.id,
                "action_id": actionID,
                "dedupe_key": signal.dedupeKey,
                "status": "retried_pending",
                "decision": encodableDictionary(pending.decision),
                "action_result": actionResult.dictionary
            ]
            try appendAudit(config, ["type": "retried_pending_signal"].merging(result) { _, new in new })
            return result
        }
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
    if decision.action == "sync_projection" {
        let result = try syncStructuredProjection(config: config, state: state, signal: signal, decision: decision, noReminders: noReminders)
        return ActionResult(action: decision.action, status: "done", detail: result.detail, externalID: result.externalID)
    }
    if decision.action == "create_review_reminder", config.autoCreateReviewReminders, config.remindersEnabled, !noReminders {
        return try createReviewReminderAction(config: config, state: state, signal: signal, decision: decision)
    }
    if decision.action == "archive_low_value", config.autoArchiveLowValue {
        if signal.source == "apple_mail_app" {
            do {
                let externalID = try archiveAppleMailAppMessage(config, signal: signal)
                return ActionResult(action: decision.action, status: "done", detail: "Archived low-value Mail.app message through configured executor.", externalID: externalID)
            } catch {
                let errorText = appErrorMessage(error)
                let reviewDecision = Decision(
                    domain: decision.domain,
                    priority: "high",
                    risk: "medium",
                    needsReview: true,
                    action: "create_review_reminder",
                    reason: "archive_low_value.failed: \(errorText)",
                    confidence: "high"
                )
                if config.autoCreateReviewReminders, config.remindersEnabled, !noReminders {
                    let reviewResult = try createReviewReminderAction(config: config, state: state, signal: signal, decision: reviewDecision)
                    return ActionResult(action: decision.action, status: "needs_review", detail: "Archive failed; created review reminder. \(reviewResult.detail) Error: \(errorText)", externalID: reviewResult.externalID)
                }
                return ActionResult(action: decision.action, status: "needs_review", detail: "Archive failed; review required but Reminders were disabled for this run. Error: archive_low_value.failed: \(errorText)", externalID: nil)
            }
        }
        return ActionResult(action: decision.action, status: "done", detail: "Low-value signal archived in audit log only.", externalID: nil)
    }
    return ActionResult(action: decision.action, status: "done", detail: "Recorded without user-visible action.", externalID: nil)
}

func appErrorMessage(_ error: Error) -> String {
    if let appError = error as? AppError {
        return appError.description
    }
    return String(describing: error)
}

func createReviewReminderAction(config: AppConfig, state: StateStore, signal: Signal, decision: Decision) throws -> ActionResult {
    let canonicalKey = projectionCanonicalKey(signal)
    let listName = config.domainLists[decision.domain] ?? "WORK"
    let existing = try state.projection(for: canonicalKey)
    var externalIDs: [String] = []
    let reminderID = try upsertReminder(existingID: existing?.reminderExternalID, listName: listName, signal: signal, decision: decision)
    externalIDs.append(reminderID)
    var calendarID: String?
    var details = [existing?.reminderExternalID == nil ? "Created Reminders item in \(listName) through EventKit." : "Updated Reminders item in \(listName) through EventKit."]
    if let eventID = try upsertCalendarEventIfScheduled(config: config, existingID: existing?.calendarExternalID, signal: signal, decision: decision) {
        externalIDs.append(eventID)
        calendarID = eventID
        details.append(existing?.calendarExternalID == nil ? "Created Calendar time block through EventKit." : "Updated Calendar time block through EventKit.")
    }
    try state.recordProjection(canonicalKey: canonicalKey, reminderExternalID: reminderID, calendarExternalID: calendarID)
    return ActionResult(action: decision.action, status: "done", detail: details.joined(separator: " "), externalID: externalIDs.joined(separator: " "))
}

func syncStructuredProjection(config: AppConfig, state: StateStore, signal: Signal, decision: Decision, noReminders: Bool) throws -> (detail: String, externalID: String?) {
    let canonicalKey = projectionCanonicalKey(signal)
    let existing = try state.projection(for: canonicalKey)
    var reminderID: String?
    var calendarID: String?
    var details: [String] = []

    if signal.source == "lark_calendar_events" {
        if isEventKitAuthorized(EKEventStore.authorizationStatus(for: .event), for: .event) {
            calendarID = try upsertCalendarEventIfScheduled(config: config, existingID: existing?.calendarExternalID, signal: signal, decision: decision)
            details.append(existing?.calendarExternalID == nil ? "Created Calendar event from Lark through EventKit." : "Updated Calendar event from Lark through EventKit.")
        } else {
            details.append("Skipped Calendar event because EventKit Calendar is not authorized for this process.")
        }
    } else if signal.source == "lark_tasks" {
        if !noReminders, config.remindersEnabled, isEventKitAuthorized(EKEventStore.authorizationStatus(for: .reminder), for: .reminder) {
            let listName = config.domainLists[decision.domain] ?? "WORK"
            reminderID = try upsertReminder(existingID: existing?.reminderExternalID, listName: listName, signal: signal, decision: decision)
            details.append(existing?.reminderExternalID == nil ? "Created Reminders item from Lark task through EventKit." : "Updated Reminders item from Lark task through EventKit.")
        } else {
            details.append("Skipped Reminders item because reminders are disabled or EventKit Reminders is not authorized for this process.")
        }
    } else {
        throw AppError.runtime("sync_projection is not supported for source: \(signal.source)")
    }

    try state.recordProjection(canonicalKey: canonicalKey, reminderExternalID: reminderID, calendarExternalID: calendarID)
    let externalID = [reminderID, calendarID].compactMap { $0 }.joined(separator: " ")
    return (details.joined(separator: " "), externalID.isEmpty ? nil : externalID)
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
    [record.reminderExternalID, record.calendarExternalID, record.larkTaskURL, record.larkTaskGUID.map { "lark-task://\($0)" }]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
}

func upsertReminder(existingID: String?, listName: String, signal: Signal, decision: Decision) throws -> String {
    try requireEventKitAuthorization(for: .reminder, operation: "sync Apple Reminders item")
    let store = sharedEventStoreBox.store
    let reminder = eventKitItem(existingID, store: store) as? EKReminder ?? EKReminder(eventStore: store)
    reminder.title = signal.title
    reminder.notes = reminderBody(signal: signal, decision: decision)
    if reminder.calendar == nil {
        reminder.calendar = try findReminderCalendar(named: listName, store: store)
    }
    reminder.priority = reminderPriority(decision.priority)
    let fallbackDue = decision.action == "create_review_reminder" ? reminderDueDate(decision.risk, decision.priority) : nil
    if let due = signalMetadataDate(signal, keys: ["due_date", "dueDate"]) ?? fallbackDue {
        reminder.dueDateComponents = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: due)
    } else {
        reminder.dueDateComponents = nil
    }
    try store.save(reminder, commit: true)
    return "x-apple-reminder://\(reminder.calendarItemIdentifier)"
}

func upsertCalendarEventIfScheduled(config: AppConfig, existingID: String?, signal: Signal, decision: Decision) throws -> String? {
    guard let start = signalMetadataDate(signal, keys: ["calendar_start", "start", "start_at"]),
          let end = signalMetadataDate(signal, keys: ["calendar_end", "end", "end_at"]) ?? Calendar.current.date(byAdding: .minute, value: 30, to: start)
    else {
        return nil
    }
    try requireEventKitAuthorization(for: .event, operation: "sync Apple Calendar time block")
    let store = sharedEventStoreBox.store
    let calendar = try findEventCalendar(named: calendarName(for: decision.domain, config: config), store: store)
    let event = eventKitItem(existingID, store: store) as? EKEvent ?? EKEvent(eventStore: store)
    event.title = signal.title
    event.notes = calendarNotes(signal: signal, decision: decision)
    event.url = calendarURL(signal)
    event.startDate = start
    event.endDate = max(end, start.addingTimeInterval(60))
    if event.calendar == nil || event.calendar.calendarIdentifier != calendar.calendarIdentifier {
        event.calendar = calendar
    }
    try store.save(event, span: .thisEvent, commit: true)
    return "x-apple-calendar://\(event.calendarItemIdentifier)"
}

func calendarName(for domain: String, config: AppConfig) -> String {
    config.calendarDomainCalendars[domain] ?? domain.uppercased()
}

func findEventCalendar(named name: String, store: EKEventStore) throws -> EKCalendar {
    if let found = store.calendars(for: .event).first(where: { $0.title == name && $0.allowsContentModifications }) {
        return found
    }
    guard let source = store.defaultCalendarForNewEvents?.source ?? store.sources.first(where: { $0.sourceType == .local }) ?? store.sources.first else {
        throw AppError.runtime("No Calendar source available for \(name).")
    }
    let calendar = EKCalendar(for: .event, eventStore: store)
    calendar.title = name
    calendar.source = source
    try store.saveCalendar(calendar, commit: true)
    return calendar
}

func eventKitItem(_ externalID: String?, store: EKEventStore) -> EKCalendarItem? {
    guard let externalID, !externalID.isEmpty else { return nil }
    let identifier = externalID
        .replacingOccurrences(of: "x-apple-reminder://", with: "")
        .replacingOccurrences(of: "x-apple-calendar://", with: "")
    return store.calendarItem(withIdentifier: identifier)
}

func calendarNotes(signal: Signal, decision: Decision) -> String? {
    for key in ["description", "notes", "content"] {
        if let value = signal.metadata[key] as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
    }
    let trimmed = signal.body.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

func calendarURL(_ signal: Signal) -> URL? {
    guard let raw = signal.metadata["url"] as? String else {
        return nil
    }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }
    return URL(string: trimmed)
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
        "- lark_calendar_events 通过 lark-cli 用户身份只读飞书日程，并只把结构化字段交给 EventKit 投影。",
        "- lark_tasks 通过 lark-cli 用户身份只读飞书任务，并只把结构化字段交给 EventKit 投影。",
        "- google_calendar_events、google_tasks 和 google_contacts 通过 Google 官方 API 只读采集；本验收不写 Apple Calendar、Reminders 或 Contacts。",
        "- 正式 Google 同步只会删除 Smart Shadow sync_mappings 中已有映射的 Apple 对象，不按标题或内容删除用户原有 iCloud 数据。",
        "- chrome_bookmarks 只读取 Chrome 书签元数据；网页内容、历史记录、Cookies 和登录态默认未读取。",
        "- apple_mail_summary 读取配置指定的本地邮件摘要 JSON，用于离线回放和规则验收。",
        "- Mail.app 真实邮件由 Codex Automation 感知和判断；Smart Shadow 只通过 project-mail-decision 接收显式投影决策。",
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

struct ShadowDProjectIssue {
    let itemID: String?
    let projectID: String?
    let statusFieldID: String?
    let doneOptionID: String?
    let repo: String
    let number: Int
    let title: String
    let body: String
    let url: String
    let state: String
    let projectStatus: String?
    let customStatus: String?
    let labels: [String]
}

struct ShadowDGitHubRepoConfig {
    let localPath: String
    let defaultBase: String
    let allowedSenders: [String]
    let testCommand: String?
    let codexSandbox: String
}

struct ShadowDGitHubIssueTask {
    let agentName: String
    let daemonName: String
    let trigger: String
    let repoFullName: String
    let owner: String
    let repo: String
    let issueNumber: Int
    let issueTitle: String
    let issueBody: String
    let issueURL: String
    let sender: String
    let command: String?
    let labels: [String]
    let assignees: [String]
}

func handleShadowDCommand(_ config: AppConfig, arguments: [String]) throws -> [String: Any] {
    let subcommand = arguments.first ?? "once"
    let rest = Array(arguments.dropFirst())
    let dryRun = rest.contains("--dry-run") || subcommand == "inspect-issue"
    switch subcommand {
    case "once":
        return try shadowDRunOnce(config: config, arguments: rest, dryRun: dryRun)
    case "run":
        try appendAudit(config, ["type": "shadowd_started", "mode": "github_project_reconciler"])
        while true {
            do {
                _ = try shadowDRunOnce(config: config, arguments: rest, dryRun: false)
            } catch {
                try? writeDaemonErrorReport(config, error: error)
                try? appendAudit(config, ["type": "shadowd_run_error", "error": "\(error)"])
                fputs("shadowd: reconciler run failed: \(error)\n", stderr)
            }
            sleep(config.pollSeconds)
        }
    case "github-issue":
        return try shadowDHandleGitHubIssue(config: config, arguments: rest, dryRun: dryRun || !rest.contains("--write"))
    case "inspect-issue":
        return try shadowDInspectIssue(config: config, arguments: rest)
    default:
        throw AppError.usage("Unsupported shadowd command: \(subcommand)")
    }
}

func shadowDRunOnce(config: AppConfig, arguments: [String], dryRun: Bool) throws -> [String: Any] {
    let source = try loadShadowDProjectIssues(arguments: arguments)
    let allowWrites = arguments.contains("--write-comments")
    let effectiveDryRun = dryRun || !allowWrites
    let results = try source.items.map { try shadowDReconcile(issue: $0, dryRun: effectiveDryRun) }
    let actionCount = results.filter { ($0["action"] as? String) != "no_op" }.count
    let output: [String: Any] = [
        "status": effectiveDryRun ? "dry_run" : "ok",
        "mode": "github_project_reconciler",
        "source_of_truth": "github_project_issue_pr",
        "local_task_db": false,
        "github_writes_enabled": allowWrites,
        "scope": [
            "owner": source.owner,
            "project_number": source.projectNumber,
            "repo_filter": source.repoFilter as Any? ?? NSNull(),
            "requires_smartshadow_label": false
        ],
        "item_count": source.items.count,
        "action_count": actionCount,
        "results": results
    ]
    try appendAudit(config, [
        "type": "shadowd_reconcile",
        "dry_run": effectiveDryRun,
        "github_writes_enabled": allowWrites,
        "item_count": source.items.count,
        "action_count": actionCount
    ])
    return output
}

func shadowDInspectIssue(config: AppConfig, arguments: [String]) throws -> [String: Any] {
    let source = try loadShadowDProjectIssues(arguments: arguments)
    let issueNumber = Int(optionValue(arguments, "--issue") ?? "")
    let issue = issueNumber.flatMap { number in source.items.first(where: { $0.number == number }) } ?? source.items.first
    guard let issue else { throw AppError.runtime("No issue found to inspect.") }
    let plan = try shadowDReconcile(issue: issue, dryRun: true)
    return [
        "status": "ok",
        "mode": "inspect",
        "issue": shadowDIssueSummary(issue),
        "planned_result": plan,
        "local_task_db": false
    ] as [String: Any]
}

func shadowDReconcile(issue: ShadowDProjectIssue, dryRun: Bool) throws -> [String: Any] {
    let summary = shadowDIssueSummary(issue)
    if issue.state.lowercased() != "open" {
        return try shadowDResult(issue: issue, action: "no_op", reason: "issue_not_open", dryRun: dryRun, command: nil, comment: nil, extra: ["issue": summary])
    }
    if let smartShadowIssue = SmartShadowIssueParser.parse(SmartShadowIssueEnvelope(title: issue.title, labels: issue.labels, body: issue.body)) {
        if !smartShadowIssue.isFinalTextTask {
            let comment = """
            Smart Shadow no longer processes raw audio in shadowd.

            Please replace this legacy voice packet with the final user-confirmed task text first. Keep the task description at the top, remove audio paths and raw transcript dumps, and keep only compact Smart Shadow metadata.
            """
            return try shadowDResult(issue: issue, action: "comment_question", reason: "legacy_voice_audio_needs_final_text", dryRun: dryRun, command: shadowDCommentCommand(issue: issue, body: comment), comment: comment, extra: ["issue": summary])
        }

        let transition = IssueStateMachine.transition(
            labels: issue.labels,
            to: .triaging,
            comment: "已接收任务，正在拆解。"
        )
        return try shadowDResult(
            issue: issue,
            action: "transition_issue_state",
            reason: "smart_shadow_text_issue_ready_for_triage",
            dryRun: dryRun,
            command: nil,
            comment: transition.comment,
            extra: [
                "issue": summary,
                "from_label": transition.from?.rawValue ?? NSNull(),
                "to_label": transition.to.rawValue,
                "labels": transition.labels,
                "input": smartShadowIssue.input ?? NSNull(),
                "audio": smartShadowIssue.audio ?? NSNull()
            ]
        )
    }
    if shadowDIsVoiceIssue(issue) {
        if shadowDHasLegacyVoicePayload(issue.body) {
            let comment = """
            Smart Shadow no longer processes raw audio in shadowd.

            Please replace this legacy voice packet with the final user-confirmed task text first. Keep the task description at the top, remove audio paths and raw transcript dumps, and keep only compact Smart Shadow metadata.
            """
            return try shadowDResult(issue: issue, action: "comment_question", reason: "legacy_voice_audio_needs_final_text", dryRun: dryRun, command: shadowDCommentCommand(issue: issue, body: comment), comment: comment, extra: ["issue": summary])
        }
        return try shadowDResult(issue: issue, action: "no_op", reason: "smart_shadow_text_issue_ready", dryRun: dryRun, command: nil, comment: nil, extra: ["issue": summary])
    }
    if shadowDIsDoneish(issue.customStatus), !shadowDIsDoneish(issue.projectStatus) {
        let intent = shadowDProjectStatusCommand(issue: issue, status: "Done")
        return try shadowDResult(issue: issue, action: "update_project_status", reason: "custom_status_done_project_status_not_done", dryRun: true, command: intent, comment: nil, extra: ["issue": summary])
    }
    if !shadowDHasIssueTemplateEssentials(issue.body) {
        let comment = """
        ShadowD cannot safely start this issue yet because the issue body is missing the required task template sections.

        Please fill in Background, Goal, Scope, Acceptance Criteria, Constraints, Suggested Starting Points, and Agent Instructions.
        """
        return try shadowDResult(issue: issue, action: "comment_question", reason: "missing_issue_template_sections", dryRun: dryRun, command: shadowDCommentCommand(issue: issue, body: comment), comment: comment, extra: ["issue": summary])
    }
    return try shadowDResult(issue: issue, action: "no_op", reason: "github_state_already_consistent", dryRun: dryRun, command: nil, comment: nil, extra: ["issue": summary])
}

func shadowDResult(issue: ShadowDProjectIssue, action: String, reason: String, dryRun: Bool, command: [String]?, comment: String?, extra: [String: Any]) throws -> [String: Any] {
    var result = extra
    result["action"] = action
    result["reason"] = reason
    result["dry_run"] = dryRun
    if let command { result["argv"] = command; result["command"] = command.joined(separator: " ") }
    if let comment { result["comment"] = comment }
    if !dryRun, let command, action == "comment_question" {
        let shell = try shellResult(command)
        result["gh_exit_status"] = shell.status
        result["gh_output"] = shell.output
        if shell.status != 0 {
            throw AppError.runtime("GitHub comment failed: \(shell.output)")
        }
    }
    return result
}

func shadowDIssueSummary(_ issue: ShadowDProjectIssue) -> [String: Any] {
    [
        "item_id": issue.itemID ?? NSNull(),
        "repo": issue.repo,
        "number": issue.number,
        "title": issue.title,
        "url": issue.url,
        "state": issue.state,
        "project_status": issue.projectStatus ?? NSNull(),
        "custom_status": issue.customStatus ?? NSNull(),
        "labels": issue.labels,
        "voice_issue": shadowDIsVoiceIssue(issue)
    ] as [String: Any]
}

func shadowDIsVoiceIssue(_ issue: ShadowDProjectIssue) -> Bool {
    let body = issue.body.lowercased()
    return body.contains("\"audio_path\"") || body.contains("smart shadow metadata") || issue.labels.contains(where: { shadowDNormalizeStatus($0) == "voice" })
}

func shadowDHasRawTranscript(_ body: String) -> Bool {
    body.range(of: "Raw Transcript", options: [.caseInsensitive]) != nil
}

func shadowDHasLegacyVoicePayload(_ body: String) -> Bool {
    let lowercased = body.lowercased()
    return lowercased.contains("\"audio_path\"")
        || lowercased.contains("audio_file")
        || lowercased.contains(".m4a")
        || lowercased.contains("raw transcript")
}

func shadowDHasIssueTemplateEssentials(_ body: String) -> Bool {
    let required = ["## Background", "## Goal", "## Scope", "## Acceptance Criteria", "## Constraints", "## Suggested Starting Points", "## Agent Instructions"]
    return required.allSatisfy { body.range(of: $0, options: [.caseInsensitive]) != nil }
}

func shadowDIsDoneish(_ value: String?) -> Bool {
    guard let value else { return false }
    return ["done", "completed", "complete", "closed", "完成"].contains(shadowDNormalizeStatus(value))
}

func shadowDNormalizeStatus(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "ss/state:", with: "")
        .replacingOccurrences(of: "status:", with: "")
        .replacingOccurrences(of: "_", with: "-")
}

func shadowDCommentCommand(issue: ShadowDProjectIssue, body: String) -> [String] {
    ["gh", "issue", "comment", "\(issue.number)", "--repo", issue.repo, "--body", body]
}

func shadowDProjectStatusCommand(issue: ShadowDProjectIssue, status: String) -> [String] {
    var command = ["gh", "project", "item-edit"]
    if let projectID = issue.projectID { command += ["--project-id", projectID] }
    if let itemID = issue.itemID { command += ["--id", itemID] }
    if let fieldID = issue.statusFieldID { command += ["--field-id", fieldID] }
    if let doneOptionID = issue.doneOptionID { command += ["--single-select-option-id", doneOptionID] }
    command += ["# desired-status=\(status)"]
    return command
}

struct ShadowDProjectIssueSource {
    let owner: String
    let projectNumber: Int
    let repoFilter: String?
    let items: [ShadowDProjectIssue]
}

func loadShadowDProjectIssues(arguments: [String]) throws -> ShadowDProjectIssueSource {
    let owner = optionValue(arguments, "--owner") ?? "longbiaochen"
    let projectNumber = Int(optionValue(arguments, "--project") ?? "1") ?? 1
    let repoFilter = optionValue(arguments, "--repo") ?? "longbiaochen/life-os"
    if let fixture = optionValue(arguments, "--fixture") {
        let data = try Data(contentsOf: URL(fileURLWithPath: fixture))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError.runtime("ShadowD fixture must be a JSON object.")
        }
        return ShadowDProjectIssueSource(owner: owner, projectNumber: projectNumber, repoFilter: repoFilter, items: shadowDParseProjectIssues(json, repoFilter: repoFilter))
    }
    let query = """
    query($login: String!, $number: Int!) {
      user(login: $login) {
        projectV2(number: $number) {
          id
          fields(first: 50) {
            nodes {
              ... on ProjectV2SingleSelectField {
                id
                name
                options { id name }
              }
            }
          }
          items(first: 100) {
            nodes {
              id
              fieldValues(first: 30) {
                nodes {
                  ... on ProjectV2ItemFieldSingleSelectValue {
                    name
                    field { ... on ProjectV2SingleSelectField { id name } }
                  }
                }
              }
              content {
                ... on Issue {
                  number
                  title
                  body
                  url
                  state
                  repository { nameWithOwner }
                  labels(first: 30) { nodes { name } }
                }
              }
            }
          }
        }
      }
    }
    """
    let shell = try shellResult(["gh", "api", "graphql", "-f", "query=\(query)", "-f", "login=\(owner)", "-F", "number=\(projectNumber)"], timeoutSeconds: 20)
    guard shell.status == 0 else {
        throw AppError.runtime("GitHub Project query failed or timed out: \(shell.output)")
    }
    let raw = shell.output
    let data = Data(raw.utf8)
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw AppError.runtime("Unable to parse GitHub Project response.")
    }
    return ShadowDProjectIssueSource(owner: owner, projectNumber: projectNumber, repoFilter: repoFilter, items: shadowDParseProjectIssues(json, repoFilter: repoFilter))
}

func shadowDParseProjectIssues(_ json: [String: Any], repoFilter: String?) -> [ShadowDProjectIssue] {
    if let items = json["items"] as? [[String: Any]] {
        return items.compactMap { shadowDParseFixtureIssue($0, repoFilter: repoFilter) }
    }
    guard
        let data = json["data"] as? [String: Any],
        let user = data["user"] as? [String: Any],
        let project = user["projectV2"] as? [String: Any],
        let itemContainer = project["items"] as? [String: Any],
        let nodes = itemContainer["nodes"] as? [[String: Any]]
    else { return [] }
    let projectID = project["id"] as? String
    let statusInfo = shadowDProjectStatusField(project)
    return nodes.compactMap { node -> ShadowDProjectIssue? in
        guard
            let content = node["content"] as? [String: Any],
            let number = content["number"] as? Int,
            let repository = content["repository"] as? [String: Any],
            let repo = repository["nameWithOwner"] as? String
        else { return nil }
        if let repoFilter, repo != repoFilter { return nil }
        let labels = (((content["labels"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
        let statuses = shadowDProjectStatuses(node)
        return ShadowDProjectIssue(
            itemID: node["id"] as? String,
            projectID: projectID,
            statusFieldID: statusInfo.fieldID,
            doneOptionID: statusInfo.doneOptionID,
            repo: repo,
            number: number,
            title: content["title"] as? String ?? "",
            body: content["body"] as? String ?? "",
            url: content["url"] as? String ?? "",
            state: content["state"] as? String ?? "OPEN",
            projectStatus: statuses.projectStatus,
            customStatus: statuses.customStatus,
            labels: labels
        )
    }
}

func shadowDParseFixtureIssue(_ item: [String: Any], repoFilter: String?) -> ShadowDProjectIssue? {
    let repo = item["repo"] as? String ?? item["repository"] as? String ?? "longbiaochen/life-os"
    if let repoFilter, repo != repoFilter { return nil }
    guard let number = item["number"] as? Int ?? Int(item["number"] as? String ?? "") else { return nil }
    return ShadowDProjectIssue(
        itemID: item["item_id"] as? String,
        projectID: item["project_id"] as? String,
        statusFieldID: item["status_field_id"] as? String,
        doneOptionID: item["done_option_id"] as? String,
        repo: repo,
        number: number,
        title: item["title"] as? String ?? "",
        body: item["body"] as? String ?? "",
        url: item["url"] as? String ?? "https://github.com/\(repo)/issues/\(number)",
        state: item["state"] as? String ?? "OPEN",
        projectStatus: item["project_status"] as? String,
        customStatus: item["custom_status"] as? String,
        labels: item["labels"] as? [String] ?? []
    )
}

func shadowDProjectStatuses(_ node: [String: Any]) -> (projectStatus: String?, customStatus: String?) {
    let values = (((node["fieldValues"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? [])
    var projectStatus: String?
    var customStatus: String?
    for value in values {
        guard let name = value["name"] as? String else { continue }
        let fieldName = ((value["field"] as? [String: Any])?["name"] as? String) ?? ""
        if fieldName.caseInsensitiveCompare("Status") == .orderedSame {
            projectStatus = name
        } else if fieldName.localizedCaseInsensitiveContains("custom") || fieldName.localizedCaseInsensitiveContains("状态") {
            customStatus = name
        }
    }
    return (projectStatus, customStatus)
}

func shadowDProjectStatusField(_ project: [String: Any]) -> (fieldID: String?, doneOptionID: String?) {
    let fields = (((project["fields"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? [])
    for field in fields where (field["name"] as? String)?.caseInsensitiveCompare("Status") == .orderedSame {
        let options = field["options"] as? [[String: Any]] ?? []
        let done = options.first { shadowDIsDoneish($0["name"] as? String) }
        return (field["id"] as? String, done?["id"] as? String)
    }
    return (nil, nil)
}

func shadowDHandleGitHubIssue(config: AppConfig, arguments: [String], dryRun: Bool) throws -> [String: Any] {
    let payloadPath = try requiredOption(arguments, "--payload")
    let eventName = optionValue(arguments, "--event") ?? "issues"
    let deliveryID = optionValue(arguments, "--delivery") ?? "local-\(Int(Date().timeIntervalSince1970))"
    let data = try Data(contentsOf: URL(fileURLWithPath: payloadPath))
    guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw AppError.runtime("GitHub issue payload must be a JSON object.")
    }
    let route = try shadowDNormalizeGitHubIssuePayload(config: config, eventName: eventName, deliveryID: deliveryID, payload: payload)
    guard route.allowed, let task = route.task else {
        return [
            "status": "ignored",
            "mode": "github_issue_workflow",
            "reason": route.reason,
            "delivery_id": deliveryID
        ] as [String: Any]
    }
    let result = try shadowDRunGitHubIssueWorkflow(config: config, task: task, dryRun: dryRun)
    try appendAudit(config, [
        "type": "shadowd_github_issue",
        "dry_run": dryRun,
        "repo": task.repoFullName,
        "issue": task.issueNumber,
        "trigger": task.trigger,
        "status": result["status"] as? String ?? "unknown"
    ])
    return result
}

func shadowDNormalizeGitHubIssuePayload(config: AppConfig, eventName: String, deliveryID: String, payload: [String: Any]) throws -> (allowed: Bool, reason: String, task: ShadowDGitHubIssueTask?) {
    let github = config.raw["github"] as? [String: Any] ?? [:]
    let enabled = github["enabled"] as? Bool ?? false
    guard enabled else { return (false, "github_disabled", nil) }
    let allowedEvents = github["events"] as? [String] ?? ["issues", "issue_comment"]
    guard allowedEvents.contains(eventName) else { return (false, "event_not_allowed", nil) }
    guard
        let repository = payload["repository"] as? [String: Any],
        let repoFullName = repository["full_name"] as? String
    else { return (false, "repository_missing", nil) }
    guard let repoConfig = shadowDGitHubRepoConfig(config: config, repoFullName: repoFullName) else {
        return (false, "repository_mapping_missing", nil)
    }
    let action = payload["action"] as? String ?? ""
    let sender = ((payload["sender"] as? [String: Any])?["login"] as? String) ?? "unknown"
    if !repoConfig.allowedSenders.isEmpty, !repoConfig.allowedSenders.contains(sender) {
        return (false, "sender_not_allowed", nil)
    }
    guard let issue = payload["issue"] as? [String: Any] else {
        return (false, "issue_missing", nil)
    }
    guard (issue["pull_request"] as? [String: Any]) == nil else {
        return (false, "github_item_not_issue", nil)
    }
    guard let issueNumber = issue["number"] as? Int else {
        return (false, "issue_number_missing", nil)
    }
    let assignee = ((payload["assignee"] as? [String: Any])?["login"] as? String)
    let assignees = shadowDGitHubLogins(issue["assignees"])
    let command = shadowDGitHubCommentCommand((payload["comment"] as? [String: Any])?["body"] as? String)
    let configuredAssignee = github["assignee"] as? String ?? "shadow"
    let allowedCommands = github["allowedCommentCommands"] as? [String] ?? ["@shadow", "@shadow fix", "@shadow continue", "@shadow test", "@shadow explain"]
    let trigger: String
    if eventName == "issues", action == "assigned" {
        let actual = assignee ?? assignees.last
        guard actual?.lowercased() == configuredAssignee.lowercased() else {
            return (false, "assignee_not_shadow", nil)
        }
        trigger = "assigned"
    } else if eventName == "issue_comment", action == "created" {
        guard let command else { return (false, "comment_command_not_matched", nil) }
        guard allowedCommands.contains(command) else { return (false, "comment_command_not_allowed", nil) }
        trigger = "comment"
    } else {
        return (false, "trigger_not_matched", nil)
    }
    let parts = repoFullName.split(separator: "/", maxSplits: 1).map(String.init)
    let task = ShadowDGitHubIssueTask(
        agentName: github["agentName"] as? String ?? "shadow",
        daemonName: github["daemonName"] as? String ?? "shadowd",
        trigger: trigger,
        repoFullName: repoFullName,
        owner: parts.first ?? "unknown",
        repo: parts.count > 1 ? parts[1] : "unknown",
        issueNumber: issueNumber,
        issueTitle: issue["title"] as? String ?? "Issue #\(issueNumber)",
        issueBody: issue["body"] as? String ?? "",
        issueURL: issue["html_url"] as? String ?? "https://github.com/\(repoFullName)/issues/\(issueNumber)",
        sender: sender,
        command: command,
        labels: shadowDGitHubLabelNames(issue["labels"]),
        assignees: assignees
    )
    _ = deliveryID
    return (true, "matched", task)
}

func shadowDGitHubRepoConfig(config: AppConfig, repoFullName: String) -> ShadowDGitHubRepoConfig? {
    let github = config.raw["github"] as? [String: Any] ?? [:]
    let repos = github["repos"] as? [String: Any] ?? [:]
    guard let repo = repos[repoFullName] as? [String: Any] else { return nil }
    return ShadowDGitHubRepoConfig(
        localPath: absolutePath(repo["localPath"] as? String ?? repo["local_path"] as? String ?? config.projectRoot, base: config.projectRoot),
        defaultBase: repo["defaultBase"] as? String ?? repo["default_base"] as? String ?? "main",
        allowedSenders: repo["allowedSenders"] as? [String] ?? repo["allowed_senders"] as? [String] ?? [],
        testCommand: repo["testCommand"] as? String ?? repo["test_command"] as? String,
        codexSandbox: repo["codexSandbox"] as? String ?? repo["codex_sandbox"] as? String ?? "workspace-write"
    )
}

func shadowDRunGitHubIssueWorkflow(config: AppConfig, task: ShadowDGitHubIssueTask, dryRun: Bool) throws -> [String: Any] {
    guard let repoConfig = shadowDGitHubRepoConfig(config: config, repoFullName: task.repoFullName) else {
        throw AppError.runtime("No GitHub repo mapping configured for \(task.repoFullName).")
    }
    let branch = shadowDBranchName(issueNumber: task.issueNumber, title: task.issueTitle)
    let lockPath = shadowDLockPath(config: config, task: task)
    let logLines = NSMutableArray()
    if FileManager.default.fileExists(atPath: lockPath) {
        return [
            "status": "locked",
            "mode": "github_issue_workflow",
            "repo": task.repoFullName,
            "issue": task.issueNumber,
            "branch": branch,
            "reason": "task_already_running"
        ] as [String: Any]
    }
    try FileManager.default.createDirectory(atPath: URL(fileURLWithPath: lockPath).deletingLastPathComponent().path, withIntermediateDirectories: true)
    try "running \(nowISO())\n".write(toFile: lockPath, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(atPath: lockPath) }
    do {
        try shadowDGitHubComment(task: task, body: shadowDStatusAccepted(task), dryRun: dryRun)
        try shadowDGitHubComment(task: task, body: shadowDStatusRunning(task, branch: branch), dryRun: dryRun)
        try shadowDRunChecked(["git", "fetch", "origin"], cwd: repoConfig.localPath, dryRun: dryRun, logLines: logLines)
        try shadowDRunChecked(["git", "checkout", repoConfig.defaultBase], cwd: repoConfig.localPath, dryRun: dryRun, logLines: logLines)
        try shadowDRunChecked(["git", "pull", "--ff-only", "origin", repoConfig.defaultBase], cwd: repoConfig.localPath, dryRun: dryRun, logLines: logLines)
        try shadowDRunChecked(["git", "checkout", "-B", branch], cwd: repoConfig.localPath, dryRun: dryRun, logLines: logLines)
        let comments = try shadowDFetchIssueComments(task: task, cwd: repoConfig.localPath, dryRun: dryRun)
        let prompt = shadowDGitHubPrompt(task: task, comments: comments)
        let codex = try shadowDRunCommand(["codex", "exec", "--sandbox", repoConfig.codexSandbox, prompt], cwd: repoConfig.localPath, dryRun: dryRun, timeoutSeconds: 900)
        logLines.add("codex exit=\(codex.status)\n\(codex.output)")
        if codex.status != 0 { throw AppError.runtime("codex exec failed: \(shadowDSummarize(codex.output, maxLength: 600))") }
        var tests = "not configured"
        if let testCommand = repoConfig.testCommand, !testCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let argv = shadowDSplitTrustedCommand(testCommand)
            let test = try shadowDRunCommand(argv, cwd: repoConfig.localPath, dryRun: dryRun, timeoutSeconds: 900)
            logLines.add("tests exit=\(test.status)\n\(test.output)")
            tests = test.status == 0 ? "passed: \(testCommand)" : "failed: \(testCommand)\n\(shadowDSummarize(test.output, maxLength: 600))"
            if test.status != 0 { throw AppError.runtime(tests) }
        }
        let status = try shadowDRunCommand(["git", "status", "--porcelain"], cwd: repoConfig.localPath, dryRun: dryRun, timeoutSeconds: 30)
        logLines.add("git status\n\(status.output)")
        let summary = shadowDSummarize(codex.output.isEmpty ? "shadow completed the requested issue workflow." : codex.output)
        if status.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let logPath = try shadowDWriteIssueLog(config: config, task: task, lines: logLines)
            try shadowDGitHubComment(task: task, body: shadowDStatusNoChanges(task, summary: summary), dryRun: dryRun)
            return ["status": "no_changes", "mode": "github_issue_workflow", "repo": task.repoFullName, "issue": task.issueNumber, "branch": branch, "log_path": logPath] as [String: Any]
        }
        try shadowDRunChecked(["git", "add", "-A"], cwd: repoConfig.localPath, dryRun: dryRun, logLines: logLines)
        try shadowDRunChecked(["git", "commit", "-m", "Fix issue #\(task.issueNumber) via shadow"], cwd: repoConfig.localPath, dryRun: dryRun, logLines: logLines)
        try shadowDRunChecked(["git", "push", "-u", "origin", branch], cwd: repoConfig.localPath, dryRun: dryRun, logLines: logLines)
        let prBody = shadowDPRBody(task: task, summary: summary, tests: tests)
        let pr = try shadowDRunCommand(["gh", "pr", "create", "--repo", task.repoFullName, "--base", repoConfig.defaultBase, "--head", branch, "--title", "[shadow] \(task.issueTitle)", "--body", prBody], cwd: repoConfig.localPath, dryRun: dryRun, timeoutSeconds: 120)
        logLines.add("pr\n\(pr.output)")
        let prURL = shadowDExtractURL(pr.output) ?? "(dry-run PR URL unavailable)"
        let logPath = try shadowDWriteIssueLog(config: config, task: task, lines: logLines)
        try shadowDGitHubComment(task: task, body: shadowDStatusPR(task, prURL: prURL, summary: summary, tests: tests), dryRun: dryRun)
        return ["status": "pr_created", "mode": "github_issue_workflow", "repo": task.repoFullName, "issue": task.issueNumber, "branch": branch, "pr_url": prURL, "log_path": logPath] as [String: Any]
    } catch {
        let logPath = try? shadowDWriteIssueLog(config: config, task: task, lines: logLines)
        try? shadowDGitHubComment(task: task, body: shadowDStatusFailed(task, branch: branch, error: "\(error)"), dryRun: dryRun)
        throw AppError.runtime("GitHub issue workflow failed: \(error). log=\(logPath ?? "(none)")")
    }
}

func shadowDGitHubLabelNames(_ value: Any?) -> [String] {
    (value as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
}

func shadowDGitHubLogins(_ value: Any?) -> [String] {
    (value as? [[String: Any]] ?? []).compactMap { $0["login"] as? String }
}

func shadowDGitHubCommentCommand(_ body: String?) -> String? {
    let first = (body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).first ?? ""
    let pattern = #"^@shadow(?:\s+(fix|continue|test|explain))?(?:\s|$)"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
    let range = NSRange(first.startIndex..<first.endIndex, in: first)
    guard let match = regex.firstMatch(in: first, range: range) else { return nil }
    if match.numberOfRanges > 1, let subrange = Range(match.range(at: 1), in: first) {
        return "@shadow \(first[subrange].lowercased())"
    }
    return "@shadow"
}

func shadowDBranchName(issueNumber: Int, title: String) -> String {
    let slug = title.lowercased()
        .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    let limited = String(slug.prefix(60)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return "shadow/issue-\(issueNumber)-\(limited.isEmpty ? "issue" : limited)"
}

func shadowDLockPath(config: AppConfig, task: ShadowDGitHubIssueTask) -> String {
    let safe = "\(task.repoFullName)-\(task.issueNumber)".replacingOccurrences(of: #"[^A-Za-z0-9_.-]+"#, with: "-", options: .regularExpression)
    return "\(config.runtimeRoot)/locks/github-\(safe).lock"
}

func shadowDFetchIssueComments(task: ShadowDGitHubIssueTask, cwd: String, dryRun: Bool) throws -> String {
    if dryRun { return "(dry-run: comments not fetched)" }
    let result = try shadowDRunCommand(["gh", "api", "/repos/\(task.repoFullName)/issues/\(task.issueNumber)/comments", "--jq", ".[-8:] | map(.user.login + \": \" + .body) | .[]"], cwd: cwd, dryRun: false, timeoutSeconds: 60)
    return result.status == 0 ? result.output : ""
}

func shadowDRunChecked(_ argv: [String], cwd: String, dryRun: Bool, logLines: NSMutableArray) throws {
    let result = try shadowDRunCommand(argv, cwd: cwd, dryRun: dryRun, timeoutSeconds: 120)
    logLines.add("$ \(argv.joined(separator: " "))\nexit=\(result.status)\n\(result.output)")
    if result.status != 0 {
        throw AppError.runtime("\(argv.joined(separator: " ")) failed: \(shadowDSummarize(result.output, maxLength: 600))")
    }
}

func shadowDRunCommand(_ argv: [String], cwd: String, dryRun: Bool, timeoutSeconds: TimeInterval) throws -> (status: Int32, output: String) {
    if dryRun {
        if argv.first == "git", argv.dropFirst().joined(separator: " ") == "status --porcelain" {
            return (0, "")
        }
        return (0, "[dry-run] \(argv.joined(separator: " "))")
    }
    let previous = FileManager.default.currentDirectoryPath
    FileManager.default.changeCurrentDirectoryPath(cwd)
    defer { FileManager.default.changeCurrentDirectoryPath(previous) }
    return try shellResult(argv, timeoutSeconds: timeoutSeconds)
}

func shadowDGitHubComment(task: ShadowDGitHubIssueTask, body: String, dryRun: Bool) throws {
    let argv = ["gh", "issue", "comment", "\(task.issueNumber)", "--repo", task.repoFullName, "--body", body]
    if dryRun { return }
    let result = try shellResult(argv, timeoutSeconds: 60)
    if result.status != 0 { throw AppError.runtime("GitHub comment failed: \(result.output)") }
}

func shadowDWriteIssueLog(config: AppConfig, task: ShadowDGitHubIssueTask, lines: NSMutableArray) throws -> String {
    let dir = "\(config.runtimeRoot)/logs/github-issue-workflow"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let safe = "\(task.repoFullName)-\(task.issueNumber)".replacingOccurrences(of: #"[^A-Za-z0-9_.-]+"#, with: "-", options: .regularExpression)
    let path = "\(dir)/\(Int(Date().timeIntervalSince1970))-\(safe).log"
    let text = lines.compactMap { $0 as? String }.joined(separator: "\n\n")
    try text.write(toFile: path, atomically: true, encoding: .utf8)
    return path
}

func shadowDGitHubPrompt(task: ShadowDGitHubIssueTask, comments: String) -> String {
    [
        "You are shadow, a local Codex agent executed by shadowd inside the existing smart-shadow system.",
        "",
        "Repository: \(task.repoFullName)",
        "Issue: #\(task.issueNumber) \(task.issueTitle)",
        "Issue URL: \(task.issueURL)",
        "",
        "Issue body:",
        task.issueBody.isEmpty ? "(empty)" : task.issueBody,
        "",
        "Relevant comments:",
        comments.isEmpty ? "(none)" : comments,
        "",
        "Labels: \(task.labels.isEmpty ? "(none)" : task.labels.joined(separator: ", "))",
        "",
        "Instructions:",
        "1. Understand the issue.",
        "2. Make the smallest safe code change.",
        "3. Preserve the existing architecture.",
        "4. Do not rewrite unrelated files.",
        "5. Do not expose secrets.",
        "6. Do not run destructive commands.",
        "7. Run the configured test command if available.",
        "8. If ambiguous, make a conservative best effort and document assumptions.",
        "9. Do not merge.",
        "10. Leave the repository in a clean state.",
        "",
        "Output requirements:",
        "- Summary",
        "- Files changed",
        "- Tests run",
        "- Risks or follow-up"
    ].joined(separator: "\n")
}

func shadowDStatusAccepted(_ task: ShadowDGitHubIssueTask) -> String {
    "👤 `\(task.agentName)` 已接单。\n\n- Trigger: \(task.trigger)\n- Repo: `\(task.repoFullName)`\n- Issue: #\(task.issueNumber)\n- Status: queued"
}

func shadowDStatusRunning(_ task: ShadowDGitHubIssueTask, branch: String) -> String {
    "👤 `\(task.agentName)` 开始执行。\n\n- Service: `\(task.daemonName)`\n- Branch: `\(branch)`\n- Runtime: local Codex\n- Status: running"
}

func shadowDStatusPR(_ task: ShadowDGitHubIssueTask, prURL: String, summary: String, tests: String) -> String {
    "✅ `\(task.agentName)` 已创建 PR：\n\n\(prURL)\n\n摘要：\(summary)\n\n测试：\(tests)\n\n请在 PR 中 review；如需继续修改，可以评论：\n\n@shadow continue"
}

func shadowDStatusNoChanges(_ task: ShadowDGitHubIssueTask, summary: String) -> String {
    "ℹ️ `\(task.agentName)` 已执行，但没有产生代码变更。\n\n摘要：\(summary)\n\n可能原因：\n- Issue 已经被修复\n- 任务描述不够明确\n- Codex 判断不需要修改"
}

func shadowDStatusFailed(_ task: ShadowDGitHubIssueTask, branch: String, error: String) -> String {
    "❌ `\(task.agentName)` 执行失败。\n\n- Service: `\(task.daemonName)`\n- Trigger: \(task.trigger)\n- Branch: `\(branch)`\n- Error summary: \(shadowDSummarize(error, maxLength: 500))\n\n请查看本地 `shadowd` 日志。"
}

func shadowDPRBody(task: ShadowDGitHubIssueTask, summary: String, tests: String) -> String {
    "## Summary\n\nGenerated by `shadow`, executed by local `shadowd` inside `smart-shadow`.\n\n## Linked issue\n\nCloses #\(task.issueNumber)\n\n## Changes\n\n\(summary)\n\n## Tests\n\n\(tests)\n\n## Notes\n\nThis PR was generated locally and requires human review before merge."
}

func shadowDSummarize(_ output: String, maxLength: Int = 1200) -> String {
    let normalized = output.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.count <= maxLength { return normalized }
    return "\(normalized.prefix(maxLength - 1))..."
}

func shadowDExtractURL(_ output: String) -> String? {
    output.split(whereSeparator: { $0.isWhitespace }).map(String.init).first { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
}

func shadowDSplitTrustedCommand(_ command: String) -> [String] {
    var result: [String] = []
    var current = ""
    var quote: Character?
    for char in command {
        if let active = quote {
            if char == active {
                quote = nil
            } else {
                current.append(char)
            }
        } else if char == "\"" || char == "'" {
            quote = char
        } else if char.isWhitespace {
            if !current.isEmpty {
                result.append(current)
                current = ""
            }
        } else {
            current.append(char)
        }
    }
    if !current.isEmpty { result.append(current) }
    return result
}

func requiredOption(_ args: [String], _ option: String) throws -> String {
    guard let value = optionValue(args, option), !value.isEmpty else {
        throw AppError.usage("\(option) is required.")
    }
    return value
}

final class StateStore {
    private var db: OpaquePointer?

    init(path: String) throws {
        try FileManager.default.createDirectory(atPath: URL(fileURLWithPath: path).deletingLastPathComponent().path, withIntermediateDirectories: true)
        guard sqlite3_open(path, &db) == SQLITE_OK else { throw AppError.runtime("Unable to open SQLite database.") }
        try exec(Self.schema)
        try migrate()
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
      lark_task_guid text,
      lark_task_url text,
      created_at text not null,
      updated_at text not null
    );
    create table if not exists sync_cursors (
      id integer primary key autoincrement,
      source text not null,
      google_collection_id text not null,
      cursor_type text not null,
      cursor_value text not null,
      updated_at text not null,
      unique(source, google_collection_id, cursor_type)
    );
    create table if not exists sync_mappings (
      id integer primary key autoincrement,
      source text not null,
      google_id text not null,
      apple_kind text not null,
      apple_external_id text not null,
      google_etag text,
      last_seen_at text not null,
      deleted_at text,
      unique(source, google_id, apple_kind)
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

    func migrate() throws {
        let columns = try query("pragma table_info(projections)", [])
        let names = Set(columns.compactMap { $0["name"] as? String })
        if !names.contains("lark_task_guid") {
            try exec("alter table projections add column lark_task_guid text")
        }
        if !names.contains("lark_task_url") {
            try exec("alter table projections add column lark_task_url text")
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

    func pendingDecision(signalID: Int64) throws -> (id: Int64, decision: Decision)? {
        guard let row = try queryOne(
            """
            select d.id, d.domain, d.priority, d.risk, d.needs_review, d.action, d.reason, d.confidence
            from decisions d
            left join actions a on a.decision_id=d.id
            where d.signal_id=? and a.id is null
            order by d.id desc
            limit 1
            """,
            [signalID]
        ) else {
            return nil
        }
        let decision = Decision(
            domain: row["domain"] as? String ?? "work",
            priority: row["priority"] as? String ?? "normal",
            risk: row["risk"] as? String ?? "low",
            needsReview: (row["needs_review"] as? Int64 ?? 0) != 0,
            action: row["action"] as? String ?? "record_only",
            reason: row["reason"] as? String ?? "retry.pending",
            confidence: row["confidence"] as? String ?? "low"
        )
        return (row["id"] as? Int64 ?? 0, decision)
    }

    func latestDryRunDecision(signalID: Int64) throws -> (id: Int64, decision: Decision)? {
        guard let row = try queryOne(
            """
            select d.id, d.domain, d.priority, d.risk, d.needs_review, d.action, d.reason, d.confidence, a.status
            from decisions d
            join actions a on a.decision_id=d.id
            where d.signal_id=?
            order by a.id desc
            limit 1
            """,
            [signalID]
        ), row["status"] as? String == "dry_run" else {
            return nil
        }
        let decision = Decision(
            domain: row["domain"] as? String ?? "work",
            priority: row["priority"] as? String ?? "normal",
            risk: row["risk"] as? String ?? "low",
            needsReview: (row["needs_review"] as? Int64 ?? 0) != 0,
            action: row["action"] as? String ?? "record_only",
            reason: row["reason"] as? String ?? "retry.dry_run",
            confidence: row["confidence"] as? String ?? "low"
        )
        return (row["id"] as? Int64 ?? 0, decision)
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
            "sync_cursors": try scalar("select count(*) from sync_cursors"),
            "sync_mappings": try scalar("select count(*) from sync_mappings"),
            "pending_actions": try scalar("select count(*) from decisions d left join actions a on a.decision_id=d.id where a.id is null")
        ]
    }

    func syncCursor(source: String, collectionID: String, cursorType: String) throws -> String? {
        let row = try queryOne(
            "select cursor_value from sync_cursors where source=? and google_collection_id=? and cursor_type=?",
            [source, collectionID, cursorType]
        )
        return row?["cursor_value"] as? String
    }

    func recordSyncCursor(source: String, collectionID: String, cursorType: String, value: String?) throws {
        guard let value, !value.isEmpty else { return }
        try execPrepared(
            """
            insert into sync_cursors (source, google_collection_id, cursor_type, cursor_value, updated_at)
            values (?, ?, ?, ?, ?)
            on conflict(source, google_collection_id, cursor_type) do update set
              cursor_value=excluded.cursor_value,
              updated_at=excluded.updated_at
            """,
            [source, collectionID, cursorType, value, nowISO()]
        )
    }

    func clearSyncCursor(source: String, collectionID: String, cursorType: String) throws {
        try execPrepared(
            "delete from sync_cursors where source=? and google_collection_id=? and cursor_type=?",
            [source, collectionID, cursorType]
        )
    }

    func syncMapping(source: String, googleID: String, appleKind: String) throws -> [String: Any]? {
        try queryOne(
            "select source, google_id, apple_kind, apple_external_id, google_etag, last_seen_at, deleted_at from sync_mappings where source=? and google_id=? and apple_kind=?",
            [source, googleID, appleKind]
        )
    }

    func recordSyncMapping(source: String, googleID: String, appleKind: String, appleExternalID: String, googleETag: String?) throws {
        try execPrepared(
            """
            insert into sync_mappings (source, google_id, apple_kind, apple_external_id, google_etag, last_seen_at, deleted_at)
            values (?, ?, ?, ?, ?, ?, null)
            on conflict(source, google_id, apple_kind) do update set
              apple_external_id=excluded.apple_external_id,
              google_etag=excluded.google_etag,
              last_seen_at=excluded.last_seen_at,
              deleted_at=null
            """,
            [source, googleID, appleKind, appleExternalID, googleETag ?? NSNull(), nowISO()]
        )
    }

    func markSyncMappingDeleted(source: String, googleID: String, appleKind: String) throws {
        try execPrepared(
            """
            update sync_mappings
            set deleted_at=?, last_seen_at=?
            where source=? and google_id=? and apple_kind=?
            """,
            [nowISO(), nowISO(), source, googleID, appleKind]
        )
    }

    func projection(for canonicalKey: String) throws -> ProjectionRecord? {
        guard let row = try queryOne("select canonical_key, reminder_external_id, calendar_external_id, lark_task_guid, lark_task_url from projections where canonical_key=?", [canonicalKey]) else {
            return nil
        }
        return ProjectionRecord(
            canonicalKey: row["canonical_key"] as? String ?? canonicalKey,
            reminderExternalID: row["reminder_external_id"] as? String,
            calendarExternalID: row["calendar_external_id"] as? String,
            larkTaskGUID: row["lark_task_guid"] as? String,
            larkTaskURL: row["lark_task_url"] as? String
        )
    }

    func recordProjection(canonicalKey: String, reminderExternalID: String?, calendarExternalID: String?, larkTaskGUID: String? = nil, larkTaskURL: String? = nil) throws {
        try execPrepared(
            """
            insert into projections (canonical_key, reminder_external_id, calendar_external_id, lark_task_guid, lark_task_url, created_at, updated_at)
            values (?, ?, ?, ?, ?, ?, ?)
            on conflict(canonical_key) do update set
              reminder_external_id=coalesce(excluded.reminder_external_id, projections.reminder_external_id),
              calendar_external_id=coalesce(excluded.calendar_external_id, projections.calendar_external_id),
              lark_task_guid=coalesce(excluded.lark_task_guid, projections.lark_task_guid),
              lark_task_url=coalesce(excluded.lark_task_url, projections.lark_task_url),
              updated_at=excluded.updated_at
            """,
            [canonicalKey, reminderExternalID ?? NSNull(), calendarExternalID ?? NSNull(), larkTaskGUID ?? NSNull(), larkTaskURL ?? NSNull(), nowISO(), nowISO()]
        )
    }

    func projections(limit: Int) throws -> [[String: Any]] {
        try query(
            """
            select canonical_key, reminder_external_id, calendar_external_id, lark_task_guid, lark_task_url, created_at, updated_at
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
            let larkURL = externalID.split(separator: " ").map(String.init).first { $0.contains("applink.feishu.cn/client/todo/task") }
            let larkGUID = externalID.split(separator: " ").map(String.init).first { $0.hasPrefix("lark-task://") }?.replacingOccurrences(of: "lark-task://", with: "")
            if reminderID != nil || calendarID != nil || larkURL != nil || larkGUID != nil {
                try recordProjection(canonicalKey: canonicalKey, reminderExternalID: reminderID, calendarExternalID: calendarID, larkTaskGUID: larkGUID, larkTaskURL: larkURL)
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
      <key>LimitLoadToSessionType</key>
      <string>Aqua</string>
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

func shellResult(_ args: [String], timeoutSeconds: TimeInterval? = nil) throws -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = args
    let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("smart-shadow-shell-\(UUID().uuidString).log")
    FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    let outputHandle = try FileHandle(forWritingTo: outputURL)
    defer {
        try? outputHandle.close()
        try? FileManager.default.removeItem(at: outputURL)
    }
    process.standardOutput = outputHandle
    process.standardError = outputHandle
    try process.run()
    if let timeoutSeconds {
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            process.waitUntilExit()
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            process.terminate()
            if semaphore.wait(timeout: .now() + 2) == .timedOut {
                process.interrupt()
            }
        }
    } else {
        process.waitUntilExit()
    }
    try? outputHandle.synchronize()
    let output = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
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
