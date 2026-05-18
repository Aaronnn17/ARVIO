import Foundation

#if canImport(ArvioShared)
import ArvioShared
#endif

enum SharedCoreBridge {
    static func normalizeTitle(_ value: String) -> String {
        #if canImport(ArvioShared)
        return CoreTitleMatcher.shared.normalize(value: value)
        #else
        let lower = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let scalars = lower.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(scalars)
            .split(separator: " ")
            .filter { token in
                let value = String(token)
                return value != "the" && value != "a" && value != "an"
            }
            .joined(separator: " ")
        #endif
    }

    static func qualityRank(_ quality: String) -> Int {
        #if canImport(ArvioShared)
        return Int(CoreStreamRanker.shared.qualityRank(quality: quality))
        #else
        let value = quality.lowercased()
        if value.contains("2160") || value.contains("4k") || value.contains("uhd") { return 4 }
        if value.contains("1080") || value.contains("fhd") { return 3 }
        if value.contains("720") || value.contains("hd") { return 2 }
        if value.contains("480") || value.contains("sd") { return 1 }
        return 0
        #endif
    }

    static func qualityLabel(from text: String) -> String {
        switch qualityRank(text) {
        case 4: return "4K"
        case 3: return "1080p"
        case 2: return "720p"
        case 1: return "480p"
        default: return "Direct"
        }
    }

    static func xtreamPathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}
