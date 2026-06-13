import Foundation

enum MacRuntimeMode {
    private static var arguments: [String] {
        ProcessInfo.processInfo.arguments
    }

    static var isPreviewAuthenticated: Bool {
        isPreviewAuthenticated(arguments: arguments)
    }

    static var usesPreviewData: Bool {
        usesPreviewData(arguments: arguments)
    }

    static var disablesGlobalHotkey: Bool {
        disablesGlobalHotkey(arguments: arguments)
    }

    static func isPreviewAuthenticated(arguments: [String]) -> Bool {
        arguments.contains("-SmartShadowPreviewAuthenticated")
    }

    static func usesPreviewData(arguments: [String]) -> Bool {
        isPreviewAuthenticated(arguments: arguments) || arguments.contains("-SmartShadowForcePreviewData")
    }

    static func disablesGlobalHotkey(arguments: [String]) -> Bool {
        isPreviewAuthenticated(arguments: arguments) || usesPreviewData(arguments: arguments)
    }
}
