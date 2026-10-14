import Domain

/// The categories the app ships for known apps and sites. It is data: the resolution logic is in `StyleResolver`.
/// A bundle rule matches the bundle ID itself and the IDs under it (`com.apple.Terminal` and `com.apple.Terminal.x`);
/// a host rule matches the host and its subdomains.
public struct SeedTable: Sendable, Equatable {
    public let bundles: [String: AppCategory]
    public let hosts: [String: AppCategory]

    public init(bundles: [String: AppCategory], hosts: [String: AppCategory]) {
        self.bundles = bundles
        self.hosts = hosts
    }

    public static let standard = SeedTable(
        bundles: [
            // Email
            "com.apple.mail": .email,
            "com.microsoft.Outlook": .email,
            "com.readdle.smartemail-Mac": .email,
            // Work chat
            "com.tinyspeck.slackmacgap": .workChat,
            "com.microsoft.teams2": .workChat,
            "us.zoom.xos": .workChat,
            // Personal messaging
            "com.apple.MobileSMS": .personalMessaging,
            "net.whatsapp.WhatsApp": .personalMessaging,
            "ru.keepcoder.Telegram": .personalMessaging,
            // Documents
            "com.apple.Notes": .document,
            "com.apple.TextEdit": .document,
            "com.apple.iWork.Pages": .document,
            "com.microsoft.Word": .document,
            "md.obsidian": .document,
            "notion.id": .document,
            // Terminals
            "com.apple.Terminal": .terminal,
            "com.googlecode.iterm2": .terminal,
            "com.mitchellh.ghostty": .terminal,
            "net.kovidgoyal.kitty": .terminal,
            "dev.warp.Warp-Stable": .terminal,
            // AI chat
            "com.openai.chat": .aiChat,
            "com.anthropic.claudefordesktop": .aiChat,
        ],
        hosts: [
            "mail.google.com": .email,
            "outlook.office.com": .email,
            "outlook.live.com": .email,
            "slack.com": .workChat,
            "teams.microsoft.com": .workChat,
            "web.whatsapp.com": .personalMessaging,
            "web.telegram.org": .personalMessaging,
            "docs.google.com": .document,
            "notion.so": .document,
            "chatgpt.com": .aiChat,
            "claude.ai": .aiChat,
            "gemini.google.com": .aiChat,
        ]
    )
}
