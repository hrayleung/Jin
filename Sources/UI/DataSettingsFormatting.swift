import Foundation

enum DataSettingsFormatting {
    static func formattedSize(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 bytes" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }

    /// Fraction of `total` represented by `bytes` (0 when total is non-positive).
    static func shareFraction(bytes: Int64, total: Int64) -> Double {
        guard total > 0, bytes > 0 else { return 0 }
        return Double(bytes) / Double(total)
    }

    /// Whole-number percentage of `total`. Non-zero bytes that would round to 0% report 1%.
    /// Returns `nil` when the share should be omitted (zero total or zero bytes).
    static func sharePercent(bytes: Int64, total: Int64) -> Int? {
        guard total > 0, bytes > 0 else { return nil }
        let raw = Double(bytes) / Double(total) * 100
        let rounded = Int(raw.rounded())
        if rounded == 0 { return 1 }
        return min(100, rounded)
    }

    /// Human-readable share such as `"88%"`, or `nil` when it should be omitted.
    static func formattedShare(bytes: Int64, total: Int64) -> String? {
        guard let percent = sharePercent(bytes: bytes, total: total) else { return nil }
        return "\(percent)%"
    }
}
