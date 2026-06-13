import XCTest
@testable import SmartShadowShared

final class ShadowRepoClassifierTests: XCTestCase {
    func testClassifiesLifeAreasFromRepoTextAndTopics() {
        XCTAssertEqual(
            classify(name: "quant-trading", description: "Revenue and risk research", topics: ["finance"]).area,
            .money
        )
        XCTAssertEqual(
            classify(name: "mind-heal", description: "Sleep and routine notes", topics: []).area,
            .health
        )
        XCTAssertEqual(
            classify(name: "human-comms", description: "Relationship draft review", topics: ["people"]).area,
            .network
        )
        XCTAssertEqual(
            classify(name: "smart-shadow", description: "Native repo console", topics: ["github"]).area,
            .work
        )
    }

    func testClassifiesBucketsByExplicitSignalsBeforeIssueVolume() {
        XCTAssertEqual(
            classify(name: "contract-review", description: "urgent blocker before deadline", topics: [], openIssueCount: 12).bucket,
            .urgent
        )
        XCTAssertEqual(
            classify(name: "life-os", description: "core platform rules", topics: [], openIssueCount: 1).bucket,
            .important
        )
        XCTAssertEqual(
            classify(name: "coursework", description: "active curriculum work", topics: [], openIssueCount: 2).bucket,
            .doing
        )
        XCTAssertEqual(
            classify(name: "archive-lab", description: "quiet archive", topics: [], openIssueCount: 0).bucket,
            .todo
        )
    }

    func testHighOpenIssueCountDefaultsToImportantWhenNoUrgentSignalExists() {
        XCTAssertEqual(
            classify(name: "repo-board", description: "unclassified backlog", topics: [], openIssueCount: 8).bucket,
            .important
        )
    }

    private func classify(
        name: String,
        description: String?,
        topics: [String],
        openIssueCount: Int = 0
    ) -> ShadowRepoClassification {
        ShadowRepoClassifier.classify(
            ShadowRepoClassificationInput(
                name: name,
                description: description,
                topics: topics,
                openIssueCount: openIssueCount
            )
        )
    }
}
