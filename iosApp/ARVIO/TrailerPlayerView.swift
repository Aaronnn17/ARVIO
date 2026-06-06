import SwiftUI
import WebKit

struct TrailerPlayerView: View {
    let url: URL
    var soundEnabled: Bool = true
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let embedURL = Self.embedURL(from: url, soundEnabled: soundEnabled) {
                TrailerWebView(url: embedURL)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 12) {
                    Text("Trailer unavailable")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(ArvioTheme.textPrimary)
                    Link("Open trailer", destination: url)
                        .buttonStyle(.borderedProminent)
                        .tint(ArvioTheme.gold)
                }
            }
            Button("Close", action: onClose)
                .buttonStyle(.borderedProminent)
                .tint(ArvioTheme.gold)
                .padding(24)
        }
    }

    private static func embedURL(from url: URL, soundEnabled: Bool) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let host = components.host?.lowercased() ?? ""
        let id: String?
        if host.contains("youtu.be") {
            id = url.pathComponents.dropFirst().first
        } else if host.contains("youtube.com") {
            id = components.queryItems?.first(where: { $0.name == "v" })?.value
        } else {
            id = nil
        }
        guard let id, !id.isEmpty else { return url }
        let muted = soundEnabled ? "0" : "1"
        return URL(string: "https://www.youtube.com/embed/\(id)?autoplay=1&playsinline=1&rel=0&mute=\(muted)")
    }
}

private struct TrailerWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.scrollView.isScrollEnabled = false
        view.backgroundColor = .black
        view.isOpaque = false
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url != url {
            uiView.load(URLRequest(url: url))
        }
    }
}
