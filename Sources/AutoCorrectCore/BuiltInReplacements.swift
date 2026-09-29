import Foundation

/// Small, inspectable opt-in writing conveniences. Ignored words and user corrections
/// should be resolved first. Only an exact lowercase trigger is expanded or recased.
public enum BuiltInReplacements {
    public static let expansions: [String: String] = [
        "idk": "I don't know", "omw": "On my way", "brb": "Be right back",
        "imo": "in my opinion", "fyi": "for your information"
    ]

    public static let casing: [String: String] = [
        "iphone": "iPhone", "ipad": "iPad", "macbook": "MacBook", "airpods": "AirPods",
        "github": "GitHub", "chatgpt": "ChatGPT", "linkedin": "LinkedIn", "youtube": "YouTube",
        "powerpoint": "PowerPoint", "photoshop": "Photoshop", "onenote": "OneNote", "onedrive": "OneDrive",
        "sharepoint": "SharePoint", "libreoffice": "LibreOffice", "openoffice": "OpenOffice",
        "javascript": "JavaScript", "typescript": "TypeScript", "wordpress": "WordPress", "woocommerce": "WooCommerce",
        "salesforce": "Salesforce", "quickbooks": "QuickBooks", "autocad": "AutoCAD", "solidworks": "SolidWorks",
        "davinci": "DaVinci", "tiktok": "TikTok", "whatsapp": "WhatsApp", "snapchat": "Snapchat",
        "instagram": "Instagram", "facebook": "Facebook", "reddit": "Reddit", "spotify": "Spotify",
        "netflix": "Netflix", "gmail": "Gmail", "icloud": "iCloud", "imessage": "iMessage", "facetime": "FaceTime",
        "ipados": "iPadOS", "watchos": "watchOS", "airdrop": "AirDrop", "airplay": "AirPlay", "airtag": "AirTag",
        "testflight": "TestFlight", "xcode": "Xcode",
        "pdf": "PDF", "png": "PNG", "jpeg": "JPEG", "jpg": "JPG", "gif": "GIF", "svg": "SVG",
        "csv": "CSV", "json": "JSON", "html": "HTML", "css": "CSS", "xml": "XML", "sql": "SQL",
        "http": "HTTP", "https": "HTTPS", "url": "URL", "usb": "USB",
        "ui": "UI", "ux": "UX", "api": "API", "macos": "macOS"
    ]

    /// English abbreviations are language-gated. Product/acronym casing is language-neutral.
    /// ALLCAPS, Initialcase, and mixed-case input are preserved as deliberate user choices.
    public static func replacement(for original: String, language: String,
                                   includeExpansions: Bool, includeCasing: Bool) -> String? {
        guard original == original.lowercased() else { return nil }
        if includeCasing, let replacement = casing[original] { return replacement }
        let isEnglish = language.replacingOccurrences(of: "-", with: "_").split(separator: "_").first?.lowercased() == "en"
        if includeExpansions, isEnglish { return expansions[original] }
        return nil
    }
}
