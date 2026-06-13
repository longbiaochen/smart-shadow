import Speech
import SmartShadowGitHubAPI
import SmartShadowShared
import SwiftUI
import UIKit

struct SmartShadowRootView: View {
    @EnvironmentObject private var session: ShadowSession
    @State private var showSplash = true

    var body: some View {
        ZStack {
            ShadowBackground()
            if showSplash {
                SplashView()
                    .transition(.opacity)
            } else if session.isAuthenticated {
                ShadowConsoleView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                GitHubLoginView()
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            try? await Task.sleep(nanoseconds: 850_000_000)
            withAnimation(.easeInOut(duration: 0.45)) {
                showSplash = false
            }
        }
    }
}

struct SplashView: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            SmartShadowIconView(size: 122)
            Text("Smart Shadow")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            Text("Repo-first life-os console")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.58))
            Spacer()
            Text("Shadow online")
                .font(.caption.weight(.medium))
                .foregroundStyle(ShadowPalette.cyan)
                .padding(.bottom, 42)
        }
    }
}

struct GitHubLoginView: View {
    @EnvironmentObject private var session: ShadowSession
    @State private var deviceCode: GitHubOAuthDeviceCodeResponse?
    @State private var isLoggingIn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            SmartShadowIconView(size: 94)
            VStack(spacing: 8) {
                Text("GitHub Login")
                    .font(.system(size: 29, weight: .semibold, design: .rounded))
                Text(session.authStatus)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.58))
            }

            VStack(spacing: 12) {
                TextField("GitHub OAuth Client ID", text: $session.oauthClientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(ShadowPalette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(ShadowPalette.border))

                Button {
                    Task { await beginLogin() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                        Text(isLoggingIn ? "Waiting for GitHub" : "Continue with GitHub")
                    }
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(isLoggingIn || session.oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 30)

            if let deviceCode {
                DeviceCodeCard(deviceCode: deviceCode)
                    .padding(.horizontal, 28)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
            Spacer()
        }
    }

    private func beginLogin() async {
        isLoggingIn = true
        errorMessage = nil
        session.saveSettings()
        do {
            let service = GitHubOAuthService(userAgent: "smart-shadow-ios")
            let code = try await service.requestDeviceCode(clientID: session.oauthClientID)
            deviceCode = code
            UIPasteboard.general.string = code.userCode
            await MainActor.run { UIApplication.shared.open(code.verificationURI) }
            let token = try await service.pollForAccessToken(
                clientID: session.oauthClientID,
                deviceCode: code.deviceCode,
                interval: code.interval,
                expiresIn: code.expiresIn
            )
            let user = try await service.validateUser(token: token)
            session.applyOAuthToken(token, login: user.login)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoggingIn = false
    }
}

struct DeviceCodeCard: View {
    var deviceCode: GitHubOAuthDeviceCodeResponse

    var body: some View {
        VStack(spacing: 8) {
            Text("GitHub device code")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))
            Text(deviceCode.userCode)
                .font(.system(size: 29, weight: .bold, design: .monospaced))
            Text("Code copied. Confirm it in GitHub.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.48))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(ShadowPalette.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(ShadowPalette.border))
    }
}

@MainActor
final class ShadowConsoleStore: ObservableObject {
    @Published var repos: [ShadowRepo] = []
    @Published var issuesByRepo: [String: [ShadowIssue]] = [:]
    @Published var isLoadingRepos = false
    @Published var isLoadingIssues = false
    @Published var errorMessage: String?
    @Published var commandText = ""
    @Published var suggestedAction = "Draft a GitHub issue comment with next action and ask for confirmation."
    @Published var pendingAction: ShadowGitHubAction?
    @Published var commandStatus: String?

    private var token = ""
    private var focusedRepo: ShadowRepo?
    private var focusedIssue: ShadowIssue?

    func configure(token: String) {
        guard self.token != token else { return }
        self.token = token
        repos = []
        issuesByRepo = [:]
    }

    func loadRepos() async {
        guard !token.isEmpty, !isLoadingRepos else { return }
        isLoadingRepos = true
        errorMessage = nil
        do {
            var loaded = try await GitHubClient(token: token).fetchRepositories()
            let activeToken = token
            await withTaskGroup(of: (String, Int).self) { group in
                for repo in loaded.prefix(12) {
                    group.addTask {
                        let count = (try? await GitHubClient(token: activeToken).fetchPullCount(repoFullName: repo.fullName)) ?? 0
                        return (repo.fullName, count)
                    }
                }
                for await result in group {
                    if let index = loaded.firstIndex(where: { $0.fullName == result.0 }) {
                        loaded[index].openPRCount = result.1
                    }
                }
            }
            repos = loaded
        } catch {
            errorMessage = "GitHub sync unavailable. Showing local preview radar."
            repos = Self.previewRepos
        }
        isLoadingRepos = false
    }

    func loadIssues(for repo: ShadowRepo) async {
        guard issuesByRepo[repo.fullName] == nil else { return }
        isLoadingIssues = true
        do {
            issuesByRepo[repo.fullName] = try await GitHubClient(token: token).fetchIssues(repoFullName: repo.fullName)
        } catch {
            errorMessage = "Issue sync unavailable. Showing local preview issues."
            issuesByRepo[repo.fullName] = Self.previewIssues
        }
        isLoadingIssues = false
    }

    func focus(repo: ShadowRepo?, issue: ShadowIssue?) {
        focusedRepo = repo
        focusedIssue = issue
    }

    func generateSuggestion() {
        let trimmed = commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            commandStatus = "Enter or dictate a command first."
            pendingAction = nil
            return
        }

        guard let focusedRepo else {
            suggestedAction = "Select a repo or issue before generating a GitHub operation."
            commandStatus = "No repo selected."
            pendingAction = nil
            return
        }

        guard let plan = ShadowGitHubActionPlanner.plan(
            command: trimmed,
            repo: ShadowRepoActionContext(name: focusedRepo.name, fullName: focusedRepo.fullName, agentState: focusedRepo.agentState),
            issue: focusedIssue.map { ShadowIssueActionContext(number: $0.number, title: $0.title) },
            allowCreateRepoWithoutSelection: false
        ) else {
            suggestedAction = "Select a repo or issue before generating a GitHub operation."
            commandStatus = "No GitHub operation generated."
            pendingAction = nil
            return
        }

        pendingAction = ShadowGitHubAction(
            kind: plan.kind == .issueComment ? .issueComment : .createIssue,
            title: plan.title,
            repoFullName: plan.repoFullName,
            issueNumber: plan.issueNumber,
            issueTitle: plan.issueTitle,
            labels: plan.labels,
            body: plan.body
        )
        suggestedAction = plan.suggestedAction
        commandStatus = "Review the generated GitHub action before executing."
    }

    func executePendingAction() async {
        commandStatus = "Executing GitHub action..."
        let result = await ShadowGitHubActionExecutor.execute(
            plan: pendingAction?.sharedPlan,
            token: token,
            client: GitHubClient(token: token)
        )
        commandStatus = result.statusMessage
        if result == .executed {
            self.pendingAction = nil
        }
    }

    static let previewRepos: [ShadowRepo] = [
        ShadowRepo(id: 1, name: "smart-shadow", fullName: "longbiaochen/smart-shadow", description: "Native life-os control surface and shadow daemon.", nextAction: "Ship repo-first console and verify simulator flow.", openIssueCount: 11, openPRCount: 2, labels: ["ios", "macos", "life-os"], status: "active", updatedAt: .now, reviewDate: .now.addingTimeInterval(86400), agentState: "executing", area: .work, bucket: .important),
        ShadowRepo(id: 4, name: "xmu-ai-micro-major", fullName: "longbiaochen/xmu-ai-micro-major", description: "AI education project intake and course work.", nextAction: "Confirm next curriculum issue and owner.", openIssueCount: 8, openPRCount: 1, labels: ["education", "ai"], status: "watching", updatedAt: .now.addingTimeInterval(-86_400), reviewDate: .now.addingTimeInterval(172800), agentState: "idle", area: .work, bucket: .important),
        ShadowRepo(id: 5, name: "brics-course-june", fullName: "longbiaochen/brics-course-june", description: "Course delivery and contract-sensitive tasks.", nextAction: "Review blocker issue before next session.", openIssueCount: 6, openPRCount: 0, labels: ["course", "urgent"], status: "active", updatedAt: .now.addingTimeInterval(-10_800), reviewDate: .now.addingTimeInterval(86400), agentState: "watching", area: .work, bucket: .urgent),
        ShadowRepo(id: 6, name: "contract-review", fullName: "longbiaochen/contract-review", description: "Contract review notes and approval follow-ups.", nextAction: "Prepare decision note for outstanding clause.", openIssueCount: 4, openPRCount: 0, labels: ["legal", "review"], status: "active", updatedAt: .now.addingTimeInterval(-18_000), reviewDate: .now.addingTimeInterval(86400), agentState: "idle", area: .work, bucket: .urgent),
        ShadowRepo(id: 7, name: "life-os", fullName: "longbiaochen/life-os", description: "Personal operating system rules and inbox.", nextAction: "Sync new rules into repo board mapping.", openIssueCount: 9, openPRCount: 1, labels: ["shadow", "docs"], status: "doing", updatedAt: .now.addingTimeInterval(-7_200), reviewDate: .now.addingTimeInterval(172800), agentState: "watching", area: .work, bucket: .doing),
        ShadowRepo(id: 8, name: "codex-github-flow", fullName: "longbiaochen/codex-github-flow", description: "GitHub issue-first automation workflow.", nextAction: "Validate issue to branch acceptance path.", openIssueCount: 5, openPRCount: 1, labels: ["github", "automation"], status: "doing", updatedAt: .now.addingTimeInterval(-21_600), reviewDate: .now.addingTimeInterval(259200), agentState: "idle", area: .work, bucket: .doing),
        ShadowRepo(id: 9, name: "lab-website", fullName: "longbiaochen/lab-website", description: "Public site updates and publication queue.", nextAction: "Decide whether to archive stale copy tasks.", openIssueCount: 2, openPRCount: 0, labels: ["web"], status: "quiet", updatedAt: .now.addingTimeInterval(-172_800), reviewDate: .now.addingTimeInterval(345600), agentState: "idle", area: .work, bucket: .todo),
        ShadowRepo(id: 2, name: "quant-trading", fullName: "longbiaochen/quant-trading", description: "Research and execution system for financial experiments.", nextAction: "Review risk guardrails before adding new automation.", openIssueCount: 6, openPRCount: 1, labels: ["finance", "risk"], status: "watching", updatedAt: .now.addingTimeInterval(-9200), reviewDate: .now.addingTimeInterval(172800), agentState: "idle", area: .money, bucket: .doing),
        ShadowRepo(id: 3, name: "mind-heal", fullName: "longbiaochen/mind-heal", description: "Health research, routines, and decision support.", nextAction: "Summarize latest sleep notes into one review issue.", openIssueCount: 3, openPRCount: 0, labels: ["health"], status: "quiet", updatedAt: .now.addingTimeInterval(-21400), reviewDate: .now.addingTimeInterval(259200), agentState: "watching", area: .health, bucket: .todo)
    ]

    static let previewIssues: [ShadowIssue] = [
        ShadowIssue(id: 101, number: 42, title: "Implement repo board grouping", status: "open", labels: ["ios", "decision"], assignee: "Longbiao", updatedAt: .now, commentCount: 3, linkedPRStatus: "draft", needsDecision: true, summary: "Repo cards should be first-class life project objects, not issue rows.", timeline: ["opened", "triaged", "awaiting decision"], comments: ["Need final visual acceptance on simulator."]),
        ShadowIssue(id: 102, number: 43, title: "Wire Shadow Orb command suggestions", status: "open", labels: ["voice"], assignee: "unassigned", updatedAt: .now.addingTimeInterval(-3600), commentCount: 1, linkedPRStatus: "none", needsDecision: false, summary: "Convert natural-language input into reviewable GitHub actions.", timeline: ["opened", "updated today"], comments: ["Keep all writes confirmation-gated."])
    ]
}

enum ShadowGitHubActionKind: Equatable {
    case issueComment
    case createIssue
}

struct ShadowGitHubAction: Equatable {
    var kind: ShadowGitHubActionKind
    var title: String
    var repoFullName: String
    var issueNumber: Int?
    var issueTitle: String?
    var labels: [String] = []
    var body: String

    var sharedPlan: SmartShadowShared.ShadowGitHubActionPlan {
        SmartShadowShared.ShadowGitHubActionPlan(
            kind: kind == .issueComment ? .issueComment : .createIssue,
            title: title,
            repoFullName: repoFullName,
            issueNumber: issueNumber,
            issueTitle: issueTitle,
            labels: labels,
            body: body,
            suggestedAction: title
        )
    }
}

struct ShadowConsoleView: View {
    @EnvironmentObject private var session: ShadowSession
    @StateObject private var store = ShadowConsoleStore()
    @State private var selectedArea: LifeArea = .work
    @State private var orbState: VoiceInteractionState = .idle
    @State private var showCommandPanel = false

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationStack {
                if selectedArea == .mine {
                    MineView(store: store)
                        .environmentObject(session)
                } else {
                    RepoBoardView(area: selectedArea, store: store, orbState: $orbState, showCommandPanel: $showCommandPanel)
                }
            }
            .id(selectedArea)

            ShadowBottomTabBar(selection: $selectedArea)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            ShadowOrbDock(state: $orbState, showCommandPanel: $showCommandPanel)
                .padding(.bottom, 72)
        }
        .tint(ShadowPalette.cyan)
        .sheet(isPresented: $showCommandPanel) {
            CommandPanel(store: store, orbState: $orbState)
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            store.configure(token: session.settings.token)
        }
        .task {
            store.configure(token: session.settings.token)
            await store.loadRepos()
        }
    }
}

struct ShadowBottomTabBar: View {
    @Binding var selection: LifeArea

    var body: some View {
        HStack(spacing: 0) {
            ForEach(LifeArea.allCases) { area in
                Button {
                    selection = area
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: area.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                        Text(area.rawValue)
                            .font(.system(size: area == .mine ? 9 : 10, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                    }
                    .foregroundStyle(selection == area ? ShadowPalette.cyan : .white.opacity(0.66))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        Group {
                            if selection == area {
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: [ShadowPalette.violet.opacity(0.28), ShadowPalette.cyan.opacity(0.12)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("shadowTab-\(area.rawValue)")
            }
        }
        .padding(6)
        .frame(height: 62)
        .background(.ultraThinMaterial, in: Capsule())
        .background(ShadowPalette.cardFill.opacity(0.82), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.40), radius: 24, x: 0, y: 12)
    }
}

struct RepoBoardView: View {
    var area: LifeArea
    @ObservedObject var store: ShadowConsoleStore
    @Binding var orbState: VoiceInteractionState
    @Binding var showCommandPanel: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 11) {
                HeaderStrip(title: area.rawValue, subtitle: "Repo radar")

                if store.isLoadingRepos {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }

                ForEach(RepoBucket.allCases) { bucket in
                    let repos = store.repos.filter { $0.area == area && $0.bucket == bucket }
                    if !repos.isEmpty {
                        RepoGroupSection(bucket: bucket, repos: repos, store: store, orbState: $orbState, showCommandPanel: $showCommandPanel)
                    }
                }

                if let error = store.errorMessage {
                    Text(error)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.orange.opacity(0.66))
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 126)
        }
        .background(ShadowBackground().ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await store.loadRepos()
        }
        .onAppear {
            store.focus(repo: nil, issue: nil)
        }
    }
}

struct RepoGroupSection: View {
    var bucket: RepoBucket
    var repos: [ShadowRepo]
    @ObservedObject var store: ShadowConsoleStore
    @Binding var orbState: VoiceInteractionState
    @Binding var showCommandPanel: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(bucket.tint)
                    .frame(width: 3, height: 13)
                    .clipShape(Capsule())
                Text(bucket.rawValue)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(bucket.tint)
                Spacer()
                Text("\(repos.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.42))
            }

            ForEach(repos) { repo in
                NavigationLink {
                    RepoDetailView(repo: repo, store: store, orbState: $orbState, showCommandPanel: $showCommandPanel)
                } label: {
                    RepoCard(repo: repo)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("repoCard-\(repo.name)")
            }
        }
    }
}

struct RepoCard: View {
    var repo: ShadowRepo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: repo.area.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ShadowPalette.violet)
                    .frame(width: 20, height: 20)
                    .background(ShadowPalette.violet.opacity(0.18), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(repo.name)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(repo.description)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.46))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(repo.updatedAt.relativeTime)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.44))
            }

            Text("Next: \(repo.nextAction)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)

            HStack(spacing: 11) {
                InlineMetric(icon: "number", value: "\(repo.openIssueCount)")
                InlineMetric(icon: "arrow.triangle.2.circlepath", value: "\(repo.openPRCount)")
                InlineMetric(icon: "tag", value: "\(max(repo.labels.count, 1))")
                Spacer()
                StatusPill(status: repo.status)
            }

            HStack(spacing: 9) {
                RepoMetaChip(title: "Review", value: repo.reviewDate.relativeDay)
                RepoMetaChip(title: "Agent", value: repo.agentState)
            }

            LabelRow(labels: repo.labels.isEmpty ? ["system", "shadow"] : repo.labels, accessibilityID: "repoLabels-\(repo.name)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(ShadowPalette.cardFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(ShadowPalette.border))
    }
}

struct RepoDetailView: View {
    var repo: ShadowRepo
    @ObservedObject var store: ShadowConsoleStore
    @Binding var orbState: VoiceInteractionState
    @Binding var showCommandPanel: Bool

    private var issues: [ShadowIssue] {
        store.issuesByRepo[repo.fullName] ?? []
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                RepoDetailHeader(repo: repo)
                HStack(spacing: 8) {
                    DetailTabChip(title: "Issues (\(repo.openIssueCount))", active: true)
                    DetailTabChip(title: "PRs (\(repo.openPRCount))", active: false)
                    DetailTabChip(title: "About", active: false)
                }
                Text("Issues")
                    .font(.headline)
                    .padding(.top, 2)

                if store.isLoadingIssues && issues.isEmpty {
                    ProgressView().tint(.white).frame(maxWidth: .infinity, minHeight: 90)
                } else if issues.isEmpty {
                    EmptyState(text: "No open issues found.")
                } else {
                    ForEach(issues) { issue in
                        NavigationLink {
                            IssueDetailView(repo: repo, issue: issue, store: store, orbState: $orbState, showCommandPanel: $showCommandPanel)
                        } label: {
                            IssueRow(issue: issue)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("issueRow-\(issue.number)")
                    }
                }

            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 112)
        }
        .background(ShadowBackground().ignoresSafeArea())
        .navigationTitle(repo.name)
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            ShadowOrbDock(state: $orbState, showCommandPanel: $showCommandPanel)
                .padding(.bottom, 12)
        }
        .task {
            await store.loadIssues(for: repo)
        }
        .onAppear {
            store.focus(repo: repo, issue: nil)
        }
    }
}

struct RepoDetailHeader: View {
    var repo: ShadowRepo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(repo.name)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(repo.fullName)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.46))
                }
                Spacer()
                StatusPill(status: repo.status)
            }
            Text(repo.nextAction)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(ShadowPalette.cyan)
            HStack(spacing: 10) {
                MetricChip(title: "Issues", value: "\(repo.openIssueCount)")
                MetricChip(title: "PRs", value: "\(repo.openPRCount)")
                MetricChip(title: "Sync", value: repo.updatedAt.relativeTime)
                MetricChip(title: "Review", value: repo.reviewDate.relativeDay)
            }
            DetailBlock(title: "Agent", rows: [repo.agentState])
            LabelRow(labels: repo.labels.isEmpty ? ["repo"] : repo.labels, accessibilityID: "repoDetailLabels-\(repo.name)")
        }
        .padding(12)
        .background(ShadowPalette.cardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(ShadowPalette.border))
    }
}

struct IssueRow: View {
    var issue: ShadowIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("#\(issue.number)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(ShadowPalette.cyan)
                Text(issue.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Spacer()
                if issue.needsDecision {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            HStack(spacing: 10) {
                StatusPill(status: issue.status)
                Text(issue.assignee)
                Text(issue.updatedAt.relativeTime)
                Text("\(issue.commentCount) comments")
                Text("PR \(issue.linkedPRStatus)")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.55))
            LabelRow(labels: issue.labels)
        }
        .padding(10)
        .background(ShadowPalette.panel, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(ShadowPalette.border))
    }
}

struct IssueDetailView: View {
    var repo: ShadowRepo
    var issue: ShadowIssue
    @ObservedObject var store: ShadowConsoleStore
    @Binding var orbState: VoiceInteractionState
    @Binding var showCommandPanel: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("#\(issue.number) \(issue.title)")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                    Text(repo.fullName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.50))
                    HStack(spacing: 8) {
                        StatusPill(status: issue.status)
                        if issue.needsDecision {
                            Text("needs decision")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.orange, in: Capsule())
                        }
                    }
                    HStack(spacing: 10) {
                        RepoMetaChip(title: "Assignee", value: issue.assignee)
                        RepoMetaChip(title: "Updated", value: issue.updatedAt.relativeTime)
                        RepoMetaChip(title: "Comments", value: "\(issue.commentCount)")
                    }
                    LabelRow(labels: issue.labels)
                }
                .padding(16)
                .background(ShadowPalette.cardFill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(ShadowPalette.border))

                DetailBlock(title: "Summary", rows: [issue.summary])
                DetailBlock(title: "Timeline", rows: issue.timeline)
                DetailBlock(title: "Comments", rows: issue.comments)
                DetailBlock(title: "Linked PR", rows: [issue.linkedPRStatus])
            }
            .padding(18)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 112)
        }
        .background(ShadowBackground().ignoresSafeArea())
        .navigationTitle("#\(issue.number)")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            ShadowOrbDock(state: $orbState, showCommandPanel: $showCommandPanel)
                .padding(.bottom, 18)
        }
        .onAppear {
            store.focus(repo: repo, issue: issue)
        }
    }
}

struct MineView: View {
    @EnvironmentObject private var session: ShadowSession
    @ObservedObject var store: ShadowConsoleStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HeaderStrip(title: "我的", subtitle: "Control plane")
                SettingsSection(title: "GitHub", rows: [
                    ("Login", session.authStatus),
                    ("Account", session.userLogin ?? "connected"),
                    ("Owner / repo", "\(session.settings.owner)/\(session.settings.repo)"),
                    ("Token scope", "repo, read:user"),
                    ("Repo sync", store.isLoadingRepos ? "syncing" : "\(store.repos.count) repos")
                ])
                SettingsSection(title: "Shadow", rows: [
                    ("shadowd", "online check pending"),
                    ("Local link", "this device"),
                    ("Agent", "Codex"),
                    ("Mode", "confirm before write"),
                    ("Voice", "press / dictate")
                ])
                SettingsSection(title: "Life OS", rows: [
                    ("Repo rules", "keyword + topic routing"),
                    ("Bucket rules", "important, urgent, doing, todo"),
                    ("Labels", "GitHub labels as capsules"),
                    ("Archive", "manual confirmation")
                ])
                SettingsSection(title: "Safety", rows: [
                    ("Danger confirms", "enabled"),
                    ("Auto whitelist", "none"),
                    ("GitHub writes", "confirmation required"),
                    ("Operation log", "local + GitHub history")
                ])

                Button("Log Out", role: .destructive) {
                    session.logout()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)

                Color.clear.frame(height: 112)
            }
            .padding(18)
        }
        .background(ShadowBackground().ignoresSafeArea())
        .navigationTitle("我的")
    }
}

struct CommandPanel: View {
    @ObservedObject var store: ShadowConsoleStore
    @Binding var orbState: VoiceInteractionState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = AudioRecorder()
    @State private var isTranscribing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextEditor(text: $store.commandText)
                        .font(.body)
                        .frame(minHeight: 120)
                        .padding(10)
                        .scrollContentBackground(.hidden)
                        .background(ShadowPalette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityIdentifier("shadowCommandText")

                    DetailBlock(title: "Suggested GitHub action", rows: [store.suggestedAction])

                    HStack {
                        Button {
                            Task { await toggleVoiceInput() }
                        } label: {
                            Label(recorder.isRecording ? "Stop" : "Voice", systemImage: recorder.isRecording ? "stop.fill" : "mic.fill")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("shadowVoiceButton")

                        Spacer()

                        Button {
                            store.generateSuggestion()
                            orbState = store.pendingAction == nil ? .failed(store.commandStatus ?? "No action generated") : .responding("Waiting for confirmation")
                        } label: {
                            Label("Generate", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("shadowGenerateButton")
                    }

                    if let pendingAction = store.pendingAction {
                        DetailBlock(title: "Confirmation required", rows: [pendingAction.title, pendingAction.body])
                        Button {
                            Task {
                                orbState = .uploading
                                await store.executePendingAction()
                                orbState = store.pendingAction == nil ? .uploaded(deliveryPlaceholder) : .failed(store.commandStatus ?? "Execution failed")
                            }
                        } label: {
                            Label("Confirm and Execute", systemImage: "checkmark.seal.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("shadowConfirmExecuteButton")
                        .accessibilityLabel("Confirm and Execute")
                    }

                    if isTranscribing {
                        Text("Transcribing voice command...")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.58))
                    }

                    if let commandStatus = store.commandStatus {
                        Text(commandStatus)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(18)
            }
            .background(ShadowBackground().ignoresSafeArea())
            .navigationTitle("Shadow Command")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        orbState = .idle
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var deliveryPlaceholder: VoicePacketDelivery {
        VoicePacketDelivery(
            packetID: "github_action",
            repositoryPath: "github/issues",
            uploadedAt: ISO8601DateFormatter.localInternetDateTimeString(from: Date()),
            status: .uploaded,
            errorMessage: nil
        )
    }

    private func toggleVoiceInput() async {
        if recorder.isRecording {
            recorder.stop()
            guard let url = recorder.recordingURL else { return }
            isTranscribing = true
            do {
                let pipeline = LocalVoiceProcessingPipeline(client: SpeechCommandVoiceProcessingClient())
                let result = try await pipeline.process(audioURL: url)
                store.commandText = result.polishedText
                store.commandStatus = result.transcript == result.polishedText
                    ? "Voice command processed locally."
                    : "Voice command transcribed and polished locally."
            } catch {
                store.commandStatus = "Voice processing failed: \(error.localizedDescription)"
            }
            isTranscribing = false
            orbState = .idle
        } else {
            orbState = .listening
            await recorder.start()
        }
    }
}

struct SpeechCommandVoiceProcessingClient: LocalVoiceProcessingClient {
    func transcribe(audioURL: URL) async throws -> String {
        try await SpeechCommandTranscriber.transcribe(url: audioURL)
    }

    func polish(transcript: String) async throws -> String {
        transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SpeechCommandTranscriber {
    static func transcribe(url: URL) async throws -> String {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard status == .authorized else {
            throw SpeechCommandError.permissionDenied
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh_CN")) ?? SFSpeechRecognizer(), recognizer.isAvailable else {
            throw SpeechCommandError.unavailable
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

enum SpeechCommandError: LocalizedError {
    case permissionDenied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Speech recognition permission was denied."
        case .unavailable:
            "Speech recognition is unavailable on this device."
        }
    }
}

struct ShadowOrbDock: View {
    @Binding var state: VoiceInteractionState
    @Binding var showCommandPanel: Bool
    @State private var isPressing = false

    var body: some View {
        Button {
            showCommandPanel = true
        } label: {
            ShadowOrbView(state: state, size: 42, ringSpacing: 16)
                .frame(width: 76, height: 76)
                .scaleEffect(isPressing ? 1.08 : 1)
        }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35)
                    .onChanged { _ in isPressing = true }
                    .onEnded { _ in
                        isPressing = false
                        state = .listening
                        showCommandPanel = true
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 18)
                    .onEnded { value in
                        if value.translation.height < -12 {
                            showCommandPanel = true
                        }
                    }
            )
            .accessibilityIdentifier("shadowOrb")
            .accessibilityLabel("Shadow Orb")
    }
}

struct HeaderStrip: View {
    var title: String
    var subtitle: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.42))
            }
            Spacer()
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(ShadowPalette.cyan)
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.06), in: Circle())
                Image("SmartShadowIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }
}

struct SmartShadowIconView: View {
    var size: CGFloat

    var body: some View {
        Image("SmartShadowIcon")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.46), radius: 22, x: 0, y: 16)
            .shadow(color: ShadowPalette.cyan.opacity(0.10), radius: 26, x: 0, y: 0)
    }
}

struct StatusPill: View {
    var status: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(statusColor).frame(width: 7, height: 7)
            Text(status)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white.opacity(0.74))
    }

    private var statusColor: Color {
        status.lowercased().contains("active") || status.lowercased().contains("open") ? .green : .cyan
    }
}

struct InlineMetric: View {
    var icon: String
    var value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white.opacity(0.62))
    }
}

struct DetailTabChip: View {
    var title: String
    var active: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(active ? .white : .white.opacity(0.54))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(active ? ShadowPalette.violet.opacity(0.28) : ShadowPalette.panel, in: Capsule())
            .overlay(Capsule().stroke(active ? ShadowPalette.violet.opacity(0.36) : ShadowPalette.border))
    }
}

struct MetricChip: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
            Text(title)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.44))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct RepoMetaChip: View {
    var title: String
    var value: String

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .foregroundStyle(.white.opacity(0.40))
            Text(value)
                .foregroundStyle(.white.opacity(0.68))
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .lineLimit(1)
    }
}

struct LabelRow: View {
    var labels: [String]
    var accessibilityID: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(labels.prefix(6), id: \.self) { label in
                    Text(label)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                    .background(ShadowPalette.violet.opacity(0.18), in: Capsule())
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Labels \(labels.prefix(6).joined(separator: ", "))")
        .accessibilityIdentifier(accessibilityID ?? "labelRow")
    }
}

struct DetailBlock: View {
    var title: String
    var rows: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            ForEach(rows, id: \.self) { row in
                Text(row)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.64))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(ShadowPalette.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(ShadowPalette.border))
    }
}

struct SettingsSection: View {
    var title: String
    var rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            ForEach(rows, id: \.0) { key, value in
                HStack(alignment: .firstTextBaseline) {
                    Text(key)
                        .foregroundStyle(.white.opacity(0.52))
                    Spacer()
                    Text(value)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.white.opacity(0.78))
                }
                .font(.subheadline)
            }
        }
        .padding(14)
        .background(ShadowPalette.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(ShadowPalette.border))
    }
}

struct EmptyState: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.50))
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(ShadowPalette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ShadowBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.018, green: 0.026, blue: 0.046),
                    Color(red: 0.026, green: 0.036, blue: 0.064),
                    Color(red: 0.008, green: 0.012, blue: 0.026)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadarGridView().opacity(0.16)
            StarFieldView().opacity(0.12)
        }
    }
}

struct ShadowOrbView: View {
    var state: VoiceInteractionState
    var size: CGFloat
    var ringSpacing: CGFloat = 34
    @State private var pulse = false
    @State private var rotate = false

    var body: some View {
        ZStack {
            ForEach(0..<3) { index in
                Circle()
                    .stroke(state.ringColor.opacity(state.pulseOpacity / Double(index + 1)), lineWidth: 1)
                    .frame(width: size + CGFloat(index) * ringSpacing, height: size + CGFloat(index) * ringSpacing)
                    .scaleEffect(pulse ? 1.08 : 0.92)
            }
            Circle()
                .trim(from: 0.10, to: state == .uploading ? 0.82 : 0.28)
                .stroke(state.ringColor.opacity(0.78), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .frame(width: size + 12, height: size + 12)
                .rotationEffect(.degrees(rotate ? 360 : 0))
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.88), ShadowPalette.cyan, ShadowPalette.violet, ShadowPalette.violetDeep, .black.opacity(0.96)],
                        center: .center,
                        startRadius: 5,
                        endRadius: size * 0.64
                    )
                )
                .frame(width: size, height: size)
                .overlay(Circle().stroke(.white.opacity(0.58), lineWidth: 1.1).blur(radius: 1))
                .shadow(color: state.ringColor.opacity(0.64), radius: 24, x: 0, y: 0)
                .scaleEffect(state.orbScale)
        }
        .animation(.easeInOut(duration: 0.7), value: state)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) { rotate = true }
        }
    }
}

struct StarFieldView: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<42 {
                let x = CGFloat((index * 73) % 997) / 997 * size.width
                let y = CGFloat((index * 149) % 991) / 991 * size.height
                let radius = CGFloat((index % 2) + 1) * 0.42
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)), with: .color(.white.opacity(index % 5 == 0 ? 0.34 : 0.10)))
            }
        }
    }
}

struct RadarGridView: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.76, y: size.height * 0.22)
            for radius in stride(from: 70.0, through: Double(max(size.width, size.height)) * 0.88, by: 82.0) {
                let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(ShadowPalette.cyan.opacity(0.16)), lineWidth: 0.55)
            }
            for x in stride(from: 0.0, through: Double(size.width), by: 58.0) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.white.opacity(0.030)), lineWidth: 0.5)
            }
            for y in stride(from: 0.0, through: Double(size.height), by: 58.0) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.white.opacity(0.026)), lineWidth: 0.5)
            }
        }
    }
}

enum ShadowPalette {
    static let cyan = Color(red: 0.35, green: 0.90, blue: 0.98)
    static let violet = Color(red: 0.52, green: 0.30, blue: 1.0)
    static let violetDeep = Color(red: 0.12, green: 0.09, blue: 0.26)
    static let panel = Color.white.opacity(0.052)
    static let cardFill = Color(red: 0.09, green: 0.12, blue: 0.20).opacity(0.78)
    static let border = Color.white.opacity(0.085)
}

extension VoiceInteractionState {
    var ringColor: Color {
        switch self {
        case .failed: .red
        case .responding: .orange
        case .uploaded: .green
        case .listening: ShadowPalette.cyan
        case .uploading: .orange
        case .idle: ShadowPalette.cyan
        }
    }
}

extension Date {
    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: self, relativeTo: .now)
    }

    var relativeDay: String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: self)
    }
}

#Preview("Console") {
    SmartShadowRootView()
        .environmentObject(ShadowSession())
}
