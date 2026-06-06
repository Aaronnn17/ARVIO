import SwiftUI

struct PosterBackdrop: View {
    let item: MediaItem
    var preferPoster = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: item.palette.map(Color.init(hex:)),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let url = preferredImageURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    }
                }
            }

            LinearGradient(colors: [Color.black.opacity(0.05), Color.black.opacity(0.52)], startPoint: .top, endPoint: .bottom)

            if item.backdropURL == nil && item.posterURL == nil {
                Text(item.title.uppercased())
                    .font(.system(size: 27, weight: .bold, design: .serif))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .multilineTextAlignment(.center)
                    .padding(18)
            }
        }
        .clipped()
    }

    private var preferredImageURL: URL? {
        preferPoster ? (item.posterURL ?? item.backdropURL) : (item.backdropURL ?? item.posterURL)
    }
}

struct MediaCard: View {
    let item: MediaItem
    var layout = "Landscape"
    var onSelect: ((MediaItem) -> Void)?

    var body: some View {
        Button {
            onSelect?(item)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                PosterBackdrop(item: item, preferPoster: isPortrait)
                    .frame(width: cardWidth, height: imageHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(ArvioTheme.border, lineWidth: 1)
                    )

                Text(item.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ArvioTheme.textPrimary)
                    .lineLimit(1)

                Text(item.subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ArvioTheme.textTertiary)
                    .lineLimit(1)

                if item.progress > 0 {
                    ProgressView(value: item.progress)
                        .tint(ArvioTheme.gold)
                        .frame(width: cardWidth)
                }
            }
            .frame(width: cardWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private var isPortrait: Bool {
        layout == "Portrait"
    }

    private var cardWidth: CGFloat {
        switch layout {
        case "Portrait": return 156
        case "Compact": return 170
        default: return 210
        }
    }

    private var imageHeight: CGFloat {
        switch layout {
        case "Portrait": return 234
        case "Compact": return 96
        default: return 118
        }
    }
}

struct PrimaryButton: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 8).fill(ArvioTheme.gold))
    }
}

struct SecondaryButton: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(ArvioTheme.textPrimary)
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 8).fill(ArvioTheme.panel))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArvioTheme.border, lineWidth: 1))
    }
}
