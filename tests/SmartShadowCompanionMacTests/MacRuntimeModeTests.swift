import XCTest
@testable import SmartShadowCompanionMac

final class MacRuntimeModeTests: XCTestCase {
    func testPreviewAuthenticatedUsesPreviewDataAndDisablesGlobalHotkey() {
        let arguments = ["/tmp/SmartShadowCompanionMac", "-SmartShadowPreviewAuthenticated"]

        XCTAssertTrue(MacRuntimeMode.isPreviewAuthenticated(arguments: arguments))
        XCTAssertTrue(MacRuntimeMode.usesPreviewData(arguments: arguments))
        XCTAssertTrue(MacRuntimeMode.disablesGlobalHotkey(arguments: arguments))
    }

    func testForcePreviewDataDoesNotMarkAuthenticationButDisablesNetworkDependentPreview() {
        let arguments = ["/tmp/SmartShadowCompanionMac", "-SmartShadowForcePreviewData"]

        XCTAssertFalse(MacRuntimeMode.isPreviewAuthenticated(arguments: arguments))
        XCTAssertTrue(MacRuntimeMode.usesPreviewData(arguments: arguments))
        XCTAssertTrue(MacRuntimeMode.disablesGlobalHotkey(arguments: arguments))
    }

    func testNormalLaunchDoesNotUsePreviewMode() {
        let arguments = ["/Applications/SmartShadowCompanionMac.app/Contents/MacOS/SmartShadowCompanionMac"]

        XCTAssertFalse(MacRuntimeMode.isPreviewAuthenticated(arguments: arguments))
        XCTAssertFalse(MacRuntimeMode.usesPreviewData(arguments: arguments))
        XCTAssertFalse(MacRuntimeMode.disablesGlobalHotkey(arguments: arguments))
    }
}
