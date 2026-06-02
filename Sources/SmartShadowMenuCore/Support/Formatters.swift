import Foundation

extension JSONDecoder {
    static var smartShadow: JSONDecoder {
        JSONDecoder()
    }
}

public enum SmartShadowFormatters {
    public static func relativeAge(seconds: Int?) -> String {
        guard let seconds else { return "未知" }
        if seconds < 60 { return "\(seconds) 秒前" }
        if seconds < 3_600 { return "\(seconds / 60) 分钟前" }
        return "\(seconds / 3_600) 小时前"
    }

    public static func shortTimestamp(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "无记录" }
        return value.replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "Z", with: "")
    }

    public static func compactPathDirectory(_ path: String?) -> String? {
        guard let path else { return nil }
        return URL(fileURLWithPath: path).deletingLastPathComponent().path
    }
}
