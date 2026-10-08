import Foundation

/// Which widgets a typed query names, for the home search ("postcard" →
/// the Postcard widget) and the Widgets tab's own filter (Wes, 2026-10-08).
/// A widget matches when its title contains the query, or — for queries of
/// 3+ characters — a word of its subtitle or id starts with it ("run" →
/// FavRun, "weather" → Weather, "mail" → Fridge Mail). Title hits lead.
public enum WidgetSearchMatcher {
    public static func matches(_ query: String, in descriptors: [FavWidgetDescriptor], limit: Int = .max) -> [FavWidgetDescriptor] {
        let q = normalize(query)
        guard !q.isEmpty else { return [] }
        var titleHits: [FavWidgetDescriptor] = []
        var otherHits: [FavWidgetDescriptor] = []
        for d in descriptors {
            let title = normalize(d.title)
            if title.contains(q) || normalize(d.title.replacingOccurrences(of: " ", with: "")).contains(q) {
                titleHits.append(d)
            } else if q.count >= 3, (words(d.subtitle) + words(d.id)).contains(where: { $0.hasPrefix(q) }) {
                otherHits.append(d)
            }
        }
        return Array((titleHits + otherHits).prefix(limit))
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func words(_ s: String) -> [String] {
        normalize(s).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
}
