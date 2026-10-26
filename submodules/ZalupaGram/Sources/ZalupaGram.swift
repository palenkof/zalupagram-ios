import Foundation
import UIKit
import Display
import TelegramPresentationData

// ZalupaGram fork: shared constants and settings icons.
public enum ZalupaGram {
    public static let version: String = zalupaGramVersion
    public static let title: String = "ZalupaGram by palenkof"

    public static let settingsIcon: UIImage? = renderSettingsIcon(name: "ZalupaGram/SettingsIcon")
    public static let logsIcon: UIImage? = renderSettingsIcon(name: "Item List/Icons/File", backgroundColors: [UIColor(rgb: 0x8E8E93)])

    // Fork strings are not in the cloud language packs,
    // so pick between English and Russian by the current language.
    public static func tr(_ strings: PresentationStrings, _ english: String, _ russian: String) -> String {
        if strings.baseLanguageCode == "ru" || strings.primaryComponent.languageCode == "ru" {
            return russian
        }
        return english
    }
}
