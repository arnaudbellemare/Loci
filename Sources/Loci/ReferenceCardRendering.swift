import AppKit
import SwiftUI

enum ReferenceCardKind: String, Hashable, Sendable {
    case instagram
    case xPost
    case website
    case image
    case video
    case pdf
    case document
    case note
    case fallback
}

struct ReferenceCardPresentation: Hashable, Sendable {
    var kind: ReferenceCardKind
    var title: String
    var body: String?
    var sourceLabel: String
    var secondaryLabel: String?
    var badge: String
    var mediaCount: Int?
}

enum ReferenceCardResolver {
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "tiff", "tif", "heic", "heif", "bmp", "svg"
    ]
    private static let videoExtensions: Set<String> = [
        "mov", "mp4", "m4v", "webm", "avi", "mkv", "mpeg", "mpg"
    ]
    private static let noteExtensions: Set<String> = ["md", "txt", "rtf"]
    private static let documentExtensions: Set<String> = [
        "doc", "docx", "pages", "key", "ppt", "pptx", "xls", "xlsx", "csv", "json"
    ]

    static func resolve(item: ReferenceItem, metadata: ReferenceSourceMetadata?) -> ReferenceCardPresentation {
        let url = metadata?.url.flatMap(URL.init(string:)) ?? item.websiteURL
        let host = normalizedHost(url)
        let ext = item.fileExtension
        let title = clean(metadata?.title) ?? clean(item.title) ?? "Untitled reference"
        let body = clean(metadata?.selectedText)
            ?? clean(metadata?.articleMarkdown)
            ?? clean(metadata?.note)
        let mediaCount = metadata?.mediaCount ?? metadata?.imageURLs?.count

        if item.isXBookmark {
            return .init(
                kind: .xPost,
                title: title,
                body: body,
                sourceLabel: xAuthorLabel(url: url),
                secondaryLabel: host ?? "x.com",
                badge: "X POST",
                mediaCount: mediaCount
            )
        }

        if isInstagram(url) {
            return .init(
                kind: .instagram,
                title: title,
                body: body,
                sourceLabel: instagramAuthorLabel(url: url),
                secondaryLabel: relativeDateLabel(metadata?.sourceCreatedAt),
                badge: mediaBadge(metadata: metadata, fallback: "INSTAGRAM"),
                mediaCount: mediaCount
            )
        }

        if videoExtensions.contains(ext) || metadata?.mediaTypes?.contains(where: { $0.lowercased().contains("video") }) == true {
            return .init(kind: .video, title: title, body: nil, sourceLabel: host ?? item.fileName,
                         secondaryLabel: nil, badge: ext.isEmpty ? "VIDEO" : ext.uppercased(), mediaCount: mediaCount)
        }
        if imageExtensions.contains(ext) {
            return .init(kind: .image, title: title, body: nil, sourceLabel: item.fileName,
                         secondaryLabel: nil, badge: ext.isEmpty ? "IMAGE" : ext.uppercased(), mediaCount: nil)
        }
        if ext == "pdf" {
            return .init(kind: .pdf, title: title, body: body, sourceLabel: item.fileName,
                         secondaryLabel: nil, badge: "PDF", mediaCount: nil)
        }
        if item.subtitle == "Quick Note" || noteExtensions.contains(ext) {
            return .init(kind: .note, title: title, body: body, sourceLabel: "Personal note",
                         secondaryLabel: nil, badge: "NOTE", mediaCount: nil)
        }
        if item.kind == .typography || documentExtensions.contains(ext) {
            return .init(kind: .document, title: title, body: body, sourceLabel: item.fileName,
                         secondaryLabel: nil, badge: ext.isEmpty ? "DOCUMENT" : ext.uppercased(), mediaCount: nil)
        }
        if url != nil || item.kind == .website || ext == "webloc" || ["html", "htm"].contains(ext) {
            return .init(kind: .website, title: title, body: body, sourceLabel: host ?? "Website",
                         secondaryLabel: clean(metadata?.source), badge: "WEBSITE", mediaCount: mediaCount)
        }
        return .init(kind: .fallback, title: title, body: body, sourceLabel: item.fileName,
                     secondaryLabel: item.group.rawValue, badge: ext.isEmpty ? "REFERENCE" : ext.uppercased(), mediaCount: nil)
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func normalizedHost(_ url: URL?) -> String? {
        guard var host = url?.host(percentEncoded: false)?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    private static func isInstagram(_ url: URL?) -> Bool {
        guard let host = normalizedHost(url) else { return false }
        return host == "instagram.com" || host.hasSuffix(".instagram.com")
    }

    private static func instagramAuthorLabel(url: URL?) -> String {
        let ignored = Set(["p", "reel", "reels", "stories", "explore", "accounts"])
        let components = url?.pathComponents.filter { $0 != "/" && !$0.isEmpty } ?? []
        if let first = components.first, !ignored.contains(first.lowercased()) {
            return "@\(first)"
        }
        return "Instagram"
    }

    private static func xAuthorLabel(url: URL?) -> String {
        let ignored = Set(["i", "home", "explore", "notifications", "messages", "search", "settings"])
        let components = url?.pathComponents.filter { $0 != "/" && !$0.isEmpty } ?? []
        if let first = components.first, !ignored.contains(first.lowercased()) {
            return "@\(first)"
        }
        return "X"
    }

    private static func mediaBadge(metadata: ReferenceSourceMetadata?, fallback: String) -> String {
        let count = metadata?.mediaCount ?? metadata?.imageURLs?.count ?? 0
        guard count > 1 else { return fallback }
        return "\(count) ITEMS"
    }

    private static func relativeDateLabel(_ value: String?) -> String? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
        guard let date else { return nil }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

struct ReferenceCardRenderer: View {
    var item: ReferenceItem
    var presentation: ReferenceCardPresentation
    var image: NSImage?
    var sourceMetadata: ReferenceSourceMetadata?

    @ViewBuilder
    var body: some View {
        if let image {
            VisualElementCard(
                image: image,
                kind: presentation.kind,
                mediaCount: presentation.mediaCount
            )
        } else {
            switch presentation.kind {
            case .instagram:
                SocialTextElementCard(
                    text: presentation.body ?? presentation.title,
                    attribution: presentation.sourceLabel,
                    source: "Instagram"
                )
            case .xPost:
                let card = XBookmarkDisplay.cardData(item: item, payload: sourceMetadata)
                SocialTextElementCard(
                    text: card.text,
                    attribution: card.handle ?? card.name,
                    source: "X"
                )
            case .website:
                WebsiteReferenceCard(presentation: presentation, image: nil, accent: accent)
            case .image:
                ImageReferenceCard(presentation: presentation, image: nil)
            case .video:
                VideoReferenceCard(presentation: presentation, image: nil)
            case .pdf:
                PaperReferenceCard(presentation: presentation, image: nil, accent: .red)
            case .document:
                PaperReferenceCard(presentation: presentation, image: nil, accent: accent)
            case .note:
                NoteReferenceCard(presentation: presentation, accent: accent)
            case .fallback:
                FallbackReferenceCard(presentation: presentation, accent: accent)
            }
        }
    }

    private var accent: Color { item.theme.colors.dropFirst().first ?? .gray }
}

private struct SocialTextElementCard: View {
    var text: String
    var attribution: String
    var source: String

    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: max(10, proxy.size.height * 0.055)) {
                Text("“")
                    .font(.system(size: min(48, proxy.size.width * 0.22), weight: .light, design: .serif))
                    .foregroundStyle(.black.opacity(0.22))
                    .frame(height: min(28, proxy.size.height * 0.12), alignment: .top)

                Text(text)
                    .font(.system(size: min(18, max(11, proxy.size.width * 0.065)), weight: .medium))
                    .lineSpacing(3)
                    .foregroundStyle(.black.opacity(0.82))
                    .lineLimit(8)

                Spacer(minLength: 0)

                HStack {
                    Text(attribution).lineLimit(1)
                    Spacer()
                    Text(source.uppercased())
                }
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.black.opacity(0.38))
            }
            .padding(max(14, proxy.size.width * 0.085))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.965, green: 0.958, blue: 0.938))
        }
    }
}

/// The board's canonical representation: source-specific extraction goes in,
/// but the strongest visual element comes out without platform chrome.
private struct VisualElementCard: View {
    var image: NSImage
    var kind: ReferenceCardKind
    var mediaCount: Int?

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .overlay(alignment: .topTrailing) {
                if kind == .video {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(7)
                        .background(.black.opacity(0.42), in: Circle())
                        .padding(8)
                } else if let mediaCount, mediaCount > 1 {
                    Text("1/\(mediaCount)")
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.94))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.42), in: Capsule())
                        .padding(8)
                }
            }
    }
}

private struct CardCanvas<Content: View>: View {
    var tint: Color = Color(red: 0.958, green: 0.958, blue: 0.946)
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                tint
                LinearGradient(colors: [.white.opacity(0.55), .clear, .black.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing)
                content
                    .frame(width: proxy.size.width * 0.90, height: proxy.size.height * 0.90)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(.black.opacity(0.075), lineWidth: 0.8) }
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
            }
        }
    }
}

private struct InstagramReferenceCard: View {
    var presentation: ReferenceCardPresentation
    var image: NSImage?

    var body: some View {
        CardCanvas(tint: Color(red: 0.975, green: 0.956, blue: 0.961)) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(AngularGradient(colors: [.purple, .pink, .orange, .purple], center: .center))
                        Circle().fill(.white).padding(2)
                        Circle().fill(Color.black.opacity(0.08)).padding(4)
                    }.frame(width: 25, height: 25)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(presentation.sourceLabel).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                        Text("Instagram").font(.system(size: 7.5, weight: .medium)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "ellipsis").font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 11).frame(height: 43).background(.white)

                media(image, fallbackIcon: "camera.fill")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 11) {
                        Image(systemName: "heart")
                        Image(systemName: "bubble.right")
                        Image(systemName: "paperplane")
                        Spacer()
                        Image(systemName: "bookmark")
                    }.font(.system(size: 11, weight: .medium))
                    Text(presentation.body ?? presentation.title)
                        .font(.system(size: 9.5, weight: .medium)).foregroundStyle(.black.opacity(0.76)).lineLimit(2)
                }
                .padding(11).background(.white)
            }
        }
    }
}

private struct XReferenceCard: View {
    var item: ReferenceItem
    var presentation: ReferenceCardPresentation
    var image: NSImage?
    var metadata: ReferenceSourceMetadata?

    var body: some View {
        let card = XBookmarkDisplay.cardData(item: item, payload: metadata)
        CardCanvas(tint: Color(red: 0.963, green: 0.968, blue: 0.973)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Circle().fill(.black).frame(width: 25, height: 25).overlay { Text("X").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(card.name).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                        Text(card.handle ?? card.sourceLabel).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "ellipsis").foregroundStyle(.secondary)
                }.padding(11)

                Text(card.text).font(.system(size: 10.5, weight: .medium)).lineSpacing(2).foregroundStyle(.black.opacity(0.78)).lineLimit(image == nil ? 6 : 3).padding(.horizontal, 11)

                if let image {
                    Image(nsImage: image).resizable().scaledToFill().frame(maxWidth: .infinity, maxHeight: .infinity).clipped().padding(10)
                } else {
                    Spacer(minLength: 8)
                }

                HStack {
                    Label(card.mediaBadge ?? card.metaLabel, systemImage: card.mediaBadge == nil ? "bookmark.fill" : "photo.on.rectangle")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }.font(.system(size: 7.8, weight: .semibold)).foregroundStyle(.secondary).padding(11).background(.black.opacity(0.025))
            }.background(.white)
        }
    }
}

private struct WebsiteReferenceCard: View {
    var presentation: ReferenceCardPresentation
    var image: NSImage?
    var accent: Color

    var body: some View {
        CardCanvas(tint: Color(red: 0.955, green: 0.963, blue: 0.966)) {
            VStack(spacing: 0) {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill().frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                } else {
                    ZStack {
                        LinearGradient(colors: [accent.opacity(0.52), accent.opacity(0.13), .white], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Text(String(presentation.sourceLabel.prefix(1)).uppercased()).font(.system(size: 48, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.72))
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text(presentation.sourceLabel); Spacer(); Text(presentation.badge) }
                        .font(.system(size: 7.5, weight: .bold)).foregroundStyle(.secondary)
                    Text(presentation.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.black.opacity(0.82)).lineLimit(2)
                    if let body = presentation.body { Text(body).font(.system(size: 8.5)).foregroundStyle(.secondary).lineLimit(1) }
                }.padding(11).background(.white)
            }
        }
    }
}

private struct ImageReferenceCard: View {
    var presentation: ReferenceCardPresentation
    var image: NSImage?
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(red: 0.09, green: 0.09, blue: 0.095)
            if let image { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { Image(systemName: "photo").font(.system(size: 42, weight: .light)).foregroundStyle(.white.opacity(0.28)) }
            Text(presentation.badge).font(.system(size: 7.5, weight: .bold)).foregroundStyle(.white.opacity(0.84)).padding(.horizontal, 7).padding(.vertical, 5).background(.black.opacity(0.52), in: Capsule()).padding(9)
        }
    }
}

private struct VideoReferenceCard: View {
    var presentation: ReferenceCardPresentation
    var image: NSImage?
    var body: some View {
        ZStack {
            Color.black
            if let image { Image(nsImage: image).resizable().scaledToFill().frame(maxWidth: .infinity, maxHeight: .infinity).clipped() }
            else { LinearGradient(colors: [Color(white: 0.20), .black], startPoint: .topLeading, endPoint: .bottomTrailing) }
            Circle().fill(.black.opacity(0.56)).frame(width: 48, height: 48).overlay { Image(systemName: "play.fill").font(.system(size: 18)).foregroundStyle(.white).offset(x: 1) }
            VStack { Spacer(); HStack { VStack(alignment: .leading, spacing: 3) { Text(presentation.title).font(.system(size: 11, weight: .semibold)).lineLimit(1); Text(presentation.badge).font(.system(size: 7.5, weight: .bold)).opacity(0.72) }; Spacer() }.foregroundStyle(.white).padding(11).background(LinearGradient(colors: [.clear, .black.opacity(0.76)], startPoint: .top, endPoint: .bottom)) }
        }
    }
}

private struct PaperReferenceCard: View {
    var presentation: ReferenceCardPresentation
    var image: NSImage?
    var accent: Color
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 0.94, green: 0.935, blue: 0.92)
                VStack(alignment: .leading, spacing: 9) {
                    HStack { Text(presentation.badge).font(.system(size: 8, weight: .bold)).foregroundStyle(.white).padding(.horizontal, 7).padding(.vertical, 4).background(accent, in: Capsule()); Spacer(); Image(systemName: "doc.text").foregroundStyle(.secondary) }
                    if let image { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else {
                        Text(presentation.title).font(.system(size: 13, weight: .semibold)).lineLimit(3)
                        ForEach(0..<6) { index in Capsule().fill(index == 1 ? accent.opacity(0.35) : .black.opacity(0.11)).frame(width: proxy.size.width * [0.55, 0.62, 0.48, 0.58, 0.43, 0.52][index], height: 4) }
                        Spacer()
                    }
                }.padding(15).frame(width: proxy.size.width * 0.72, height: proxy.size.height * 0.84).background(.white).shadow(color: .black.opacity(0.14), radius: 11, y: 6).rotationEffect(.degrees(0.7))
            }
        }
    }
}

private struct NoteReferenceCard: View {
    var presentation: ReferenceCardPresentation
    var accent: Color
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 0.972, green: 0.968, blue: 0.948)
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Image(systemName: "note.text").foregroundStyle(accent); Spacer(); Text("NOTE").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary) }
                    Text(presentation.title).font(.system(size: 15, weight: .semibold)).lineLimit(3)
                    if let body = presentation.body { Text(body).font(.system(size: 10)).lineSpacing(2).foregroundStyle(.black.opacity(0.58)).lineLimit(6) }
                    Spacer()
                }.padding(16).frame(width: proxy.size.width * 0.78, height: proxy.size.height * 0.72).background(Color(red: 1, green: 0.985, blue: 0.88)).overlay(alignment: .top) { Rectangle().fill(accent.opacity(0.55)).frame(height: 4) }.shadow(color: .black.opacity(0.12), radius: 10, y: 6).rotationEffect(.degrees(-1))
            }
        }
    }
}

private struct FallbackReferenceCard: View {
    var presentation: ReferenceCardPresentation
    var accent: Color
    var body: some View {
        CardCanvas {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Image(systemName: "square.stack.3d.up.fill").foregroundStyle(accent); Spacer(); Text(presentation.badge).font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary) }
                Spacer()
                Text(presentation.title).font(.system(size: 15, weight: .semibold)).lineLimit(3)
                Text(presentation.sourceLabel).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }.padding(16).background(.white)
        }
    }
}

@ViewBuilder
private func media(_ image: NSImage?, fallbackIcon: String) -> some View {
    if let image {
        Image(nsImage: image).resizable().scaledToFill().clipped()
    } else {
        ZStack {
            LinearGradient(colors: [Color.purple.opacity(0.56), Color.pink.opacity(0.40), Color.orange.opacity(0.48)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: fallbackIcon).font(.system(size: 36, weight: .light)).foregroundStyle(.white.opacity(0.78))
        }
    }
}
