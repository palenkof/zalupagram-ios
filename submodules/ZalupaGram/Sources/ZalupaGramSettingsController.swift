import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import ZalupaGramCore
import ZalupaGramSky

// ZalupaGram fork: the fork settings, opened from the top of Settings.

private final class ZalupaGramSettingsArguments {
    let setOption: (ZalupaGramCore.Option, Bool) -> Void
    let clearExceptions: () -> Void
    let openFrameDelay: () -> Void
    let checkForUpdates: () -> Void
    let openFeatures: () -> Void
    let exportSettings: () -> Void
    let importSettings: () -> Void
    let openDeleted: () -> Void
    let openTemplates: () -> Void
    let hiddenAction: () -> Void
    let changePin: () -> Void
    let applyTheme: (ZalupaGramThemeVariant) -> Void
    let openSkyCity: () -> Void
    let openSkyCaught: () -> Void
    let openVpn: () -> Void

    init(setOption: @escaping (ZalupaGramCore.Option, Bool) -> Void, clearExceptions: @escaping () -> Void, openFrameDelay: @escaping () -> Void, checkForUpdates: @escaping () -> Void, openFeatures: @escaping () -> Void, exportSettings: @escaping () -> Void, importSettings: @escaping () -> Void, openDeleted: @escaping () -> Void, openTemplates: @escaping () -> Void, hiddenAction: @escaping () -> Void, changePin: @escaping () -> Void, applyTheme: @escaping (ZalupaGramThemeVariant) -> Void, openSkyCity: @escaping () -> Void, openSkyCaught: @escaping () -> Void, openVpn: @escaping () -> Void) {
        self.setOption = setOption
        self.clearExceptions = clearExceptions
        self.openFrameDelay = openFrameDelay
        self.checkForUpdates = checkForUpdates
        self.openFeatures = openFeatures
        self.exportSettings = exportSettings
        self.importSettings = importSettings
        self.openDeleted = openDeleted
        self.openTemplates = openTemplates
        self.hiddenAction = hiddenAction
        self.changePin = changePin
        self.applyTheme = applyTheme
        self.openSkyCity = openSkyCity
        self.openSkyCaught = openSkyCaught
        self.openVpn = openVpn
    }
}

private enum ZalupaGramSettingsSection: Int32 {
    case vpn
    case ghost
    case chats
    case keep
    case hidden
    case appearance
    case animations
    case tabs
    case more
    case about
}

private enum ZalupaGramSettingsEntry: ItemListNodeEntry {
    case vpn(String, String)
    case ghostHeader(String)
    case ghostOption(Int32, ZalupaGramCore.Option, String, Bool)
    case ghostInfo(String)
    case ghostClearExceptions(String)
    case chatsHeader(String)
    case chatsOption(Int32, ZalupaGramCore.Option, String, Bool)
    case chatsTemplates(String, String)
    case chatsInfo(String)
    case keepHeader(String)
    case keepOption(Int32, ZalupaGramCore.Option, String, Bool)
    case keepList(String, String)
    case keepInfo(String)
    case hiddenHeader(String)
    case hiddenAction(String)
    case hiddenChangePin(String)
    case hiddenInfo(String)
    case appearanceHeader(String)
    case appearanceSky(String)
    case appearanceSkyDay(String)
    case appearanceSkyCycle(String)
    case appearanceSkyEvents(String, Bool)
    case appearanceSkyParallax(String, Bool)
    case appearanceSkyCity(String, String)
    case appearanceSkyCaught(String, String)
    case appearanceDark(String)
    case appearanceLight(String)
    case appearanceSystem(String)
    case appearanceOutline(String, Bool)
    case appearanceInfo(String)
    case animationsHeader(String)
    case animationsDelay(String, String)
    case animationsInfo(String)
    case tabsHeader(String)
    case karlanTab(String, Bool)
    case tabsInfo(String)
    case moreHeader(String)
    case features(String)
    case exportSettings(String)
    case importSettings(String)
    case checkForUpdates(String)
    case about(String)

    var section: ItemListSectionId {
        switch self {
        case .vpn:
            return ZalupaGramSettingsSection.vpn.rawValue
        case .ghostHeader, .ghostOption, .ghostInfo, .ghostClearExceptions:
            return ZalupaGramSettingsSection.ghost.rawValue
        case .chatsHeader, .chatsOption, .chatsTemplates, .chatsInfo:
            return ZalupaGramSettingsSection.chats.rawValue
        case .keepHeader, .keepOption, .keepList, .keepInfo:
            return ZalupaGramSettingsSection.keep.rawValue
        case .hiddenHeader, .hiddenAction, .hiddenChangePin, .hiddenInfo:
            return ZalupaGramSettingsSection.hidden.rawValue
        case .appearanceHeader, .appearanceSky, .appearanceSkyDay, .appearanceSkyCycle, .appearanceSkyEvents, .appearanceSkyParallax, .appearanceSkyCity, .appearanceSkyCaught, .appearanceDark, .appearanceLight, .appearanceSystem, .appearanceOutline, .appearanceInfo:
            return ZalupaGramSettingsSection.appearance.rawValue
        case .animationsHeader, .animationsDelay, .animationsInfo:
            return ZalupaGramSettingsSection.animations.rawValue
        case .tabsHeader, .karlanTab, .tabsInfo:
            return ZalupaGramSettingsSection.tabs.rawValue
        case .moreHeader, .features, .exportSettings, .importSettings:
            return ZalupaGramSettingsSection.more.rawValue
        case .checkForUpdates, .about:
            return ZalupaGramSettingsSection.about.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .vpn:
            return -1
        case .ghostHeader:
            return 0
        case let .ghostOption(index, _, _, _):
            return 1 + index
        case .ghostClearExceptions:
            return 10
        case .ghostInfo:
            return 11
        case .chatsHeader:
            return 20
        case let .chatsOption(index, _, _, _):
            return 21 + index
        case .chatsTemplates:
            return 38
        case .chatsInfo:
            return 39
        case .keepHeader:
            return 40
        case let .keepOption(index, _, _, _):
            return 41 + index
        case .keepList:
            return 46
        case .keepInfo:
            return 47
        case .hiddenHeader:
            return 50
        case .hiddenAction:
            return 51
        case .hiddenChangePin:
            return 52
        case .hiddenInfo:
            return 53
        case .appearanceHeader:
            return 54
        case .appearanceSky:
            return 55
        case .appearanceSkyDay:
            return 56
        case .appearanceSkyCycle:
            return 57
        case .appearanceDark:
            return 58
        case .appearanceLight:
            return 59
        case .appearanceSystem:
            return 60
        case .appearanceOutline:
            return 61
        case .appearanceSkyEvents:
            return 62
        case .appearanceSkyParallax:
            return 63
        case .appearanceSkyCity:
            return 64
        case .appearanceSkyCaught:
            return 65
        case .appearanceInfo:
            return 66
        case .animationsHeader:
            return 70
        case .animationsDelay:
            return 71
        case .animationsInfo:
            return 72
        case .tabsHeader:
            return 75
        case .karlanTab:
            return 76
        case .tabsInfo:
            return 77
        case .moreHeader:
            return 80
        case .features:
            return 81
        case .exportSettings:
            return 82
        case .importSettings:
            return 83
        case .checkForUpdates:
            return 90
        case .about:
            return 91
        }
    }

    static func ==(lhs: ZalupaGramSettingsEntry, rhs: ZalupaGramSettingsEntry) -> Bool {
        switch lhs {
        case let .vpn(text, value):
            if case .vpn(text, value) = rhs {
                return true
            }
            return false
        case let .ghostHeader(text):
            if case .ghostHeader(text) = rhs {
                return true
            }
            return false
        case let .ghostOption(index, option, text, value):
            if case .ghostOption(index, option, text, value) = rhs {
                return true
            }
            return false
        case let .ghostInfo(text):
            if case .ghostInfo(text) = rhs {
                return true
            }
            return false
        case let .ghostClearExceptions(text):
            if case .ghostClearExceptions(text) = rhs {
                return true
            }
            return false
        case let .chatsHeader(text):
            if case .chatsHeader(text) = rhs {
                return true
            }
            return false
        case let .chatsOption(index, option, text, value):
            if case .chatsOption(index, option, text, value) = rhs {
                return true
            }
            return false
        case let .chatsTemplates(text, value):
            if case .chatsTemplates(text, value) = rhs {
                return true
            }
            return false
        case let .chatsInfo(text):
            if case .chatsInfo(text) = rhs {
                return true
            }
            return false
        case let .keepHeader(text):
            if case .keepHeader(text) = rhs {
                return true
            }
            return false
        case let .keepOption(index, option, text, value):
            if case .keepOption(index, option, text, value) = rhs {
                return true
            }
            return false
        case let .keepList(text, value):
            if case .keepList(text, value) = rhs {
                return true
            }
            return false
        case let .keepInfo(text):
            if case .keepInfo(text) = rhs {
                return true
            }
            return false
        case let .hiddenHeader(text):
            if case .hiddenHeader(text) = rhs {
                return true
            }
            return false
        case let .hiddenAction(text):
            if case .hiddenAction(text) = rhs {
                return true
            }
            return false
        case let .hiddenChangePin(text):
            if case .hiddenChangePin(text) = rhs {
                return true
            }
            return false
        case let .hiddenInfo(text):
            if case .hiddenInfo(text) = rhs {
                return true
            }
            return false
        case let .appearanceHeader(text):
            if case .appearanceHeader(text) = rhs {
                return true
            }
            return false
        case let .appearanceSky(text):
            if case .appearanceSky(text) = rhs {
                return true
            }
            return false
        case let .appearanceSkyDay(text):
            if case .appearanceSkyDay(text) = rhs {
                return true
            }
            return false
        case let .appearanceSkyCycle(text):
            if case .appearanceSkyCycle(text) = rhs {
                return true
            }
            return false
        case let .appearanceSkyEvents(text, value):
            if case .appearanceSkyEvents(text, value) = rhs {
                return true
            }
            return false
        case let .appearanceSkyParallax(text, value):
            if case .appearanceSkyParallax(text, value) = rhs {
                return true
            }
            return false
        case let .appearanceSkyCity(text, value):
            if case .appearanceSkyCity(text, value) = rhs {
                return true
            }
            return false
        case let .appearanceSkyCaught(text, value):
            if case .appearanceSkyCaught(text, value) = rhs {
                return true
            }
            return false
        case let .appearanceDark(text):
            if case .appearanceDark(text) = rhs {
                return true
            }
            return false
        case let .appearanceLight(text):
            if case .appearanceLight(text) = rhs {
                return true
            }
            return false
        case let .appearanceSystem(text):
            if case .appearanceSystem(text) = rhs {
                return true
            }
            return false
        case let .appearanceOutline(text, value):
            if case .appearanceOutline(text, value) = rhs {
                return true
            }
            return false
        case let .appearanceInfo(text):
            if case .appearanceInfo(text) = rhs {
                return true
            }
            return false
        case let .animationsHeader(text):
            if case .animationsHeader(text) = rhs {
                return true
            }
            return false
        case let .tabsHeader(text):
            if case .tabsHeader(text) = rhs {
                return true
            }
            return false
        case let .karlanTab(text, value):
            if case .karlanTab(text, value) = rhs {
                return true
            }
            return false
        case let .tabsInfo(text):
            if case .tabsInfo(text) = rhs {
                return true
            }
            return false
        case let .animationsDelay(text, value):
            if case .animationsDelay(text, value) = rhs {
                return true
            }
            return false
        case let .animationsInfo(text):
            if case .animationsInfo(text) = rhs {
                return true
            }
            return false
        case let .moreHeader(text):
            if case .moreHeader(text) = rhs {
                return true
            }
            return false
        case let .features(text):
            if case .features(text) = rhs {
                return true
            }
            return false
        case let .exportSettings(text):
            if case .exportSettings(text) = rhs {
                return true
            }
            return false
        case let .importSettings(text):
            if case .importSettings(text) = rhs {
                return true
            }
            return false
        case let .checkForUpdates(text):
            if case .checkForUpdates(text) = rhs {
                return true
            }
            return false
        case let .about(text):
            if case .about(text) = rhs {
                return true
            }
            return false
        }
    }

    static func <(lhs: ZalupaGramSettingsEntry, rhs: ZalupaGramSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! ZalupaGramSettingsArguments
        switch self {
        case let .ghostHeader(text), let .chatsHeader(text), let .animationsHeader(text), let .moreHeader(text), let .keepHeader(text), let .hiddenHeader(text), let .appearanceHeader(text), let .tabsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .ghostOption(_, option, text, value), let .chatsOption(_, option, text, value), let .keepOption(_, option, text, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: text, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setOption(option, value)
            })
        case let .ghostInfo(text), let .animationsInfo(text), let .keepInfo(text), let .chatsInfo(text), let .hiddenInfo(text), let .appearanceInfo(text), let .tabsInfo(text), let .about(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .karlanTab(text, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: text, value: value, sectionId: self.section, style: .blocks, updated: { value in
                ZalupaGramKarlan.setEnabled(value)
            })
        case let .ghostClearExceptions(text):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.clearExceptions()
            })
        case let .features(text):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: text, label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openFeatures()
            })
        case let .exportSettings(text):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.exportSettings()
            })
        case let .importSettings(text):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.importSettings()
            })
        case let .checkForUpdates(text):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.checkForUpdates()
            })
        case let .vpn(text, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: text, label: value, sectionId: self.section, style: .blocks, action: {
                arguments.openVpn()
            })
        case let .hiddenAction(text):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.hiddenAction()
            })
        case let .hiddenChangePin(text):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.changePin()
            })
        case let .appearanceSky(text):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.applyTheme(.sky)
            })
        case let .appearanceSkyDay(text):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.applyTheme(.skyDay)
            })
        case let .appearanceSkyCycle(text):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.applyTheme(.skyCycle)
            })
        case let .appearanceSkyEvents(text, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: text, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setOption(.skyEvents, value)
            })
        case let .appearanceSkyParallax(text, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: text, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setOption(.skyParallax, value)
            })
        case let .appearanceSkyCity(text, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: text, label: value, sectionId: self.section, style: .blocks, action: {
                arguments.openSkyCity()
            })
        case let .appearanceSkyCaught(text, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: text, label: value, sectionId: self.section, style: .blocks, action: {
                arguments.openSkyCaught()
            })
        case let .appearanceDark(text):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.applyTheme(.dark)
            })
        case let .appearanceLight(text):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.applyTheme(.light)
            })
        case let .appearanceSystem(text):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.applyTheme(.system)
            })
        case let .appearanceOutline(text, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: text, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setOption(.bubbleOutline, value)
            })
        case let .chatsTemplates(text, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: text, label: value, sectionId: self.section, style: .blocks, action: {
                arguments.openTemplates()
            })
        case let .keepList(text, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: text, label: value, sectionId: self.section, style: .blocks, action: {
                arguments.openDeleted()
            })
        case let .animationsDelay(text, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: text, label: value, sectionId: self.section, style: .blocks, action: {
                arguments.openFrameDelay()
            })
        }
    }
}

private func zalupaGramSettingsEntries(presentationData: PresentationData, deletedCount: Int, hiddenCount: Int) -> [ZalupaGramSettingsEntry] {
    let ru = zalupaGramIsRussian(presentationData.strings)
    let t: (String, String) -> String = { english, russian in
        return ru ? russian : english
    }
    var entries: [ZalupaGramSettingsEntry] = []

    entries.append(.vpn("🛡 VPN", zalupaGramVpnStatusLabel(strings: presentationData.strings)))
    entries.append(.ghostHeader(t("GHOST MODE", "РЕЖИМ ПРИЗРАКА")))
    entries.append(.ghostOption(0, .ghostRead, t("No read receipts", "Не отправлять «прочитано»"), ZalupaGramCore.option(.ghostRead)))
    entries.append(.ghostOption(1, .ghostOnline, t("Always offline", "Всегда «не в сети»"), ZalupaGramCore.option(.ghostOnline)))
    entries.append(.ghostOption(2, .ghostTyping, t("Don't send «typing…»", "Не показывать «печатает»"), ZalupaGramCore.option(.ghostTyping)))
    let exceptions = ZalupaGramCore.ghostExceptions.count
    if exceptions > 0 {
        entries.append(.ghostClearExceptions(t("Clear chat exceptions (\(exceptions))", "Сбросить исключения чатов (\(exceptions))")))
    }
    entries.append(.ghostInfo(t(
        "Others don't see that you read their messages, are online or typing. Chats are read locally, in your app.",
        "Собеседники не увидят, что вы прочитали сообщения, были в сети или печатаете. Чаты читаются только у вас в приложении."
    )))

    entries.append(.chatsHeader(t("CHATS", "ЧАТЫ")))
    entries.append(.chatsOption(0, .timeWithSeconds, t("Time with seconds", "Время с секундами"), ZalupaGramCore.option(.timeWithSeconds)))
    entries.append(.chatsOption(1, .hideSponsored, t("No ads in channels", "Без рекламы в каналах"), ZalupaGramCore.option(.hideSponsored)))
    entries.append(.chatsOption(2, .stripTracking, t("Clean links", "Чистые ссылки"), ZalupaGramCore.option(.stripTracking)))
    entries.append(.chatsOption(3, .localTranscribe, t("Local voice to text", "Расшифровка голосовых"), ZalupaGramCore.option(.localTranscribe)))
    entries.append(.chatsOption(4, .freeTranslation, t("Free translation", "Бесплатный перевод"), ZalupaGramCore.option(.freeTranslation)))
    entries.append(.chatsOption(5, .noLinkPreviews, t("Links without a preview", "Ссылки без превью"), ZalupaGramCore.option(.noLinkPreviews)))
    entries.append(.chatsOption(6, .localPins, t("More than 5 pinned chats", "Больше 5 закреплённых"), ZalupaGramCore.option(.localPins)))
    let templates = ZalupaGramTemplates.all.count
    entries.append(.chatsTemplates(t("Reply templates", "Шаблоны ответов"), templates > 0 ? "\(templates)" : ""))
    entries.append(.chatsInfo(t(
        "Clean links: utm_*, fbclid and other tracking is cut when sending. Voice to text and translation work without Premium: on the phone and through Google.",
        "Чистые ссылки: при отправке вырезаются utm_*, fbclid и другие метки. Расшифровка и перевод работают без Premium: на телефоне и через Google."
    )))

    entries.append(.keepHeader(t("ANTI-DELETE", "АНТИУДАЛЕНИЕ")))
    entries.append(.keepOption(0, .keepDeleted, t("Keep deleted", "Сохранять удалённые"), ZalupaGramCore.option(.keepDeleted)))
    entries.append(.keepOption(1, .keepEdits, t("Edit history", "История правок"), ZalupaGramCore.option(.keepEdits)))
    entries.append(.keepOption(2, .profileHistory, t("Profile history", "История профилей"), ZalupaGramCore.option(.profileHistory)))
    entries.append(.keepList(t("Deleted messages", "Удалённые сообщения"), deletedCount > 0 ? "\(deletedCount)" : ""))
    entries.append(.keepInfo(t(
        "Messages deleted by others stay in the chat with the «deleted» mark. Previous versions of edited messages: message menu → «Edit history». Name, username and photo changes of contacts: in their profile. Only what the app has seen is kept.",
        "Сообщения, удалённые собеседниками, остаются в чате с пометкой «удалено». Старые версии изменённых сообщений: меню сообщения → «История правок». Смены имени, юзернейма и аватарки контактов: в их профиле. Сохраняется только то, что приложение успело увидеть."
    )))

    entries.append(.hiddenHeader(t("HIDDEN CHATS", "СКРЫТЫЕ ЧАТЫ")))
    if !ZalupaGramHiddenChats.hasPin {
        entries.append(.hiddenAction(t("Set a PIN", "Задать PIN")))
    } else if ZalupaGramHiddenChats.unlocked {
        entries.append(.hiddenAction(t("Hide them again", "Спрятать скрытые чаты")))
    } else {
        entries.append(.hiddenAction(t("Show hidden chats", "Показать скрытые чаты") + (hiddenCount > 0 ? " (\(hiddenCount))" : "")))
    }
    if ZalupaGramHiddenChats.hasPin {
        entries.append(.hiddenChangePin(t("Change the PIN", "Сменить PIN")))
    }
    entries.append(.hiddenInfo(t(
        "Hold a chat in the list → «Hide the chat». After the PIN they show up until the app goes to the background. Panic: the link zalupagram://panic hides them and turns the passcode lock on, put it on Back Tap: Shortcuts → new shortcut «Open URLs», then iPhone Settings → Accessibility → Touch → Back Tap.",
        "Зажмите чат в списке → «Скрыть чат». После PIN они видны, пока приложение не уйдёт в фон. Паника: ссылка zalupagram://panic прячет их и включает код-пароль. Повесьте её на двойной стук по задней панели: «Быстрые команды» → новая команда «Открыть URL», затем Настройки iPhone → Универсальный доступ → Касание → Касание задней панели."
    )))

    entries.append(.appearanceHeader(t("APPEARANCE", "ОФОРМЛЕНИЕ")))
    entries.append(.appearanceSky(t("ZalupaGram theme, night sky", "Тема ZalupaGram, ночное небо")))
    entries.append(.appearanceSkyDay(t("ZalupaGram theme, day sky", "Тема ZalupaGram, дневное небо")))
    entries.append(.appearanceSkyCycle(t("ZalupaGram theme, day and night by the clock", "Тема ZalupaGram, сутки по часам")))
    entries.append(.appearanceDark(t("ZalupaGram theme, dark", "Тема ZalupaGram, тёмная")))
    entries.append(.appearanceLight(t("ZalupaGram theme, light", "Тема ZalupaGram, светлая")))
    entries.append(.appearanceSystem(t("ZalupaGram theme, like iOS", "Тема ZalupaGram, как в системе")))
    entries.append(.appearanceOutline(t("Message outlines in «Night sky»", "Обводка сообщений в «Ночном небе»"), ZalupaGramCore.option(.bubbleOutline)))
    entries.append(.appearanceSkyEvents(t("Events in the sky", "События в небе"), ZalupaGramCore.option(.skyEvents)))
    entries.append(.appearanceSkyParallax(t("The sky follows the tilt", "Небо следует за наклоном"), ZalupaGramCore.option(.skyParallax)))
    entries.append(.appearanceSkyCity(t("Weather in a city", "Погода по городу"), ZalupaGramSky.city))
    entries.append(.appearanceSkyCaught(t("Caught in the sky", "Поймано в небе"), "\(ZalupaGramSky.caught.values.reduce(0, +))"))
    entries.append(.appearanceInfo(t("The sky comes alive: stars, planes, whales, UFOs, by the time of day and the season. Tap a rare event in a chat to catch it. A city goes to open-meteo.com, once in half an hour. «Like iOS» is light by day and dark by night; the others turn the automatic night theme off. The usual themes are in Settings → Appearance.", "Небо живое: звёзды, самолёты, киты, НЛО, по времени суток и сезону. Нажмите на редкое событие в чате, чтобы поймать его. Город уходит на open-meteo.com раз в полчаса. «Как в системе» — светлая днём и тёмная ночью, остальные выключают автоночь. Обычные темы — в Настройки → Оформление.")))

    entries.append(.animationsHeader(t("ANIMATED PHRASES", "АНИМИРОВАННЫЕ ФРАЗЫ")))
    entries.append(.animationsDelay(t("Time per frame", "Время на кадр"), formatSeconds(zalupaGramAnimationFrameDelay, ru: ru)))
    entries.append(.animationsInfo(t(
        "Type a phrase, hold the send button and choose «Animate the phrase».",
        "Напишите фразу, зажмите кнопку отправки и выберите «Анимировать фразу»."
    )))

    entries.append(.tabsHeader(t("TABS", "ВКЛАДКИ")))
    entries.append(.karlanTab(t("«Karlan» tab", "Вкладка «Карлан»"), ZalupaGramKarlan.isEnabled))
    entries.append(.tabsInfo(t(
        "zapostit.com/shevtsov right in the app, next to the chats. Tap the tab again to scroll up or go back to the start page.",
        "zapostit.com/shevtsov прямо в приложении, рядом с чатами. Повторное нажатие на вкладку листает наверх и возвращает на главную."
    )))

    entries.append(.moreHeader(t("MORE", "ЕЩЁ")))
    entries.append(.features(t("ZalupaGram features", "Возможности ZalupaGram")))
    entries.append(.exportSettings(t("Save settings to a file", "Сохранить настройки в файл")))
    entries.append(.importSettings(t("Restore from a file", "Восстановить из файла")))

    entries.append(.checkForUpdates(t("Check for updates", "Проверить обновления")))
    let telegramVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    entries.append(.about("\(ZalupaGram.title) \(ZalupaGram.version)\n" + t("Based on Telegram ", "На основе Telegram ") + telegramVersion))
    return entries
}

public func zalupaGramSettingsController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?
    let updated = ValuePromise<Int>(0, ignoreRepeated: false)
    var counter = 0
    let reload: () -> Void = {
        counter += 1
        updated.set(counter)
    }

    let arguments = ZalupaGramSettingsArguments(setOption: { option, value in
        ZalupaGramCore.setOption(option, value)
        if option == .bubbleOutline {
            zalupaGramRefreshSkyOutline(context: context)
        }
        reload()
    }, clearExceptions: {
        ZalupaGramCore.clearGhostExceptions()
        reload()
    }, openFrameDelay: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentFrameDelayPicker(presentationData: presentationData, present: { controller in
            presentControllerImpl?(controller)
        }, done: {
            reload()
        })
    }, checkForUpdates: {
        zalupaGramCheckForUpdates(context: context, manual: true)
    }, openFeatures: {
        pushControllerImpl?(zalupaGramFeaturesController(context: context))
    }, exportSettings: {
        zalupaGramExportSettings(context: context)
    }, importSettings: {
        zalupaGramImportSettings(context: context, completion: { count in
            reload()
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let ru = zalupaGramIsRussian(presentationData.strings)
            let text: String
            if let count {
                text = ru ? "Восстановлено настроек: \(count)." : "Restored options: \(count)."
            } else {
                text = ru ? "Это не файл настроек ZalupaGram." : "This is not a ZalupaGram settings file."
            }
            presentControllerImpl?(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]))
        })
    }, openDeleted: {
        pushControllerImpl?(zalupaGramDeletedMessagesController(context: context))
    }, openTemplates: {
        pushControllerImpl?(zalupaGramTemplatesController(context: context))
    }, hiddenAction: {
        let present: (ViewController) -> Void = { controller in
            presentControllerImpl?(controller)
        }
        if !ZalupaGramHiddenChats.hasPin {
            zalupaGramSetupHiddenPin(context: context, present: present, done: {
                reload()
            })
        } else if ZalupaGramHiddenChats.unlocked {
            ZalupaGramHiddenChats.setUnlocked(false)
            reload()
        } else {
            zalupaGramUnlockHiddenChats(context: context, present: present, done: {
                reload()
            })
        }
    }, changePin: {
        let present: (ViewController) -> Void = { controller in
            presentControllerImpl?(controller)
        }
        zalupaGramUnlockHiddenChats(context: context, present: present, done: {
            zalupaGramSetupHiddenPin(context: context, present: present, done: {
                reload()
            })
        })
    }, applyTheme: { variant in
        zalupaGramApplyTheme(context: context, variant: variant)
    }, openSkyCity: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let ru = zalupaGramIsRussian(presentationData.strings)
        presentControllerImpl?(promptController(context: context, text: ru ? "Погода по городу" : "Weather in a city", titleFont: .bold, subtitle: ru ? "Город уходит на open-meteo.com. Пусто — случайная погода по сезону." : "The city goes to open-meteo.com. Empty means random weather by the season.", value: ZalupaGramSky.city, placeholder: ru ? "Город" : "City", characterLimit: 64, apply: { value in
            if let value {
                ZalupaGramSky.city = value
                reload()
            }
        }))
    }, openSkyCaught: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let ru = zalupaGramIsRussian(presentationData.strings)
        let caught = ZalupaGramSky.caught.sorted(by: { $0.key < $1.key }).map({ "\($0.key) × \($0.value)" }).joined(separator: "\n")
        let empty = ru ? "Пока ничего. Редкие события появляются раз в несколько дней: нажмите на такое в чате." : "Nothing yet. Rare events show up once in a few days: tap one in a chat."
        presentControllerImpl?(textAlertController(context: context, title: ru ? "Поймано в небе" : "Caught in the sky", text: caught.isEmpty ? empty : caught, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]))
    }, openVpn: {
        pushControllerImpl?(zalupaGramVpnController(context: context))
    })

    let signal = combineLatest(context.sharedContext.presentationData, updated.get(), ZalupaGramVpn.shared.changes, ZalupaGramKarlan.enabledValue)
    |> deliverOnMainQueue
    |> map { presentationData, _, _, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("ZalupaGram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: zalupaGramSettingsEntries(presentationData: presentationData, deletedCount: zalupaGramDeletedMessagesCount(context: context), hiddenCount: ZalupaGramHiddenChats.hiddenPeerIds(accountPeerId: context.account.peerId.toInt64()).count), style: .blocks, emptyStateItem: nil, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    return controller
}
