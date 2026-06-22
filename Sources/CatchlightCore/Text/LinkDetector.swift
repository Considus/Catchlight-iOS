//
//  LinkDetector.swift
//  CatchlightCore — clickable links in Take bodies (owner 2026-06-22)
//
//  Pure URL detection over a Take's plain text, so it's unit-testable without a
//  host app. Two passes:
//    1. `NSDataDetector` — schemed URLs and `www.` links (the reliable path).
//    2. Bare domains with NO scheme (e.g. "catchlight.app") — matched by a
//       conservative regex and accepted ONLY when the TLD is in a curated
//       common set, then linked with an assumed `https://`. The TLD gate is what
//       keeps "readme.md", "config.json", "e.g.", or "Mr.Smith" from becoming
//       links — precision over recall, since a false link in a personal note is
//       worse than missing a niche TLD (which still works if typed with https://).
//

import Foundation

public enum LinkDetector {

    /// One detected link: the range in the ORIGINAL string and the resolved URL
    /// (with `https://` assumed for bare domains).
    public struct Match: Equatable {
        public let range: Range<String.Index>
        public let url: URL
    }

    private static let dataDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue)

    // A bare domain: labels separated by dots, a 2–24 letter TLD (captured for the
    // curated-set check), and an optional path. Case-insensitive so an auto-capitalised
    // first letter ("Considus.app", common when a URL is typed first) still links; the
    // curated-TLD gate below — not the casing — is what keeps "Mr.Smith" inert. The
    // lookbehind avoids matching inside an email's domain or a longer token.
    private static let bareDomain = try? NSRegularExpression(
        pattern: #"(?<![@./\w-])((?:[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+([a-zA-Z]{2,24}))(/[^\s]*)?"#)

    /// Curated common TLDs we'll auto-link without a scheme. Generous but bounded —
    /// expand as needed (owner can add niche TLDs). NOT exhaustive by design.
    static let commonTLDs: Set<String> = [
        "com", "org", "net", "io", "co", "app", "dev", "ai", "me", "info", "biz",
        "xyz", "online", "site", "store", "tech", "blog", "page", "link", "cloud",
        "email", "news", "tv", "fm", "gg", "so", "to", "ly", "sh", "st", "design",
        "studio", "agency", "uk", "us", "ca", "au", "de", "fr", "nl", "es", "it",
        "eu", "ie", "nz", "in", "jp", "cn", "br", "za", "ch", "se", "no",
    ]

    /// All links in `text`, ordered by position, non-overlapping (schemed/www links
    /// win over a bare-domain match in the same span).
    public static func detect(in text: String) -> [Match] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var matches: [Match] = []
        var taken: [NSRange] = []

        if let detector = dataDetector {
            for m in detector.matches(in: text, range: full) {
                guard let url = m.url, let r = Range(m.range, in: text) else { continue }
                let matched = ns.substring(with: m.range)
                // NSDataDetector catches common bare/`www.` domains but defaults them to
                // `http://`. When the user typed no scheme, assume `https://` so every
                // schemeless domain links consistently (owner 2026-06-22); an explicitly
                // typed scheme (http:// or anything else) is preserved as-is.
                let resolved: URL
                if matched.contains("://") {
                    guard url.scheme != nil else { continue }
                    resolved = url
                } else {
                    resolved = URL(string: "https://\(matched)") ?? url
                }
                matches.append(Match(range: r, url: resolved))
                taken.append(m.range)
            }
        }

        if let regex = bareDomain {
            for m in regex.matches(in: text, range: full) {
                if taken.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) { continue }
                let tldRange = m.range(at: 2)
                guard tldRange.location != NSNotFound else { continue }
                let tld = ns.substring(with: tldRange).lowercased()
                guard commonTLDs.contains(tld) else { continue }
                guard let r = Range(m.range, in: text) else { continue }
                let raw = ns.substring(with: m.range)
                guard let url = URL(string: "https://\(raw)") else { continue }
                matches.append(Match(range: r, url: url))
            }
        }

        return matches.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }
}
