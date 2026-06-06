import Foundation
import JavaScriptCore

enum NuvioJSRuntime {
    static func execute(
        scraper: PluginScraperRecord,
        code: String,
        tmdbId: String,
        mediaType: String,
        season: Int?,
        episode: Int?,
        customUserAgent: String
    ) async -> [ResolvedStream] {
        run(
            scraper: scraper,
            code: code,
            tmdbId: tmdbId,
            mediaType: mediaType,
            season: season,
            episode: episode,
            customUserAgent: customUserAgent
        )
    }

    private static func run(
        scraper: PluginScraperRecord,
        code: String,
        tmdbId: String,
        mediaType: String,
        season: Int?,
        episode: Int?,
        customUserAgent: String
    ) -> [ResolvedStream] {
        guard let context = JSContext() else { return [] }
        var resultJson: String?

        context.exceptionHandler = { _, exception in
            print("[NuvioJSRuntime] \(scraper.name): \(exception?.toString() ?? "Unknown JavaScript exception")")
        }

        let nativeFetch: @convention(block) (String, String, String, String) -> String = { url, method, headersJson, body in
            fetchSynchronously(
                urlString: url,
                method: method,
                headersJson: headersJson,
                body: body,
                customUserAgent: customUserAgent
            )
        }
        let captureResult: @convention(block) (String) -> Void = { json in
            resultJson = json
        }

        context.setObject(nativeFetch, forKeyedSubscript: "__native_fetch" as NSString)
        context.setObject(captureResult, forKeyedSubscript: "__capture_result" as NSString)

        context.evaluateScript(polyfills())
        context.evaluateScript("""
            var module = { exports: {} };
            var exports = module.exports;
            (function() {
            \(code)
            })();
        """)

        let seasonArg = season.map(String.init) ?? "undefined"
        let episodeArg = episode.map(String.init) ?? "undefined"
        context.evaluateScript("""
            (function() {
                function done(value) {
                    try {
                        __capture_result(JSON.stringify(value || []));
                    } catch (jsonError) {
                        __capture_result("[]");
                    }
                }
                function fail(error) {
                    try {
                        console.error("Nuvio scraper failed", error && (error.stack || error.message || error));
                    } catch (_) {}
                    __capture_result("[]");
                }
                try {
                    var fn =
                        module.exports.getStreams ||
                        module.exports.scrape ||
                        module.exports.search ||
                        module.exports.default ||
                        globalThis.getStreams ||
                        globalThis.scrape ||
                        globalThis.search;
                    if (typeof fn !== "function") {
                        fail(new Error("No compatible scraper entry point"));
                        return;
                    }
                    var output = fn(\(jsString(tmdbId)), \(jsString(mediaType)), \(seasonArg), \(episodeArg));
                    if (output && typeof output.then === "function") {
                        output.then(done).catch(fail);
                    } else {
                        done(output);
                    }
                } catch (error) {
                    fail(error);
                }
            })();
        """)

        let deadline = Date().addingTimeInterval(60)
        while resultJson == nil && Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }

        return parseResults(
            resultJson ?? "[]",
            scraper: scraper,
            customUserAgent: customUserAgent
        )
    }

    private static func fetchSynchronously(
        urlString: String,
        method: String,
        headersJson: String,
        body: String,
        customUserAgent: String
    ) -> String {
        guard let url = URL(string: urlString) else {
            return jsonString([
                "ok": false,
                "status": 0,
                "statusText": "Invalid URL",
                "url": urlString,
                "body": "",
                "headers": [:]
            ])
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.uppercased()
        var headers = decodeHeaders(headersJson)
        if !headers.keys.contains(where: { $0.caseInsensitiveCompare("User-Agent") == .orderedSame }) {
            headers["User-Agent"] = customUserAgent.nilIfBlank ??
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        }
        headers["Accept-Encoding"] = "identity"
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        if ["POST", "PUT", "PATCH"].contains(request.httpMethod ?? ""),
           !body.isEmpty {
            request.httpBody = Data(body.utf8)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var payload: [String: Any] = [
            "ok": false,
            "status": 0,
            "statusText": "Timed out",
            "url": url.absoluteString,
            "body": "",
            "headers": [:]
        ]

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        let session = URLSession(configuration: config)
        let task = session.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                payload["statusText"] = error.localizedDescription
                return
            }
            let http = response as? HTTPURLResponse
            var responseHeaders: [String: String] = [:]
            http?.allHeaderFields.forEach { key, value in
                responseHeaders[String(describing: key).lowercased()] = String(describing: value)
            }
            payload = [
                "ok": http.map { (200..<300).contains($0.statusCode) } ?? false,
                "status": http?.statusCode ?? 0,
                "statusText": HTTPURLResponse.localizedString(forStatusCode: http?.statusCode ?? 0),
                "url": response?.url?.absoluteString ?? url.absoluteString,
                "body": String(data: data ?? Data(), encoding: .utf8) ?? "",
                "headers": responseHeaders
            ]
        }
        task.resume()

        if semaphore.wait(timeout: .now() + 32) == .timedOut {
            task.cancel()
        }
        session.finishTasksAndInvalidate()
        return jsonString(payload)
    }

    private static func decodeHeaders(_ raw: String) -> [String: String] {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return dictionary.reduce(into: [:]) { result, entry in
            let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(describing: entry.value).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty, key.caseInsensitiveCompare("Accept-Encoding") != .orderedSame else {
                return
            }
            result[key] = value
        }
    }

    private static func parseResults(
        _ json: String,
        scraper: PluginScraperRecord,
        customUserAgent: String
    ) -> [ResolvedStream] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        return array.compactMap { item in
            guard let rawURL = stringValue(item["url"]) ?? stringValue((item["url"] as? [String: Any])?["url"]) else {
                return nil
            }
            let split = splitUrlAndHeaders(rawURL)
            let declaredHeaders = (item["headers"] as? [String: Any])?.reduce(into: [String: String]()) { result, entry in
                result[entry.key] = String(describing: entry.value)
            } ?? [:]
            let requestHeaders = playbackHeaders(
                extra: mergeHeaders(declaredHeaders, split.1),
                customUserAgent: customUserAgent
            )
            let normalizedURL = normalizePlaybackUrl(split.0)
            let url = normalizedURL.flatMap(URL.init(string:))
            let title = stringValue(item["title"]) ??
                stringValue(item["name"]) ??
                scraper.name
            let sourceName = stringValue(item["provider"]) ??
                stringValue(item["name"]) ??
                scraper.name
            let text = [title, sourceName, stringValue(item["quality"]), stringValue(item["size"])]
                .compactMap { $0 }
                .joined(separator: " ")

            return ResolvedStream(
                addonId: scraper.id,
                addonName: scraper.name,
                sourceName: sourceName,
                title: title,
                quality: stringValue(item["quality"]) ?? quality(from: text),
                size: stringValue(item["size"]) ?? size(from: text),
                url: url,
                requestHeaders: requestHeaders,
                subtitles: parseSubtitles(item["subtitles"]),
                isPlayable: url.map(isDirectPlayable) ?? false,
                resumePositionSeconds: nil
            )
        }
    }

    private static func parseSubtitles(_ raw: Any?) -> [ResolvedSubtitle] {
        guard let subtitles = raw as? [[String: Any]] else { return [] }
        return subtitles.compactMap { item in
            guard let rawURL = stringValue(item["url"]),
                  let url = URL(string: rawURL) else { return nil }
            let language = stringValue(item["language"]) ??
                stringValue(item["lang"]) ??
                "sub"
            return ResolvedSubtitle(
                id: stringValue(item["id"]) ?? "\(language)-\(rawURL)",
                label: stringValue(item["label"]) ?? language.uppercased(),
                language: language,
                url: url
            )
        }
    }

    private static func polyfills() -> String {
        """
        var console = {
            log: function(){},
            info: function(){},
            debug: function(){},
            warn: function(){},
            error: function(){}
        };
        if (typeof globalThis.global === "undefined") globalThis.global = globalThis;
        if (typeof globalThis.window === "undefined") globalThis.window = globalThis;
        if (typeof globalThis.self === "undefined") globalThis.self = globalThis;
        if (typeof setTimeout === "undefined") {
            var setTimeout = function(fn) {
                if (typeof fn === "function") fn();
                return 0;
            };
            var clearTimeout = function() {};
        }
        var fetch = function(url, options) {
            options = options || {};
            var method = (options.method || "GET").toUpperCase();
            var headers = options.headers || {};
            var body = options.body || "";
            var parsed = JSON.parse(__native_fetch(String(url), method, JSON.stringify(headers), String(body || "")));
            var response = {
                ok: parsed.ok,
                status: parsed.status,
                statusText: parsed.statusText,
                url: parsed.url,
                headers: {
                    get: function(name) {
                        return parsed.headers[String(name).toLowerCase()] || null;
                    }
                },
                text: function() { return Promise.resolve(parsed.body || ""); },
                json: function() {
                    try {
                        return Promise.resolve(parsed.body ? JSON.parse(parsed.body) : null);
                    } catch (_) {
                        return Promise.resolve(null);
                    }
                }
            };
            return Promise.resolve(response);
        };
        if (typeof URLSearchParams === "undefined") {
            var URLSearchParams = function(init) {
                this._params = {};
                var source = String(init || "").replace(/^\\?/, "");
                if (source.length) {
                    var parts = source.split("&");
                    for (var i = 0; i < parts.length; i++) {
                        var pair = parts[i].split("=");
                        if (pair[0]) this._params[decodeURIComponent(pair[0])] = decodeURIComponent(pair[1] || "");
                    }
                }
            };
            URLSearchParams.prototype.get = function(key) { return this._params[key] || null; };
            URLSearchParams.prototype.set = function(key, value) { this._params[key] = String(value); };
            URLSearchParams.prototype.append = function(key, value) { this._params[key] = String(value); };
            URLSearchParams.prototype.toString = function() {
                var output = [];
                for (var key in this._params) {
                    output.push(encodeURIComponent(key) + "=" + encodeURIComponent(this._params[key]));
                }
                return output.join("&");
            };
        }
        if (typeof require === "undefined") {
            var require = function(name) {
                throw new Error("Module '" + name + "' is not available in the iOS JavaScriptCore runtime");
            };
        }
        if (!Array.prototype.flat) {
            Array.prototype.flat = function(depth) {
                depth = depth === undefined ? 1 : depth;
                return depth > 0 ? this.reduce(function(acc, item) {
                    return acc.concat(Array.isArray(item) ? item.flat(depth - 1) : item);
                }, []) : this.slice();
            };
        }
        if (!Array.prototype.flatMap) {
            Array.prototype.flatMap = function(callback) { return this.map(callback).flat(); };
        }
        if (!Object.entries) {
            Object.entries = function(obj) {
                var output = [];
                for (var key in obj) if (Object.prototype.hasOwnProperty.call(obj, key)) output.push([key, obj[key]]);
                return output;
            };
        }
        """
    }

    private static func splitUrlAndHeaders(_ rawUrl: String) -> (String?, [String: String]) {
        guard let separator = rawUrl.firstIndex(of: "|") else {
            return (rawUrl.trimmingCharacters(in: .whitespacesAndNewlines), [:])
        }
        let baseUrl = String(rawUrl[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rawHeaders = String(rawUrl[rawUrl.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        var headers: [String: String] = [:]
        rawHeaders.split(separator: "&").forEach { entry in
            let text = String(entry)
            guard let equals = text.firstIndex(of: "=") else { return }
            let key = String(text[..<equals]).removingPercentEncoding ?? String(text[..<equals])
            let value = String(text[text.index(after: equals)...]).removingPercentEncoding ?? String(text[text.index(after: equals)...])
            if isSafeHeader(key: key, value: value) {
                headers[key] = value
            }
        }
        return (baseUrl, headers)
    }

    private static func normalizePlaybackUrl(_ rawUrl: String?) -> String? {
        let value = rawUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty, !value.lowercased().hasPrefix("magnet:") else { return nil }
        if value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://") {
            return value
        }
        if value.hasPrefix("//") {
            return "https:\(value)"
        }
        if !value.contains("://"), value.contains(".") {
            return "https://\(value)"
        }
        return value
    }

    private static func playbackHeaders(extra: [String: String], customUserAgent: String) -> [String: String] {
        var headers: [String: String] = [
            "User-Agent": customUserAgent.nilIfBlank ??
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            "Accept": "*/*",
            "Accept-Encoding": "identity"
        ]
        for (key, value) in extra where isSafeHeader(key: key, value: value) {
            headers[key] = value
        }
        return headers
    }

    private static func mergeHeaders(_ left: [String: String], _ right: [String: String]) -> [String: String] {
        var output = left
        right.forEach { output[$0.key] = $0.value }
        return output
    }

    private static func isSafeHeader(key: String, value: String) -> Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !key.contains("\n") &&
            !key.contains("\r") &&
            !value.contains("\n") &&
            !value.contains("\r")
    }

    private static func isDirectPlayable(url: URL) -> Bool {
        let value = url.absoluteString.lowercased()
        guard value.hasPrefix("http://") || value.hasPrefix("https://") else { return false }
        return !value.contains("youtube.com/watch") && !value.contains("youtu.be/")
    }

    private static func quality(from text: String) -> String {
        let label = SharedCoreBridge.qualityLabel(from: text)
        return label == "Direct" ? "Unknown" : label
    }

    private static func size(from text: String) -> String {
        let pattern = #"(\d+\.?\d*)\s*(GB|MB|TB|KB)"#
        guard let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return ""
        }
        return String(text[match])
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String {
            return value.nilIfBlank
        }
        if let value {
            return String(describing: value).nilIfBlank
        }
        return nil
    }

    private static func jsString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return encoded
    }

    private static func jsonString(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
