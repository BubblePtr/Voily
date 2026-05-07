import Foundation

enum AppLocalization {
    private static let storage = AppLocalizationStorage()

    static var currentLanguageCode: String {
        storage.currentLanguageCode
    }

    static func setLanguageCode(_ code: String) {
        let normalized = AppInterfaceLanguage(rawValue: code)?.rawValue ?? AppInterfaceLanguage.defaultLanguage.rawValue
        storage.setLanguageCode(normalized)
    }

    static func localized(_ key: String) -> String {
        localized(key, languageCode: currentLanguageCode)
    }

    static func localized(_ key: String, languageCode: String) -> String {
        guard let bundle = bundle(for: languageCode) else {
            return key
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    private static func bundle(for languageCode: String) -> Bundle? {
        guard let url = ResourceBundle.current.url(forResource: languageCode, withExtension: "lproj") else {
            return nil
        }
        return Bundle(url: url)
    }
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

enum ResourceBundle {
    static var current: Bundle {
        Bundle.main
    }
}
