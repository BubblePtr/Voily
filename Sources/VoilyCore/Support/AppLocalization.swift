import Foundation

public enum AppLocalization: Sendable {
    private static let storage = AppLocalizationStorage()

    public static var currentLanguageCode: String {
        storage.currentLanguageCode
    }

    public static func setLanguageCode(_ code: String) {
        let normalized = AppInterfaceLanguage(rawValue: code)?.rawValue ?? AppInterfaceLanguage.defaultLanguage.rawValue
        storage.setLanguageCode(normalized)
    }

    public static func localized(_ key: String) -> String {
        localized(key, languageCode: currentLanguageCode)
    }

    public static func localized(_ key: String, languageCode: String) -> String {
        if let bundle = bundle(for: languageCode) {
            let localized = bundle.localizedString(forKey: key, value: key, table: nil)
            if localized != key {
                return localized
            }
        }

        return fallbackStringsByLanguage[languageCode]?[key] ?? key
    }

    private static func bundle(for languageCode: String) -> Bundle? {
        guard let url = ResourceBundle.current.url(forResource: languageCode, withExtension: "lproj") else {
            return nil
        }
        return Bundle(url: url)
    }

    private static let fallbackStringsByLanguage: [String: [String: String]] = [
        AppInterfaceLanguage.simplifiedChinese.rawValue: [
            "glossary.customTerms": "自定义词条",
            "glossary.domain.internet": "互联网",
            "glossary.domain.medical": "医疗",
            "glossary.domain.legal": "法律",
            "glossary.scene.development": "开发",
            "glossary.scene.testing": "测试",
            "glossary.scene.productManagement": "产品经理",
            "glossary.unknown": "未知",
            "%@-%@": "%@-%@",
        ],
    ]
}

private final class AppLocalizationStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var languageCode = AppInterfaceLanguage.defaultLanguage.rawValue

    var currentLanguageCode: String {
        lock.lock()
        defer { lock.unlock() }
        return languageCode
    }

    func setLanguageCode(_ code: String) {
        lock.lock()
        languageCode = code
        lock.unlock()
    }
}

public enum ResourceBundle: Sendable {
    public static var current: Bundle {
        Bundle.main
    }
}
