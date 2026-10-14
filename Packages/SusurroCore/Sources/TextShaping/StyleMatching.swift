import Foundation

/// How bundle IDs and hosts are compared with the rules of a table. A rule matches at a dot: `slack.com` matches
/// `app.slack.com` and not `notslack.com`, and `com.apple.Terminal` matches `com.apple.Terminal.helper` and not
/// `com.apple.TerminalX`.
enum StyleMatching {
    /// The host of a page URL as it is compared: lower case, with a leading `www.` removed. A URL without a scheme, as
    /// `mail.google.com/inbox`, reads as if it had one. Nil when there is no host.
    static func host(ofURL url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let host = URL(string: withScheme)?.host(percentEncoded: false), !host.isEmpty else { return nil }
        return normalized(host: host)
    }

    /// A host as it is compared: lower case, without `www.`.
    static func normalized(host: String) -> String {
        let lowered = host.lowercased()
        return lowered.hasPrefix("www.") ? String(lowered.dropFirst(4)) : lowered
    }

    /// Whether `host` is the host of `rule` or a subdomain of it. Both are normalized first.
    static func host(_ host: String, matches rule: String) -> Bool {
        let host = normalized(host: host)
        let rule = normalized(host: rule)
        return host == rule || host.hasSuffix("." + rule)
    }

    /// Whether `bundleID` is the ID of `rule` or an ID under it. A rule that ends in a dot is a plain prefix.
    static func bundleID(_ bundleID: String, matches rule: String) -> Bool {
        if rule.hasSuffix(".") { return bundleID.hasPrefix(rule) }
        return bundleID == rule || bundleID.hasPrefix(rule + ".")
    }

    /// The rule that matches and is the most specific, which is the longest. Nil when none matches.
    static func longest<Value>(
        in rules: [String: Value], where matches: (String) -> Bool
    ) -> (rule: String, value: Value)? {
        rules.filter { matches($0.key) }.max { $0.key.count < $1.key.count }.map { ($0.key, $0.value) }
    }

    /// `host` and its parent domains down to two labels: `app.slack.com` gives `app.slack.com` and `slack.com`.
    static func hostChain(_ host: String) -> [String] {
        let labels = normalized(host: host).split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return labels.isEmpty ? [] : [labels.joined(separator: ".")] }
        return (0...(labels.count - 2)).map { labels[$0...].joined(separator: ".") }
    }

    /// `bundleID` and the IDs above it, down to two parts: `com.apple.Mail.x` gives `com.apple.Mail.x`,
    /// `com.apple.Mail` and `com.apple`.
    static func bundleChain(_ bundleID: String) -> [String] {
        let parts = bundleID.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return bundleID.isEmpty ? [] : [bundleID] }
        return stride(from: parts.count, through: 2, by: -1).map { parts[..<$0].joined(separator: ".") }
    }
}
