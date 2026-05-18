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
        #if canImport(ArvioShared)
        return CoreStreamRanker.shared.qualityLabel(text: text)
        #else
        switch qualityRank(text) {
        case 4: return "4K"
        case 3: return "1080p"
        case 2: return "720p"
        case 1: return "480p"
        default: return "Direct"
        }
        #endif
    }

    static func streamScore(
        quality: String,
        size: String,
        addonName: String,
        sourceName: String,
        title: String,
        isPlayable: Bool,
        preferredLanguage: String,
        cached: Bool = false
    ) -> Int {
        #if canImport(ArvioShared)
        return Int(CoreStreamRanker.shared.sourceScore(
            quality: quality,
            size: size,
            addonName: addonName,
            sourceName: sourceName,
            title: title,
            isPlayable: isPlayable,
            preferredLanguage: preferredLanguage,
            cached: cached
        ))
        #else
        var value = isPlayable ? 100_000 : 0
        value += qualityRank(quality) * 10_000
        value += min(99, Int(parseSizeBytes(size) / 1_073_741_824)) * 100
        if !preferredLanguage.isEmpty &&
            [addonName, sourceName, title].joined(separator: " ").localizedCaseInsensitiveContains(preferredLanguage) {
            value += 80
        }
        if cached { value += 20 }
        return value
        #endif
    }

    static func parseSizeBytes(_ text: String) -> Int64 {
        #if canImport(ArvioShared)
        return CoreStreamRanker.shared.parseSizeBytes(text: text)
        #else
        let pattern = #"(\d+\.?\d*)\s*(TB|GB|MB|KB)"#
        guard let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return 0 }
        let parts = String(text[match]).split(separator: " ")
        guard let amount = Double(parts.first ?? "0") else { return 0 }
        let unit = parts.dropFirst().first?.uppercased() ?? ""
        let multiplier: Double
        switch unit {
        case "TB": multiplier = 1_099_511_627_776
        case "GB": multiplier = 1_073_741_824
        case "MB": multiplier = 1_048_576
        case "KB": multiplier = 1024
        default: multiplier = 1
        }
        return Int64(amount * multiplier)
        #endif
    }

    static func xtreamLiveUrl(baseUrl: String, username: String, password: String, streamId: Int) -> String {
        #if canImport(ArvioShared)
        return CoreXtreamPaths.shared.live(baseUrl: baseUrl, username: username, password: password, streamId: Int32(streamId))
        #else
        return "\(baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/live/\(xtreamPathComponent(username))/\(xtreamPathComponent(password))/\(streamId).ts"
        #endif
    }

    static func xtreamMovieUrl(baseUrl: String, username: String, password: String, streamId: Int, fileExtension ext: String) -> String {
        #if canImport(ArvioShared)
        return CoreXtreamPaths.shared.movie(baseUrl: baseUrl, username: username, password: password, streamId: Int32(streamId), fileExtension: ext)
        #else
        return "\(baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/movie/\(xtreamPathComponent(username))/\(xtreamPathComponent(password))/\(streamId).\(xtreamPathComponent(ext))"
        #endif
    }

    static func xtreamSeriesUrl(baseUrl: String, username: String, password: String, episodeId: String, fileExtension ext: String) -> String {
        #if canImport(ArvioShared)
        return CoreXtreamPaths.shared.series(baseUrl: baseUrl, username: username, password: password, episodeId: episodeId, fileExtension: ext)
        #else
        return "\(baseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/series/\(xtreamPathComponent(username))/\(xtreamPathComponent(password))/\(xtreamPathComponent(episodeId)).\(xtreamPathComponent(ext))"
        #endif
    }

    static func m3uAttribute(line: String, key: String) -> String? {
        #if canImport(ArvioShared)
        return CoreM3uParser.shared.attribute(line: line, key: key)
        #else
        let pattern = #"([A-Za-z0-9_-]+)="([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsText.length))
        for match in matches where match.numberOfRanges == 3 {
            let name = nsText.substring(with: match.range(at: 1))
            if name.caseInsensitiveCompare(key) == .orderedSame {
                let value = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
        }
        return nil
        #endif
    }

    static func m3uDisplayName(line: String) -> String {
        #if canImport(ArvioShared)
        return CoreM3uParser.shared.displayName(line: line)
        #else
        return m3uAttribute(line: line, key: "tvg-name")
            ?? line.split(separator: ",", maxSplits: 1).last.map(String.init)?.nilIfBlank
            ?? "Channel"
        #endif
    }

    static func xtreamPathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
