import XCTest
@testable import SmartShadowShared

final class IssueStateMachineTests: XCTestCase {
    func testTransitionReplacesPriorShadowStatusAndKeepsOtherLabels() {
        let transition = IssueStateMachine.transition(
            labels: ["smart-shadow", "shadow:inbox", "ios"],
            to: .triaging,
            comment: "已接收任务，正在拆解。"
        )

        XCTAssertEqual(transition.from, .inbox)
        XCTAssertEqual(transition.to, .triaging)
        XCTAssertEqual(transition.labels, ["smart-shadow", "ios", "shadow:triaging"])
        XCTAssertEqual(transition.comment, "已接收任务，正在拆解。")
    }

    func testTransitionAddsSmartShadowLabelWhenMissing() {
        let transition = IssueStateMachine.transition(labels: ["docs"], to: .waitingUser)

        XCTAssertNil(transition.from)
        XCTAssertEqual(transition.labels, ["docs", "smart-shadow", "shadow:waiting-user"])
    }
}
