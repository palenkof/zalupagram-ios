import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import TextFormat
import PresentationDataUtils
import AccountContext

// ZalupaGram fork: «ZalupaGram features», a list generated from code,
// newest versions first, the same idea as in ZalupaGram Desktop.

private struct Feature {
    let version: String
    let icon: String
    let title: (String, String)
    let text: (String, String)
}

private let features: [Feature] = [
    Feature(version: "0.4.0", icon: "📝", title: ("Notes on messages", "Заметки к сообщениям"), text: ("Message menu → «Add a note», only you see it, marked with 📝.", "Меню сообщения → «Добавить заметку», видна только вам, отмечена 📝.")),
    Feature(version: "0.4.0", icon: "📋", title: ("Reply templates", "Шаблоны ответов"), text: ("Message menu → «Reply with a template», saved from the send button menu.", "Меню сообщения → «Ответить шаблоном», сохраняются из меню кнопки отправки.")),
    Feature(version: "0.4.0", icon: "🌐", title: ("Translate before sending", "Перевод перед отправкой"), text: ("Hold the send button → «Translate the text».", "Зажмите кнопку отправки → «Перевести текст».")),
    Feature(version: "0.4.0", icon: "🪪", title: ("Profile history", "История профилей"), text: ("Name, username and photo changes of contacts, in their profile.", "Смены имени, юзернейма и аватарки контактов, в их профиле.")),
    Feature(version: "0.4.0", icon: "🎭", title: ("Stickers as PNG and GIF", "Стикеры в PNG и GIF"), text: ("Sticker menu → «Save as PNG» or «Save as GIF».", "Меню стикера → «Сохранить как PNG» или «Сохранить как GIF».")),
    Feature(version: "0.4.0", icon: "🧹", title: ("Delete my messages", "Удалить мои сообщения"), text: ("All of yours in a group at once: hold the group in the chat list.", "Все свои в группе разом: зажмите группу в списке чатов.")),
    Feature(version: "0.3.0", icon: "🗑", title: ("Anti-delete", "Антиудаление"), text: ("Messages deleted by others stay in the chat with the «deleted» mark.", "Сообщения, удалённые собеседниками, остаются в чате с пометкой «удалено».")),
    Feature(version: "0.3.0", icon: "📜", title: ("Edit history", "История правок"), text: ("Previous versions of edited messages: message menu.", "Старые версии изменённых сообщений: меню сообщения.")),
    Feature(version: "0.3.0", icon: "🗂", title: ("Deleted messages", "Удалённые сообщения"), text: ("All of them in one list: ZalupaGram settings → Anti-delete.", "Все в одном списке: настройки ZalupaGram → Антиудаление.")),
    Feature(version: "0.2.0", icon: "🔎", title: ("Message details", "Подробности сообщения"), text: ("Exact send and edit time, IDs, where it was forwarded from: message menu.", "Точное время отправки и правки, ID, откуда переслано: меню сообщения.")),
    Feature(version: "0.2.0", icon: "🎙", title: ("Voice to text on the phone", "Расшифровка на телефоне"), text: ("Voice and round video messages, without Premium.", "Голосовые и кружки, без Premium.")),
    Feature(version: "0.2.0", icon: "🌐", title: ("Free translation", "Бесплатный перевод"), text: ("Messages and whole chats through Google, without Premium.", "Сообщения и целые чаты через Google, без Premium.")),
    Feature(version: "0.2.0", icon: "👥", title: ("Up to 10 accounts", "До 10 аккаунтов"), text: ("Without Premium, instead of 3.", "Без Premium, вместо трёх.")),
    Feature(version: "0.2.0", icon: "📥", title: ("Save stories", "Сохранение историй"), text: ("Without Premium, if the author allows it.", "Без Premium, если автор это разрешает.")),
    Feature(version: "0.2.0", icon: "🔗", title: ("No link previews", "Без превью ссылок"), text: ("Links are sent without a preview, can be turned off.", "Ссылки отправляются без превью, можно выключить.")),
    Feature(version: "0.2.0", icon: "💾", title: ("Settings backup", "Резервная копия настроек"), text: ("Save ZalupaGram options to a file and restore them.", "Сохранение настроек ZalupaGram в файл и восстановление.")),
    Feature(version: "0.1.0", icon: "🎬", title: ("Animated phrases", "Анимированные фразы"), text: ("Hold the send button → «Animate the phrase».", "Зажмите кнопку отправки → «Анимировать фразу».")),
    Feature(version: "0.1.0", icon: "👻", title: ("Ghost mode", "Режим призрака"), text: ("No read receipts, always offline, no «typing», chat exceptions.", "Без «прочитано», всегда не в сети, без «печатает», исключения чатов.")),
    Feature(version: "0.1.0", icon: "🕐", title: ("Time with seconds", "Время с секундами"), text: ("Every message shows the exact time: 14:05:37.", "У каждого сообщения точное время: 14:05:37.")),
    Feature(version: "0.1.0", icon: "🚫", title: ("No ads in channels", "Без рекламы в каналах"), text: ("Optional, turned off by default.", "По желанию, по умолчанию выключено.")),
    Feature(version: "0.1.0", icon: "🧹", title: ("Clean links", "Чистые ссылки"), text: ("utm_source, fbclid and other tracking is cut when sending.", "При отправке вырезаются utm_source, fbclid и другие метки.")),
    Feature(version: "0.1.0", icon: "🔎", title: ("ID and registration date", "ID и дата регистрации"), text: ("Shown in profiles of users, groups and channels.", "Видны в профилях людей, групп и каналов.")),
    Feature(version: "0.1.0", icon: "⏩", title: ("Speed up to 4x", "Скорость до 4x"), text: ("For voice messages, music and videos.", "Для голосовых, музыки и видео.")),
    Feature(version: "0.1.0", icon: "📋", title: ("Logs", "Логи"), text: ("«Send Logs» at the bottom of Settings.", "«Отправить логи» внизу настроек.")),
    Feature(version: "0.1.0", icon: "🔄", title: ("Updates", "Обновления"), text: ("Finds new versions in the releases repo.", "Находит новые версии в репозитории сборок.")),
]

private enum FeaturesEntry: ItemListNodeEntry {
    case header(Int32, String)
    case feature(Int32, Int32, String, String)

    var section: ItemListSectionId {
        switch self {
        case let .header(section, _), let .feature(section, _, _, _):
            return section
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(section, _):
            return section * 1000
        case let .feature(section, index, _, _):
            return section * 1000 + 1 + index
        }
    }

    static func ==(lhs: FeaturesEntry, rhs: FeaturesEntry) -> Bool {
        switch lhs {
        case let .header(section, text):
            if case .header(section, text) = rhs {
                return true
            }
            return false
        case let .feature(section, index, title, text):
            if case .feature(section, index, title, text) = rhs {
                return true
            }
            return false
        }
    }

    static func <(lhs: FeaturesEntry, rhs: FeaturesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .feature(_, _, title, text):
            return ItemListTextWithLabelItem(presentationData: presentationData, label: title, text: text, style: .blocks, enabledEntityTypes: [], multiline: true, sectionId: self.section, action: nil)
        }
    }
}

private func featuresEntries(presentationData: PresentationData) -> [FeaturesEntry] {
    let ru = zalupaGramIsRussian(presentationData.strings)
    var entries: [FeaturesEntry] = []
    var versions: [String] = []
    for feature in features where !versions.contains(feature.version) {
        versions.append(feature.version)
    }
    for (sectionIndex, version) in versions.enumerated() {
        let section = Int32(sectionIndex)
        let title = version == ZalupaGram.version ? (ru ? "НОВОЕ В " : "NEW IN ") + version : (ru ? "ВЕРСИЯ " : "VERSION ") + version
        entries.append(.header(section, title))
        var index: Int32 = 0
        for feature in features where feature.version == version {
            entries.append(.feature(section, index, feature.icon + "  " + (ru ? feature.title.1 : feature.title.0), ru ? feature.text.1 : feature.text.0))
            index += 1
        }
    }
    return entries
}

public func zalupaGramFeaturesController(context: AccountContext) -> ViewController {
    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let title = zalupaGramIsRussian(presentationData.strings) ? "Возможности" : "Features"
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: featuresEntries(presentationData: presentationData), style: .blocks, emptyStateItem: nil, animateChanges: false)
        return (controllerState, (listState, Void()))
    }
    return ItemListController(context: context, state: signal)
}
