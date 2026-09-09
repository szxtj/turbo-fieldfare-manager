import Foundation
import SwiftUI
import Combine

public enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case en = "en"
    case zh = "zh"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system:
            return LocalizationManager.shared.isEnglish ? "System Default" : "跟随系统"
        case .en:
            return "English"
        case .zh:
            return "简体中文"
        }
    }
}

public final class LocalizationManager: ObservableObject {
    public static let shared = LocalizationManager()

    private let storageKey = "TurboFieldfare_AppLanguage"

    @Published public var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: storageKey)
        }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: storageKey),
           let lang = AppLanguage(rawValue: saved) {
            self.language = lang
        } else {
            self.language = .system
        }
    }

    public var isEnglish: Bool {
        switch language {
        case .en:
            return true
        case .zh:
            return false
        case .system:
            if let pref = Locale.preferredLanguages.first {
                return !pref.lowercased().hasPrefix("zh")
            }
            return true
        }
    }

    public func tr(_ en: String, _ zh: String) -> String {
        return isEnglish ? en : zh
    }
}
