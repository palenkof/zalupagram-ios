import Foundation
import TextFormat
import ZalupaGramCore

// ZalupaGram fork: removes tracking parameters (utm_*, fbclid, si on
// YouTube...) from links in sent messages, the same as in ZalupaGram
// Desktop (zg_links.cpp).

// Parameters that only track where a link came from, on any site.
private let trackingAnywhere: Set<String> = [
    "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid",
    "ysclid", "igshid", "igsh", "mc_cid", "mc_eid", "_hsenc", "_hsmi",
    "mkt_tok", "twclid", "ttclid", "srsltid", "_openstat", "oly_anon_id",
    "oly_enc_id", "vero_id", "wickedid",
]

// Parameters with common names, removed only on the sites using them.
private let trackingBySite: [(String, Set<String>)] = [
    ("youtube.com", ["si", "feature", "pp"]),
    ("youtu.be", ["si", "feature"]),
    ("spotify.com", ["si", "context"]),
    ("twitter.com", ["s", "t", "ref_src", "ref_url"]),
    ("x.com", ["s", "t", "ref_src", "ref_url"]),
    ("tiktok.com", ["_r", "_t", "is_from_webapp", "sender_device"]),
    ("instagram.com", ["img_index"]),
    ("reddit.com", ["share_id", "rdt"]),
    ("aliexpress.com", ["spm", "scm", "pvid", "algo_pvid"]),
    ("aliexpress.ru", ["spm", "scm", "pvid", "algo_pvid"]),
    ("ozon.ru", ["asb", "asb2"]),
]

private func hostMatches(_ host: String, _ site: String) -> Bool {
    return host == site || host.hasSuffix("." + site)
}

private func isTracking(host: String, key: String) -> Bool {
    let lower = key.lowercased()
    if lower.hasPrefix("utm_") || trackingAnywhere.contains(lower) {
        return true
    }
    for (site, params) in trackingBySite where hostMatches(host, site) {
        if params.contains(key) {
            return true
        }
    }
    return false
}

// Keeps the rest of the link exactly as typed.
public func zalupaGramStripTracking(_ link: String) -> String {
    guard let question = link.firstIndex(of: "?") else {
        return link
    }
    let end = link[question...].firstIndex(of: "#") ?? link.endIndex
    let candidate = link.contains("://") ? link : "http://" + link
    guard let host = URL(string: candidate)?.host?.lowercased(), !host.isEmpty else {
        return link
    }
    let query = link[link.index(after: question) ..< end]
    var kept: [Substring] = []
    var removed = false
    for pair in query.split(separator: "&", omittingEmptySubsequences: true) {
        let key = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first ?? pair
        if !key.isEmpty && isTracking(host: host, key: String(key)) {
            removed = true
        } else {
            kept.append(pair)
        }
    }
    if !removed {
        return link
    }
    var result = String(link[..<question])
    if !kept.isEmpty {
        result += "?" + kept.joined(separator: "&")
    }
    return result + link[end...]
}

// Cleans links in a message prepared for sending, if the option is on.
public func zalupaGramStripTrackingFromLinks(_ text: NSAttributedString) -> NSAttributedString {
    if !ZalupaGramCore.option(.stripTracking) || text.length == 0 {
        return text
    }
    let result = NSMutableAttributedString(attributedString: text)

    // Links behind text.
    result.enumerateAttribute(ChatTextInputAttributes.textUrl, in: NSRange(location: 0, length: result.length), options: [], using: { value, range, _ in
        if let value = value as? ChatTextInputTextUrlAttribute {
            let cleaned = zalupaGramStripTracking(value.url)
            if cleaned != value.url {
                result.addAttribute(ChatTextInputAttributes.textUrl, value: ChatTextInputTextUrlAttribute(url: cleaned), range: range)
            }
        }
    })

    // Links typed in the text, from the end so the ranges stay valid.
    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
        let string = result.string
        let matches = detector.matches(in: string, options: [], range: NSRange(location: 0, length: (string as NSString).length))
        for match in matches.reversed() {
            let link = (string as NSString).substring(with: match.range)
            if link.contains("@") && !link.contains("/") {
                continue // An email.
            }
            let cleaned = zalupaGramStripTracking(link)
            if cleaned != link {
                result.replaceCharacters(in: match.range, with: cleaned)
            }
        }
    }
    return result
}
