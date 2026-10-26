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

// ZalupaGram fork: the fork settings, opened from the top of Settings.

private final class ZalupaGramSettingsArguments {
    let setOption: (ZalupaGramCore.Option, Bool) -> Void
    let clearExceptions: () -> Void
    let openFrameDelay: () -> Void

    init(setOption: @escaping (ZalupaGramCore.Option, Bool) -> Void, clearExceptions: @escaping () -> Void, openFrameDelay: @escaping () -> Void) {
        self.setOption = setOption
        self.clearExceptions = clearExceptions
        self.openFrameDelay = openFrameDelay
    }
}

private enum ZalupaGramSettingsSection: Int32 {
    case ghost
    case chats
    case animations
    case about
}

private enum ZalupaGramSettingsEntry: ItemListNodeEntry {
    case ghostHeader(String)
    case ghostOption(Int32, ZalupaGramCore.Option, String, Bool)
    case ghostInfo(String)
    case ghostClearExceptions(String)
    case chatsHeader(String)
    case chatsOption(Int32, ZalupaGramCore.Option, String, Bool)
    case animationsHeader(String)
    case animationsDelay(String, String)
    case animationsInfo(String)
    case about(String)

    var section: ItemListSectionId {
        switch self {
        case .ghostHeader, .ghostOption, .ghostInfo, .ghostClearExceptions:
            return ZalupaGramSettingsSection.ghost.rawValue
        case .chatsHeader, .chatsOption:
            return ZalupaGramSettingsSection.chats.rawValue
        case .animationsHeader, .animationsDelay, .animationsInfo:
            return ZalupaGramSettingsSection.animations.rawValue
        case .about:
            return ZalupaGramSettingsSection.about.rawValue
        }
    }

    var stableId: Int32 {
        switch self {
        case .ghostHeader:
            return 0
        case let .ghostOption(index, _, _, _):
            return 1 + index
        case .ghostClearExceptions:
            return 10
        case .ghostInfo:
            return 11
        case .chatsHeader:
            return 15
        case let .chatsOption(index, _, _, _):
            return 16 + index
        case .animationsHeader:
            return 20
        case .animationsDelay:
            return 21
        case .animationsInfo:
            return 22
        case .about:
            return 30
        }
    }

    static func ==(lhs: ZalupaGramSettingsEntry, rhs: ZalupaGramSettingsEntry) -> Bool {
        switch lhs {
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
        case let .animationsHeader(text):
            if case .animationsHeader(text) = rhs {
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
        case let .ghostHeader(text), let .chatsHeader(text), let .animationsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .ghostOption(_, option, text, value), let .chatsOption(_, option, text, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: text, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setOption(option, value)
            })
        case let .ghostInfo(text), let .animationsInfo(text), let .about(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .ghostClearExceptions(text):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.clearExceptions()
            })
        case let .animationsDelay(text, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: text, label: value, sectionId: self.section, style: .blocks, action: {
                arguments.openFrameDelay()
            })
        }
    }
}

private func zalupaGramSettingsEntries(presentationData: PresentationData) -> [ZalupaGramSettingsEntry] {
    let ru = zalupaGramIsRussian(presentationData.strings)
    let t: (String, String) -> String = { english, russian in
        return ru ? russian : english
    }
    var entries: [ZalupaGramSettingsEntry] = []

    entries.append(.ghostHeader(t("GHOST MODE", "РЕЖИМ ПРИЗРАКА")))
    entries.append(.ghostOption(0, .ghostRead, t("Don't send read receipts", "Не отправлять «прочитано»"), ZalupaGramCore.option(.ghostRead)))
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

    entries.append(.animationsHeader(t("ANIMATED PHRASES", "АНИМИРОВАННЫЕ ФРАЗЫ")))
    entries.append(.animationsDelay(t("Time per frame", "Время на кадр"), formatSeconds(zalupaGramAnimationFrameDelay, ru: ru)))
    entries.append(.animationsInfo(t(
        "Type a phrase, hold the send button and choose «Animate the phrase».",
        "Напишите фразу, зажмите кнопку отправки и выберите «Анимировать фразу»."
    )))

    let telegramVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    entries.append(.about("\(ZalupaGram.title) \(ZalupaGram.version)\n" + t("Based on Telegram ", "На основе Telegram ") + telegramVersion))
    return entries
}

public func zalupaGramSettingsController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController) -> Void)?
    let updated = ValuePromise<Int>(0, ignoreRepeated: false)
    var counter = 0
    let reload: () -> Void = {
        counter += 1
        updated.set(counter)
    }

    let arguments = ZalupaGramSettingsArguments(setOption: { option, value in
        ZalupaGramCore.setOption(option, value)
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
    })

    let signal = combineLatest(context.sharedContext.presentationData, updated.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("ZalupaGram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: zalupaGramSettingsEntries(presentationData: presentationData), style: .blocks, emptyStateItem: nil, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
