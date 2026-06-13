import AppKit
import Speech
import SmartShadowGitHubAPI
import SmartShadowShared
import SwiftUI

@main
struct SmartShadowCompanionMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = MacCompanionModel.shared

    var body: some Scene {
        WindowGroup("Smart Shadow") {
            MacShadowConsoleView(model: model)
                .frame(minWidth: 1180, minHeight: 700)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1180, height: 752)

        MenuBarExtra {
            VoicePanelView(model: model)
                .frame(width: 360, height: 460)
        } label: {
            MenuBarVoiceIcon(state: model.state)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandMenu("Shadow") {
                Button("Command Panel") {
                    NotificationCenter.default.post(name: .smartShadowOpenCommandPanel, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Sync GitHub") {
                    NotificationCenter.default.post(name: .smartShadowSyncGitHub, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("New Repo / Project") {
                    NotificationCenter.default.post(name: .smartShadowNewRepoProject, object: nil)
                }
                    .keyboardShortcut("n", modifiers: .command)

                Button("New Issue") {
                    NotificationCenter.default.post(name: .smartShadowNewIssue, object: nil)
                }
                    .keyboardShortcut("i", modifiers: .command)

                Button("Execute Shadow Suggestion") {
                    NotificationCenter.default.post(name: .smartShadowExecuteSuggestion, object: nil)
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
        }

        Settings {
            SettingsView(model: model)
                .frame(width: 460, height: 390)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = MacCompanionModel.shared
    private var overlayController: HotkeyOverlayController?
    private var hotkeyAdapter: MacGlobalHotkeyAdapter?
    private var mainWindow: NSWindow?
    private var authObserver: NSObjectProtocol?
    private var loginObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.showMainWindowIfNeeded()
        }
        if !MacRuntimeMode.disablesGlobalHotkey {
            overlayController = HotkeyOverlayController(model: model)
            hotkeyAdapter = MacGlobalHotkeyAdapter {
                Task { @MainActor [weak self] in
                    self?.overlayController?.toggle()
                }
            }
            hotkeyAdapter?.registerDefaultHotkey()
        }

        authObserver = NotificationCenter.default.addObserver(
            forName: .smartShadowAuthenticationChanged,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if self.model.isAuthenticated {
                    LoginWindowController.closeShared()
                }
            }
        }

        loginObserver = NotificationCenter.default.addObserver(
            forName: .smartShadowShowLogin,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                LoginWindowController.showShared(model: self.model)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let authObserver {
            NotificationCenter.default.removeObserver(authObserver)
        }
        if let loginObserver {
            NotificationCenter.default.removeObserver(loginObserver)
        }
        hotkeyAdapter?.unregister()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindowIfNeeded()
        return true
    }

    private func showMainWindowIfNeeded() {
        if NSApp.windows.contains(where: { $0.title == "Smart Shadow" && $0.isVisible }) {
            return
        }
        if mainWindow == nil {
            let content = MacShadowConsoleView(model: model)
                .frame(minWidth: 1180, minHeight: 700)
                .preferredColorScheme(.dark)
            let hostingController = NSHostingController(rootView: content)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1180, height: 752),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Smart Shadow"
            window.contentViewController = hostingController
            window.minSize = NSSize(width: 1040, height: 680)
            window.isReleasedWhenClosed = false
            window.center()
            mainWindow = window
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct MacShadowConsoleView: View {
    @ObservedObject var model: MacCompanionModel
    @StateObject private var store = MacConsoleStore()
    @State private var selectedArea: MacLifeArea = .work
    @State private var selectedRepo: MacShadowRepo?
    @State private var selectedIssue: MacShadowIssue?
    @State private var showCommandPanel = false
    @State private var commandText = ""
    @State private var suggestionState: VoiceEntryState = .idle

    var body: some View {
        NavigationSplitView {
            MacSidebarView(selectedArea: $selectedArea, accountName: model.userLogin ?? "bozhi-ai")
            .navigationSplitViewColumnWidth(min: 175, ideal: 190)
        } content: {
            if selectedArea == .mine {
                MacMineView(model: model, store: store)
                    .navigationSplitViewColumnWidth(min: 330, ideal: 390)
            } else {
                MacRepoBoardView(
                    area: selectedArea,
                    repos: store.repos.filter { $0.area == selectedArea },
                    syncMessage: store.syncMessage,
                    isLoading: store.isLoadingRepos,
                    selectedRepo: $selectedRepo
                )
                .navigationSplitViewColumnWidth(min: 330, ideal: 390)
            }
        } detail: {
            MacDetailColumn(repo: selectedRepo, issues: selectedIssues, isLoading: store.isLoadingIssues, issue: $selectedIssue)
        }
        .background(ShadowBackground())
        .overlay(alignment: .bottom) {
            MacCommandRail(state: $suggestionState) {
                showCommandPanel = true
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 10)
        }
        .sheet(isPresented: $showCommandPanel) {
            MacCommandPanel(
                commandText: $commandText,
                state: $suggestionState,
                store: store,
                repo: selectedRepo,
                issue: selectedIssue
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .smartShadowOpenCommandPanel)) { _ in
            showCommandPanel = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .smartShadowSyncGitHub)) { _ in
            Task { await store.loadRepos() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .smartShadowNewRepoProject)) { _ in
            commandText = "Create a new repo/project card for "
            showCommandPanel = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .smartShadowNewIssue)) { _ in
            let repoName = selectedRepo?.name ?? "the selected repo"
            commandText = "Create a new issue in \(repoName): "
            showCommandPanel = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .smartShadowExecuteSuggestion)) { _ in
            Task {
                suggestionState = .executing
                await store.executePendingAction()
                suggestionState = store.pendingAction == nil ? .done : .error
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    NotificationCenter.default.post(name: .smartShadowSyncGitHub, object: nil)
                } label: {
                    Label("Sync GitHub", systemImage: "arrow.clockwise")
                }
                .accessibilityIdentifier("macSyncGitHub")
                Button {
                    showCommandPanel = true
                } label: {
                    Label("Command", systemImage: "command")
                }
                .accessibilityIdentifier("macCommandButton")
            }
        }
        .task {
            store.configure(token: model.settings.token)
            await store.loadRepos()
            alignSelectionToArea()
        }
        .onChange(of: model.settings.token) {
            store.configure(token: model.settings.token)
            Task {
                await store.loadRepos()
                alignSelectionToArea(force: true)
            }
        }
        .onChange(of: selectedArea) {
            alignSelectionToArea(force: true)
        }
        .onChange(of: selectedRepo?.id) {
            selectedIssue = nil
            if let selectedRepo {
                Task { await store.loadIssues(for: selectedRepo) }
            }
        }
    }

    private var selectedIssues: [MacShadowIssue] {
        guard let selectedRepo else { return [] }
        return store.issuesByRepo[selectedRepo.fullName] ?? selectedRepo.issues
    }

    private func alignSelectionToArea(force: Bool = false) {
        guard selectedArea != .mine else {
            selectedRepo = nil
            selectedIssue = nil
            return
        }
        if !force, let selectedRepo, selectedRepo.area == selectedArea {
            return
        }
        selectedIssue = nil
        selectedRepo = store.repos.first { $0.area == selectedArea }
    }
}

private struct MacCommandRail: View {
    @Binding var state: VoiceEntryState
    var openCommandPanel: () -> Void

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                MacRailButton(icon: "command", title: "Command") {
                    openCommandPanel()
                }
                MacRailButton(icon: "arrow.clockwise", title: "Sync") {
                    NotificationCenter.default.post(name: .smartShadowSyncGitHub, object: nil)
                }
                Spacer(minLength: 90)
                MacRailButton(icon: "plus.circle", title: "Issue") {
                    NotificationCenter.default.post(name: .smartShadowNewIssue, object: nil)
                }
                MacRailButton(icon: "shippingbox", title: "Repo") {
                    NotificationCenter.default.post(name: .smartShadowNewRepoProject, object: nil)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(ShadowColors.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(ShadowColors.border))
            .shadow(color: .black.opacity(0.34), radius: 22, x: 0, y: 12)

            Button {
                openCommandPanel()
            } label: {
                ShadowOrbView(state: state, size: 58)
                    .frame(width: 124, height: 124)
            }
                .buttonStyle(.plain)
                .offset(y: -18)
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.35)
                        .onEnded { _ in
                            state = .recording
                            openCommandPanel()
                        }
                )
                .gesture(
                    DragGesture(minimumDistance: 16)
                        .onEnded { value in
                            if value.translation.height < -10 { openCommandPanel() }
                        }
                )
                .accessibilityIdentifier("shadowOrb")
                .accessibilityLabel("Shadow Orb")
        }
        .frame(maxWidth: 640)
    }
}

private struct MacRailButton: View {
    var icon: String
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.68))
            .frame(width: 76, height: 30)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct MacSidebarView: View {
    @Binding var selectedArea: MacLifeArea
    var accountName: String

    private let quickRows: [(String, String)] = [
        ("square.grid.2x2", "所有 Repo"),
        ("person.2", "需要我决策"),
        ("clock", "等待中"),
        ("clock.arrow.circlepath", "最近更新")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("LIFE OS")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(ShadowColors.mutedText)
                .padding(.top, 16)

            VStack(spacing: 4) {
                ForEach(MacLifeArea.allCases) { area in
                    MacSidebarRow(
                        icon: area.systemImage,
                        title: area.rawValue,
                        selected: selectedArea == area
                    ) {
                        selectedArea = area
                    }
                }
            }

            Text("QUICK")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(ShadowColors.mutedText)
                .padding(.top, 6)

            VStack(spacing: 4) {
                ForEach(quickRows, id: \.1) { icon, title in
                    MacSidebarRow(icon: icon, title: title, selected: false) {}
                }
            }

            Spacer()

            HStack(spacing: 10) {
                Image("SmartShadowIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(ShadowColors.border))
                    .shadow(color: .black.opacity(0.32), radius: 8, x: 0, y: 4)
                Text(accountName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ShadowColors.mutedText)
            }
            .padding(10)
            .background(ShadowColors.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(ShadowColors.border))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.020, green: 0.027, blue: 0.046),
                    Color(red: 0.031, green: 0.038, blue: 0.066)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

private struct MacSidebarRow: View {
    var icon: String
    var title: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? ShadowColors.cyan : ShadowColors.mutedText)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? .white : ShadowColors.mutedText)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(selected ? ShadowColors.violet.opacity(0.28) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(selected ? ShadowColors.violet.opacity(0.34) : .clear))
        }
        .buttonStyle(.plain)
    }
}

private struct MacRepoBoardView: View {
    var area: MacLifeArea
    var repos: [MacShadowRepo]
    var syncMessage: String?
    var isLoading: Bool
    @Binding var selectedRepo: MacShadowRepo?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(area.rawValue)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Repo radar")
                        .font(.caption)
                        .foregroundStyle(ShadowColors.mutedText)
                }
                .padding(.bottom, 4)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 72)
                }

                ForEach(MacRepoBucket.allCases) { bucket in
                    let bucketRepos = repos.filter { $0.bucket == bucket }
                    if !bucketRepos.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Rectangle()
                                    .fill(bucket.tint)
                                    .frame(width: 3, height: 12)
                                    .clipShape(Capsule())
                                Text(bucket.rawValue)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(bucket.tint)
                                Spacer()
                                Text("\(bucketRepos.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(bucketRepos) { repo in
                                Button {
                                    selectedRepo = repo
                                } label: {
                                    MacRepoCard(repo: repo, selected: selectedRepo?.id == repo.id)
                                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("macRepoCard-\(repo.name)")
                            }
                        }
                    }
                }

                if let syncMessage {
                    Text(syncMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.top, 4)
                }
            }
            .padding(16)
        }
        .background(ShadowBackground())
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 82)
        }
    }
}

private struct MacMineView: View {
    @ObservedObject var model: MacCompanionModel
    @ObservedObject var store: MacConsoleStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("我的")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Control plane")
                        .font(.subheadline)
                        .foregroundStyle(ShadowColors.mutedText)
                }

                MacSettingsBlock(title: "GitHub", rows: [
                    ("Login", model.authStatus),
                    ("Account", model.userLogin ?? (model.isAuthenticated ? "connected" : "not connected")),
                    ("Owner / repo", "\(model.settings.owner)/\(model.settings.repo)"),
                    ("Token scope", "repo, read:user"),
                    ("Repo sync", store.isLoadingRepos ? "syncing" : "\(store.repos.count) repos")
                ])

                Button {
                    NotificationCenter.default.post(name: .smartShadowShowLogin, object: nil)
                } label: {
                    Label(model.isAuthenticated ? "Reconnect GitHub" : "Connect GitHub", systemImage: "person.crop.circle.badge.checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                MacSettingsBlock(title: "Shadow", rows: [
                    ("shadowd", "online check pending"),
                    ("Local link", "this Mac"),
                    ("Agent", "Codex"),
                    ("Mode", "confirm before write"),
                    ("Voice", model.state.statusText)
                ])
                MacSettingsBlock(title: "Life OS", rows: [
                    ("Repo rules", "keyword + topic routing"),
                    ("Bucket rules", "important, urgent, doing, todo"),
                    ("Label map", "GitHub labels as capsules"),
                    ("Auto archive", "manual confirmation")
                ])
                MacSettingsBlock(title: "Safety", rows: [
                    ("Danger confirms", "enabled"),
                    ("Auto whitelist", "none"),
                    ("GitHub writes", "confirmation required"),
                    ("Operation log", "local + GitHub history")
                ])

                if let syncMessage = store.syncMessage {
                    Text(syncMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .padding(22)
        }
        .background(ShadowBackground())
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 82)
        }
    }
}

private struct MacRepoCard: View {
    var repo: MacShadowRepo
    var selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: repo.area.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ShadowColors.violet)
                    .frame(width: 18, height: 18)
                    .background(ShadowColors.violet.opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
                Text(repo.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer()
                MacStatusPill(status: repo.status)
            }
            HStack {
                Text("Next: \(repo.nextAction)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(ShadowColors.mutedText)
                    .lineLimit(1)
                Spacer()
                Text(repo.updated)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                MacInlineMetric(icon: "number", value: "\(repo.issueCount)")
                MacInlineMetric(icon: "arrow.triangle.2.circlepath", value: "\(repo.prCount)")
                MacInlineMetric(icon: "tag", value: "\(repo.labels.count)")
                Spacer()
                MacLabelRow(labels: Array(repo.labels.prefix(2)), accessibilityID: "macRepoLabels-\(repo.name)")
            }
            HStack(spacing: 10) {
                MacRepoMeta(title: "Review", value: repo.reviewDate)
                MacRepoMeta(title: "Agent", value: repo.agentState)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background((selected ? ShadowColors.violet.opacity(0.20) : ShadowColors.card), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(selected ? ShadowColors.violet.opacity(0.46) : ShadowColors.border))
    }
}

private struct MacDetailColumn: View {
    var repo: MacShadowRepo?
    var issues: [MacShadowIssue]
    var isLoading: Bool
    @Binding var issue: MacShadowIssue?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let repo {
                    MacRepoDetail(repo: repo)
                    Text(issue == nil ? "Issues" : "Issue Detail")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    if let issue {
                        MacIssueDetail(repo: repo, issue: issue)
                    } else {
                        if isLoading && issues.isEmpty {
                            ProgressView()
                                .controlSize(.small)
                                .frame(maxWidth: .infinity, minHeight: 80)
                        }
                        ForEach(issues) { item in
                            Button {
                                issue = item
                            } label: {
                                MacIssueRow(issue: item)
                                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("macIssueRow-\(item.number)")
                        }
                    }
                } else {
                    ContentUnavailableView("Select a repo", systemImage: "scope", description: Text("The shadow console is organized around repositories as life projects."))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 420)
                }
            }
            .padding(16)
        }
        .background(ShadowBackground())
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 82)
        }
        .onChange(of: repo?.id) {
            issue = nil
        }
    }
}

private struct MacRepoDetail: View {
    var repo: MacShadowRepo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(repo.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(repo.fullName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                MacStatusPill(status: repo.status)
            }
            Text(repo.nextAction)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(ShadowColors.violet)
            HStack {
                MacMetric(title: "Issues", value: "\(repo.issueCount)")
                MacMetric(title: "PRs", value: "\(repo.prCount)")
                MacMetric(title: "Sync", value: repo.updated)
                MacMetric(title: "Review", value: repo.reviewDate)
                MacMetric(title: "Agent", value: repo.agentState)
            }
            MacLabelRow(labels: repo.labels, accessibilityID: "macRepoDetailLabels-\(repo.name)")
        }
        .padding(12)
        .background(ShadowColors.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(ShadowColors.border))
    }
}

private struct MacIssueRow: View {
    var issue: MacShadowIssue

    var body: some View {
        HStack(spacing: 10) {
            Text("#\(issue.number)")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(ShadowColors.violet)
                .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                Text(issue.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                HStack {
                    MacStatusPill(status: issue.status)
                    Text(issue.assignee)
                    Text(issue.updated)
                    Text("\(issue.comments) comments")
                    Text("PR \(issue.linkedPR)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                MacLabelRow(labels: Array(issue.labels.prefix(3)))
            }
            Spacer()
            if issue.needsDecision {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(ShadowColors.card, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(ShadowColors.border))
    }
}

private struct MacIssueDetail: View {
    var repo: MacShadowRepo
    var issue: MacShadowIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("#\(issue.number) \(issue.title)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Text(repo.fullName)
                .font(.caption)
                .foregroundStyle(.secondary)
            MacLabelRow(labels: issue.labels)
            HStack(spacing: 8) {
                MacStatusPill(status: issue.status)
                Text(issue.assignee)
                Text(issue.updated)
                Text("\(issue.comments) comments")
                Text("PR \(issue.linkedPR)")
            }
            .font(.caption)
            .foregroundStyle(ShadowColors.mutedText)
            MacInfoBlock(title: "Summary", text: issue.summary)
            MacInfoBlock(title: "Timeline", text: issue.timeline.joined(separator: "\n"))
            MacInfoBlock(title: "Comments", text: issue.commentPreview)
            MacInfoBlock(title: "Linked PR", text: issue.linkedPR)
        }
        .padding(12)
        .background(ShadowColors.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(ShadowColors.border))
    }
}

private struct MacCommandPanel: View {
    @Binding var commandText: String
    @Binding var state: VoiceEntryState
    @ObservedObject var store: MacConsoleStore
    var repo: MacShadowRepo?
    var issue: MacShadowIssue?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = VoiceRecorderService()
    @State private var isTranscribing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Shadow Command")
                .font(.title2.bold())
            HStack(spacing: 8) {
                if let repo {
                    Text(repo.name)
                } else {
                    Text("No repo selected")
                }
                if let issue {
                    Text("#\(issue.number)")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(ShadowColors.mutedText)
            TextEditor(text: $commandText)
                .font(.body)
                .frame(height: 140)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(ShadowColors.panel, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("macShadowCommandText")
            MacInfoBlock(title: "Generated GitHub suggestion", text: store.suggestedAction)
            if let pendingAction = store.pendingAction {
                MacInfoBlock(title: "Confirmation required", text: "\(pendingAction.title)\n\n\(pendingAction.body)")
            }
            if let commandStatus = store.commandStatus {
                Text(commandStatus)
                    .font(.caption)
                    .foregroundStyle(commandStatus.localizedCaseInsensitiveContains("failed") || commandStatus.localizedCaseInsensitiveContains("required") ? .orange : ShadowColors.mutedText)
            }
            HStack {
                Button(recorder.isRecording ? "Stop" : "Voice") {
                    Task { await toggleVoiceInput() }
                }
                    .accessibilityIdentifier("macVoiceButton")
                Spacer()
                Button("Generate") {
                    state = .thinking
                    store.generateSuggestion(command: commandText, repo: repo, issue: issue)
                    state = store.pendingAction == nil ? .error : .confirm
                }
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityIdentifier("macGenerateButton")
                Button("Confirm and Execute") {
                    Task {
                        state = .executing
                        await store.executePendingAction()
                        state = store.pendingAction == nil ? .done : .error
                    }
                }
                .disabled(store.pendingAction == nil)
                .accessibilityIdentifier("macConfirmExecuteButton")
                Button("Done") {
                    state = .idle
                    dismiss()
                }
            }
            if isTranscribing {
                Text("Transcribing voice command...")
                    .font(.caption)
                    .foregroundStyle(ShadowColors.mutedText)
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(ShadowBackground())
        .accessibilityIdentifier("macCommandPanel")
    }

    private func toggleVoiceInput() async {
        if recorder.isRecording {
            recorder.stopRecording()
            guard let url = recorder.recordingURL else {
                state = .error
                store.markCommandStatus("Voice recording was not saved.")
                return
            }
            isTranscribing = true
            state = .thinking
            do {
                let pipeline = LocalVoiceProcessingPipeline(client: MacVoiceProcessingClientFactory.makeClient())
                let result = try await pipeline.process(audioURL: url)
                commandText = result.polishedText
                state = .done
                store.markCommandStatus(
                    result.transcript == result.polishedText
                        ? "Voice command processed locally."
                        : "Voice command transcribed and polished locally."
                )
            } catch {
                state = .error
                store.markCommandStatus("Voice processing failed: \(error.localizedDescription)")
            }
            isTranscribing = false
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("smart-shadow-mac-command-\(Int(Date().timeIntervalSince1970)).m4a")
        state = .recording
        await recorder.startRecording(to: url)
        if let error = recorder.errorMessage {
            state = .error
            store.markCommandStatus(error)
        } else {
            store.markCommandStatus("Listening. Press Stop to transcribe.")
        }
    }
}

private struct MacSpeechCommandVoiceProcessingClient: LocalVoiceProcessingClient {
    func transcribe(audioURL: URL) async throws -> String {
        try await MacSpeechCommandTranscriber.transcribe(url: audioURL)
    }

    func polish(transcript: String) async throws -> String {
        transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum MacVoiceProcessingClientFactory {
    static func makeClient(environment: [String: String] = ProcessInfo.processInfo.environment) -> any LocalVoiceProcessingClient {
        if let path = environment["SMART_SHADOW_CHATTYPE_CLI"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty,
           FileManager.default.isExecutableFile(atPath: path) {
            return ChatTypeCLIProcessingClient(executableURL: URL(fileURLWithPath: path), environment: environment)
        }
        return MacSpeechCommandVoiceProcessingClient()
    }
}

private enum MacSpeechCommandTranscriber {
    static func transcribe(url: URL) async throws -> String {
        let authorization = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard authorization == .authorized else {
            throw MacSpeechCommandError.permissionDenied
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN")) ?? SFSpeechRecognizer(), recognizer.isAvailable else {
            throw MacSpeechCommandError.unavailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false
            var didResume = false
            recognizer.recognitionTask(with: request) { result, error in
                if let error, !didResume {
                    didResume = true
                    continuation.resume(throwing: error)
                    return
                }
                guard let result, result.isFinal, !didResume else { return }
                didResume = true
                continuation.resume(returning: result.bestTranscription.formattedString)
            }
        }
    }
}

private enum MacSpeechCommandError: LocalizedError {
    case permissionDenied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Speech recognition permission was denied."
        case .unavailable:
            "Speech recognition is unavailable on this Mac."
        }
    }
}

private struct MacMetric: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MacRepoMeta: View {
    var title: String
    var value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(ShadowColors.mutedText)
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
    }
}

private struct MacInlineMetric: View {
    var icon: String
    var value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.secondary)
    }
}

private struct MacLabelRow: View {
    var labels: [String]
    var accessibilityID: String?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(labels.prefix(6), id: \.self) { label in
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(ShadowColors.violet.opacity(0.16), in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Labels \(labels.prefix(6).joined(separator: ", "))")
        .accessibilityIdentifier(accessibilityID ?? "macLabelRow")
    }
}

private struct MacStatusPill: View {
    var status: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(status == "active" ? .green : .cyan).frame(width: 7, height: 7)
            Text(status)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

private struct MacInfoBlock: View {
    var title: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(ShadowColors.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct MacSettingsBlock: View {
    var title: String
    var rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ForEach(rows, id: \.0) { key, value in
                HStack(alignment: .firstTextBaseline) {
                    Text(key)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(value)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(ShadowColors.mutedText)
                }
                .font(.subheadline)
            }
        }
        .padding(14)
        .background(ShadowColors.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(ShadowColors.border))
    }
}

private struct MacShadowGitHubAction: Identifiable, Hashable {
    let id = UUID()
    var kind: MacShadowGitHubActionKind
    var title: String
    var repoFullName: String
    var repoName: String?
    var repoDescription: String?
    var issueNumber: Int?
    var issueTitle: String?
    var labels: [String] = []
    var body: String

    var sharedPlan: ShadowGitHubActionPlan {
        ShadowGitHubActionPlan(
            kind: kind.plannedKind,
            title: title,
            repoFullName: repoFullName,
            repoName: repoName,
            repoDescription: repoDescription,
            issueNumber: issueNumber,
            issueTitle: issueTitle,
            labels: labels,
            body: body,
            suggestedAction: title
        )
    }
}

private enum MacShadowGitHubActionKind: Hashable {
    case issueComment
    case createIssue
    case createRepo

    init(_ plannedKind: PlannedGitHubActionKind) {
        switch plannedKind {
        case .issueComment:
            self = .issueComment
        case .createIssue:
            self = .createIssue
        case .createRepo:
            self = .createRepo
        }
    }

    var plannedKind: PlannedGitHubActionKind {
        switch self {
        case .issueComment:
            .issueComment
        case .createIssue:
            .createIssue
        case .createRepo:
            .createRepo
        }
    }
}

@MainActor
private final class MacConsoleStore: ObservableObject {
    @Published var repos: [MacShadowRepo] = MacShadowRepo.preview
    @Published var issuesByRepo: [String: [MacShadowIssue]] = [:]
    @Published var isLoadingRepos = false
    @Published var isLoadingIssues = false
    @Published var syncMessage: String?
    @Published var suggestedAction = "Select an issue, describe the change, then generate a confirmation-gated GitHub action."
    @Published var pendingAction: MacShadowGitHubAction?
    @Published var commandStatus: String?

    private var token = ""

    func configure(token: String) {
        guard self.token != token else { return }
        self.token = token
        issuesByRepo = [:]
    }

    func markCommandStatus(_ message: String) {
        commandStatus = message
    }

    func generateSuggestion(command: String, repo: MacShadowRepo?, issue: MacShadowIssue?) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let plan = ShadowGitHubActionPlanner.plan(
            command: trimmed,
            repo: repo.map { ShadowRepoActionContext(name: $0.name, fullName: $0.fullName, agentState: $0.agentState) },
            issue: issue.map { ShadowIssueActionContext(number: $0.number, title: $0.title) },
            allowCreateRepoWithoutSelection: true
        ) else {
            suggestedAction = "Name a repo/project before generating a GitHub action."
            commandStatus = "Repo name required."
            pendingAction = nil
            return
        }

        pendingAction = MacShadowGitHubAction(
            kind: MacShadowGitHubActionKind(plan.kind),
            title: plan.title,
            repoFullName: plan.repoFullName,
            repoName: plan.repoName,
            repoDescription: plan.repoDescription,
            issueNumber: plan.issueNumber,
            issueTitle: plan.issueTitle,
            labels: plan.labels,
            body: plan.body
        )
        suggestedAction = plan.suggestedAction
        commandStatus = "Waiting for confirmation."
    }

    func executePendingAction() async {
        let result = await ShadowGitHubActionExecutor.execute(
            plan: pendingAction?.sharedPlan,
            token: token,
            client: MacGitHubClient(token: token)
        )
        commandStatus = result.statusMessage
        if result == .executed {
            self.pendingAction = nil
        }
    }

    func loadRepos() async {
        guard !isLoadingRepos else { return }
        if MacRuntimeMode.usesPreviewData {
            repos = MacShadowRepo.preview
            syncMessage = "Preview repo radar."
            return
        }
        if token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            repos = MacShadowRepo.preview
            syncMessage = "GitHub login required. Showing local preview radar."
            return
        }

        isLoadingRepos = true
        syncMessage = nil
        do {
            var loaded = try await MacGitHubClient(token: token).fetchRepositories()
            let activeToken = token
            await withTaskGroup(of: (String, Int).self) { group in
                for repo in loaded.prefix(12) {
                    group.addTask {
                        let count = (try? await MacGitHubClient(token: activeToken).fetchPullCount(repoFullName: repo.fullName)) ?? 0
                        return (repo.fullName, count)
                    }
                }
                for await result in group {
                    if let index = loaded.firstIndex(where: { $0.fullName == result.0 }) {
                        loaded[index].prCount = result.1
                    }
                }
            }
            repos = loaded.isEmpty ? MacShadowRepo.preview : loaded
        } catch {
            repos = MacShadowRepo.preview
            syncMessage = "GitHub sync unavailable. Showing local preview radar."
        }
        isLoadingRepos = false
    }

    func loadIssues(for repo: MacShadowRepo) async {
        guard issuesByRepo[repo.fullName] == nil, !isLoadingIssues else { return }
        if MacRuntimeMode.usesPreviewData || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issuesByRepo[repo.fullName] = repo.issues
            return
        }

        isLoadingIssues = true
        do {
            issuesByRepo[repo.fullName] = try await MacGitHubClient(token: token).fetchIssues(repoFullName: repo.fullName)
        } catch {
            issuesByRepo[repo.fullName] = repo.issues
            syncMessage = "Issue sync unavailable. Showing local preview issues."
        }
        isLoadingIssues = false
    }
}

private struct MacGitHubClient {
    var token: String
    var session: URLSession = .shared

    private var api: GitHubAPIClient {
        GitHubAPIClient(token: token, session: session, userAgent: "smart-shadow-macos")
    }

    func fetchRepositories() async throws -> [MacShadowRepo] {
        let repos = try await api.fetchRepositories()
        return repos.enumerated().map { index, repo in
            let classification = ShadowRepoClassifier.classify(
                ShadowRepoClassificationInput(
                    name: repo.name,
                    description: repo.description,
                    topics: repo.topics ?? [],
                    openIssueCount: repo.openIssuesCount
                )
            )
            return MacShadowRepo(
                id: repo.id,
                name: repo.name,
                fullName: repo.fullName,
                description: repo.description?.isEmpty == false ? repo.description! : "No description yet.",
                nextAction: repo.openIssuesCount == 0 ? "Review repo status and define next issue." : "Triage open issues and pick one user-visible move.",
                issueCount: repo.openIssuesCount,
                prCount: 0,
                labels: Array((repo.topics ?? []).prefix(4)),
                status: repo.openIssuesCount == 0 ? "quiet" : "active",
                updated: Self.relative(repo.updatedAt),
                reviewDate: Self.reviewDate(offset: index),
                agentState: index % 3 == 0 ? "watching" : "idle",
                area: MacLifeArea(classified: classification.area),
                bucket: MacRepoBucket(classified: classification.bucket),
                issues: MacShadowIssue.preview
            )
        }
    }

    func fetchIssues(repoFullName: String) async throws -> [MacShadowIssue] {
        let issues = try await api.fetchIssues(repoFullName: repoFullName)
        var mappedIssues: [MacShadowIssue] = []
        for issue in issues.filter({ !$0.isPullRequest }) {
            let labels = issue.labels.map(\.name)
            mappedIssues.append(
                MacShadowIssue(
                    id: issue.id,
                    number: issue.number,
                    title: issue.title,
                    status: issue.state,
                    labels: labels,
                    assignee: issue.assignee?.login ?? "unassigned",
                    updated: Self.relative(issue.updatedAt),
                    comments: issue.comments,
                    linkedPR: "none",
                    needsDecision: labels.contains { $0.localizedCaseInsensitiveContains("decision") || $0.localizedCaseInsensitiveContains("review") },
                    summary: issue.body?.split(separator: "\n").prefix(2).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "No summary yet.",
                    timeline: ["opened", "updated \(Self.relative(issue.updatedAt))"],
                    commentPreview: await commentPreview(for: issue, repoFullName: repoFullName)
                )
            )
        }
        return mappedIssues
    }

    private func commentPreview(for issue: GitHubAPIIssue, repoFullName: String) async -> String {
        guard issue.comments > 0 else {
            return "No comments yet."
        }
        do {
            let comments = try await api.fetchIssueComments(repoFullName: repoFullName, issueNumber: issue.number)
            let rows = comments.prefix(3).compactMap(Self.commentRow)
            return rows.isEmpty ? "\(issue.comments) GitHub comments" : rows.joined(separator: "\n")
        } catch {
            return "\(issue.comments) GitHub comments"
        }
    }

    private static func commentRow(_ comment: GitHubAPIIssueComment) -> String? {
        let body = comment.body?
            .split(separator: "\n")
            .prefix(2)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let body, !body.isEmpty else {
            return nil
        }
        return "@\(comment.user?.login ?? "unknown"): \(body)"
    }

    func fetchPullCount(repoFullName: String) async throws -> Int {
        try await api.fetchPullCount(repoFullName: repoFullName)
    }

    func createIssueComment(repoFullName: String, issueNumber: Int, body: String) async throws {
        try await api.createIssueComment(repoFullName: repoFullName, issueNumber: issueNumber, body: body)
    }

    func createIssue(repoFullName: String, title: String, body: String, labels: [String]) async throws {
        try await api.createIssue(repoFullName: repoFullName, title: title, body: body, labels: labels)
    }

    func createRepository(name: String, description: String?) async throws {
        try await api.createRepository(name: name, description: description)
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    private static func reviewDate(offset: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: offset % 5 + 1, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }
}

extension MacGitHubClient: ShadowGitHubWriteClient {}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private enum MacLifeArea: String, CaseIterable, Identifiable {
    case work = "WORK"
    case money = "MONEY"
    case health = "HEALTH"
    case network = "NETWORK"
    case mine = "我的"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .work: "briefcase"
        case .money: "chart.line.uptrend.xyaxis"
        case .health: "heart.text.square"
        case .network: "person.2.wave.2"
        case .mine: "person.crop.circle"
        }
    }

    init(classified area: ShadowLifeArea) {
        switch area {
        case .work:
            self = .work
        case .money:
            self = .money
        case .health:
            self = .health
        case .network:
            self = .network
        }
    }
}

private enum MacRepoBucket: String, CaseIterable, Identifiable {
    case important = "IMPORTANT"
    case urgent = "URGENT"
    case doing = "DOING"
    case todo = "TODO"

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .important: .cyan
        case .urgent: .orange
        case .doing: .green
        case .todo: .secondary
        }
    }

    init(classified bucket: ShadowRepoBucket) {
        switch bucket {
        case .important:
            self = .important
        case .urgent:
            self = .urgent
        case .doing:
            self = .doing
        case .todo:
            self = .todo
        }
    }
}

private struct MacShadowRepo: Identifiable, Hashable {
    var id: Int
    var name: String
    var fullName: String
    var description: String
    var nextAction: String
    var issueCount: Int
    var prCount: Int
    var labels: [String]
    var status: String
    var updated: String
    var reviewDate: String
    var agentState: String
    var area: MacLifeArea
    var bucket: MacRepoBucket
    var issues: [MacShadowIssue]

    static let preview = [
        MacShadowRepo(id: 1, name: "smart-shadow", fullName: "longbiaochen/smart-shadow", description: "Native life-os control console and daemon.", nextAction: "Verify macOS three-column shadow console.", issueCount: 12, prCount: 2, labels: ["system", "github", "shadow"], status: "doing", updated: "2h", reviewDate: "Jun 11", agentState: "executing", area: .work, bucket: .important, issues: MacShadowIssue.preview),
        MacShadowRepo(id: 2, name: "xmu-ai-micro-major", fullName: "longbiaochen/xmu-ai-micro-major", description: "AI micro-major coursework and delivery.", nextAction: "Confirm syllabus repo source.", issueCount: 8, prCount: 1, labels: ["education", "ai"], status: "important", updated: "1d", reviewDate: "Jun 12", agentState: "watching", area: .work, bucket: .important, issues: MacShadowIssue.preview),
        MacShadowRepo(id: 3, name: "brics-course-june", fullName: "longbiaochen/brics-course-june", description: "BRICS course materials and schedule.", nextAction: "Review agenda blockers.", issueCount: 6, prCount: 0, labels: ["course", "urgent"], status: "urgent", updated: "3h", reviewDate: "Jun 10", agentState: "watching", area: .work, bucket: .urgent, issues: MacShadowIssue.preview),
        MacShadowRepo(id: 4, name: "contract-review", fullName: "longbiaochen/contract-review", description: "Work contract review and legal notes.", nextAction: "Draft decision note.", issueCount: 4, prCount: 1, labels: ["legal", "review"], status: "urgent", updated: "5h", reviewDate: "Jun 10", agentState: "idle", area: .work, bucket: .urgent, issues: MacShadowIssue.preview),
        MacShadowRepo(id: 5, name: "life-os", fullName: "longbiaochen/life-os", description: "Operating rules for personal projects.", nextAction: "Map repo buckets to current rules.", issueCount: 5, prCount: 0, labels: ["docs", "shadow"], status: "doing", updated: "20m", reviewDate: "Jun 11", agentState: "executing", area: .work, bucket: .doing, issues: MacShadowIssue.preview),
        MacShadowRepo(id: 6, name: "codex-github-flow", fullName: "longbiaochen/codex-github-flow", description: "GitHub issue to Codex execution loop.", nextAction: "Validate confirmation path.", issueCount: 3, prCount: 1, labels: ["github", "codex"], status: "doing", updated: "4h", reviewDate: "Jun 12", agentState: "watching", area: .work, bucket: .doing, issues: MacShadowIssue.preview),
        MacShadowRepo(id: 7, name: "lab-website", fullName: "longbiaochen/lab-website", description: "Public website maintenance backlog.", nextAction: "Triage deployment notes.", issueCount: 2, prCount: 0, labels: ["web", "todo"], status: "todo", updated: "2d", reviewDate: "Jun 15", agentState: "idle", area: .work, bucket: .todo, issues: MacShadowIssue.preview),
        MacShadowRepo(id: 8, name: "quant-trading", fullName: "longbiaochen/quant-trading", description: "Financial research and automation guardrails.", nextAction: "Review risk boundary before writes.", issueCount: 6, prCount: 1, labels: ["finance", "risk"], status: "watching", updated: "2h", reviewDate: "Jun 12", agentState: "idle", area: .money, bucket: .doing, issues: MacShadowIssue.preview),
        MacShadowRepo(id: 9, name: "mind-heal", fullName: "longbiaochen/mind-heal", description: "Health research and routines.", nextAction: "Turn latest notes into review issue.", issueCount: 3, prCount: 0, labels: ["health"], status: "quiet", updated: "6h", reviewDate: "Jun 13", agentState: "watching", area: .health, bucket: .todo, issues: MacShadowIssue.preview),
        MacShadowRepo(id: 10, name: "human-comms", fullName: "longbiaochen/human-comms", description: "Relationship drafts and communication review.", nextAction: "Keep sensitive messages draft-only.", issueCount: 4, prCount: 0, labels: ["network", "draft"], status: "active", updated: "1d", reviewDate: "Jun 14", agentState: "watching", area: .network, bucket: .urgent, issues: MacShadowIssue.preview)
    ]
}

private struct MacShadowIssue: Identifiable, Hashable {
    var id: Int
    var number: Int
    var title: String
    var status: String
    var labels: [String]
    var assignee: String
    var updated: String
    var comments: Int
    var linkedPR: String
    var needsDecision: Bool
    var summary: String
    var timeline: [String]
    var commentPreview: String

    static let preview = [
        MacShadowIssue(id: 101, number: 42, title: "Implement repo board grouping", status: "open", labels: ["ui", "decision"], assignee: "Longbiao", updated: "20m", comments: 3, linkedPR: "draft", needsDecision: true, summary: "Repositories should be first-class cards in the life-os view.", timeline: ["opened", "triaged", "awaiting visual acceptance"], commentPreview: "Keep final GitHub writes confirmation-gated."),
        MacShadowIssue(id: 102, number: 43, title: "Wire Shadow Orb command suggestions", status: "open", labels: ["voice"], assignee: "unassigned", updated: "1h", comments: 1, linkedPR: "none", needsDecision: false, summary: "Convert natural language into a reviewable GitHub operation.", timeline: ["opened", "updated today"], commentPreview: "Orb remains available on list, repo, and issue surfaces.")
    ]
}

extension Notification.Name {
    static let smartShadowOpenCommandPanel = Notification.Name("smartShadowOpenCommandPanel")
    static let smartShadowSyncGitHub = Notification.Name("smartShadowSyncGitHub")
    static let smartShadowExecuteSuggestion = Notification.Name("smartShadowExecuteSuggestion")
    static let smartShadowNewRepoProject = Notification.Name("smartShadowNewRepoProject")
    static let smartShadowNewIssue = Notification.Name("smartShadowNewIssue")
    static let smartShadowShowLogin = Notification.Name("smartShadowShowLogin")
}

private struct MenuBarVoiceIcon: View {
    let state: VoiceEntryState

    var body: some View {
        ZStack {
            Image("SmartShadowIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 17, height: 17)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)
                .offset(x: 7, y: 7)
        }
        .accessibilityLabel("SmartShadow voice entry")
    }

    private var statusColor: Color {
        switch state {
        case .idle: .secondary
        case .recording: .red
        case .uploading, .executing: .orange
        case .uploaded, .done: .green
        case .failed, .error: .red
        case .thinking: ShadowColors.cyan
        case .confirm: .orange
        }
    }
}
