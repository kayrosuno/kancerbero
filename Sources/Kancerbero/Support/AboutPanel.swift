import AppKit

/// Presents the standard About panel with two app-specific tweaks:
/// the build number is hidden (it is already the last component of the
/// version) and the credits show a clickable link to the website.
enum AboutPanel {
    static let website = URL(string: "https://kayros.uno")!

    static func present() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "—"

        let credits = NSMutableAttributedString(
            string: website.absoluteString,
            attributes: [
                .link: website,
                .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ])

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Kancerbero",
            .applicationVersion: version,
            // An empty build string removes the "(build)" suffix.
            .version: "",
            .credits: credits
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}
