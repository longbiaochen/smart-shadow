import XCTest
@testable import SmartShadowShared

final class VoiceEntryStateTests: XCTestCase {
    func testShadowOrbStateCopyMatchesInteractionContract() {
        XCTAssertEqual(VoiceEntryState.idle.statusText, "按住，说给影子听")
        XCTAssertEqual(VoiceEntryState.recording.statusText, "松开上传")
        XCTAssertEqual(VoiceEntryState.thinking.statusText, "影子正在思考")
        XCTAssertEqual(VoiceEntryState.executing.statusText, "正在执行")
        XCTAssertEqual(VoiceEntryState.confirm.statusText, "等待确认")
        XCTAssertEqual(VoiceEntryState.done.statusText, "已完成")
        XCTAssertEqual(VoiceEntryState.error.statusText, "执行失败")
    }

    func testShadowOrbStateMotionSeparatesListeningConfirmProgressAndError() {
        XCTAssertGreaterThan(VoiceEntryState.recording.orbScale, VoiceEntryState.idle.orbScale)
        XCTAssertGreaterThan(VoiceEntryState.confirm.orbScale, VoiceEntryState.idle.orbScale)
        XCTAssertGreaterThan(VoiceEntryState.done.orbScale, VoiceEntryState.idle.orbScale)
        XCTAssertLessThan(VoiceEntryState.error.orbScale, VoiceEntryState.idle.orbScale)

        XCTAssertGreaterThan(VoiceEntryState.recording.pulseOpacity, VoiceEntryState.idle.pulseOpacity)
        XCTAssertGreaterThan(VoiceEntryState.confirm.pulseOpacity, VoiceEntryState.idle.pulseOpacity)
        XCTAssertGreaterThan(VoiceEntryState.done.pulseOpacity, VoiceEntryState.idle.pulseOpacity)

        XCTAssertFalse(VoiceEntryState.idle.showsProgressRing)
        XCTAssertFalse(VoiceEntryState.recording.showsProgressRing)
        XCTAssertFalse(VoiceEntryState.thinking.showsProgressRing)
        XCTAssertTrue(VoiceEntryState.uploading.showsProgressRing)
        XCTAssertTrue(VoiceEntryState.executing.showsProgressRing)
        XCTAssertFalse(VoiceEntryState.confirm.showsProgressRing)
        XCTAssertFalse(VoiceEntryState.error.showsProgressRing)
    }
}
