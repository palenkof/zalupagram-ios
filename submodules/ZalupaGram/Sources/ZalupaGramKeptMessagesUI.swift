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

// ZalupaGram fork: screens for anti-delete, the same as in ZalupaGram
// Desktop: the edit history of a message and the list of all messages
// deleted by others.

private func formatKeptDate(_ timestamp: Int32, ru: Bool) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: ru ? "ru_RU" : "en_US")
    formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
}

// "[photo] caption" from TelegramCore into a readable line.
private func keptText(_ text: String, ru: Bool) -> String {
    let labels: [String: (String, String)] = [
        "photo": ("📷 Photo", "📷 Фото"),
        "video": ("🎥 Video", "🎥 Видео"),
        "gif": ("🎞 GIF", "🎞 GIF"),
        "voice": ("🎤 Voice message", "🎤 Голосовое"),
        "round": ("⭕️ Video message", "⭕️ Кружок"),
        "sticker": ("🎭 Sticker", "🎭 Стикер"),
        "music": ("🎵 Music", "🎵 Музыка"),
        "file": ("📎 File", "📎 Файл"),
        "poll": ("📊 Poll", "📊 Опрос"),
        "location": ("📍 Location", "📍 Геопозиция"),
        "contact": ("👤 Contact", "👤 Контакт"),
    ]
    if text.hasPrefix("["), let end = text.firstIndex(of: "]") {
        let kind = String(text[text.index(after: text.startIndex) ..< end])
        if let label = labels[kind] {
            let rest = text[text.index(after: end)...].trimmingCharacters(in: .whitespaces)
            return (ru ? label.1 : label.0) + (rest.isEmpty ? "" : ": " + rest)
        }
    }
    return text.isEmpty ? (ru ? "(без текста)" : "(no text)") : text
}

// MARK: Edit history

public func zalupaGramHasEditHistory(context: AccountContext, messageId: EngineMessage.Id) -> Bool {
    return !ZalupaGramKeeper.forAccount(context.account.peerId.toInt64()).editVersions(zalupaGramKeeperKey(messageId)).isEmpty
}

public func zalupaGramEditHistoryTitle(strings: PresentationStrings) -> String {
    return ZalupaGram.tr(strings, "Edit history", "История правок")
}

private enum EditHistoryEntry: ItemListNodeEntry {
    case header(String)
    case version(Int32, String, String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .header:
            return 0
        case let .version(index, _, _):
            return 1 + index
        }
    }

    static func ==(lhs: EditHistoryEntry, rhs: EditHistoryEntry) -> Bool {
        switch lhs {
        case let .header(text):
            if case .header(text) = rhs {
                return true
            }
            return false
        case let .version(index, label, text):
            if case .version(index, label, text) = rhs {
                return true
            }
            return false
        }
    }

    static func <(lhs: EditHistoryEntry, rhs: EditHistoryEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .version(_, label, text):
            return ItemListTextWithLabelItem(presentationData: presentationData, label: label, text: text, style: .blocks, enabledEntityTypes: [], multiline: true, sectionId: self.section, action: nil)
        }
    }
}

public func zalupaGramEditHistoryController(context: AccountContext, message: EngineMessage) -> ViewController {
    let versions = ZalupaGramKeeper.forAccount(context.account.peerId.toInt64()).editVersions(zalupaGramKeeperKey(message.id))
    var currentDate = message.timestamp
    for attribute in message.attributes {
        if let attribute = attribute as? EditedMessageAttribute, attribute.date != 0 {
            currentDate = attribute.date
        }
    }
    let currentText = message.text
    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let ru = zalupaGramIsRussian(presentationData.strings)
        var entries: [EditHistoryEntry] = []
        entries.append(.header(ru ? "СТАРЫЕ ВЕРСИИ СВЕРХУ" : "OLDEST FIRST"))
        for (index, version) in versions.enumerated() {
            entries.append(.version(Int32(index), formatKeptDate(version.date, ru: ru), keptText(version.text, ru: ru)))
        }
        entries.append(.version(Int32(versions.count), (ru ? "Сейчас · " : "Now · ") + formatKeptDate(currentDate, ru: ru), keptText(currentText, ru: ru)))
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(zalupaGramEditHistoryTitle(strings: presentationData.strings)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, emptyStateItem: nil, animateChanges: false)
        return (controllerState, (listState, Void()))
    }
    return ItemListController(context: context, state: signal)
}

// MARK: Deleted messages

public func zalupaGramDeletedMessagesCount(context: AccountContext) -> Int {
    return ZalupaGramKeeper.forAccount(context.account.peerId.toInt64()).deletedCount
}

private final class DeletedMessagesArguments {
    let open: (ZalupaGramKeeper.Key) -> Void
    let clear: () -> Void

    init(open: @escaping (ZalupaGramKeeper.Key) -> Void, clear: @escaping () -> Void) {
        self.open = open
        self.clear = clear
    }
}

private enum DeletedMessagesEntry: ItemListNodeEntry {
    case info(String)
    case message(Int32, ZalupaGramKeeper.Key, String, String)
    case clear(String)

    var section: ItemListSectionId {
        switch self {
        case .info, .message:
            return 0
        case .clear:
            return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .info:
            return 0
        case let .message(index, _, _, _):
            return 1 + index
        case .clear:
            return Int32.max
        }
    }

    static func ==(lhs: DeletedMessagesEntry, rhs: DeletedMessagesEntry) -> Bool {
        switch lhs {
        case let .info(text):
            if case .info(text) = rhs {
                return true
            }
            return false
        case let .message(index, key, label, text):
            if case .message(index, key, label, text) = rhs {
                return true
            }
            return false
        case let .clear(text):
            if case .clear(text) = rhs {
                return true
            }
            return false
        }
    }

    static func <(lhs: DeletedMessagesEntry, rhs: DeletedMessagesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DeletedMessagesArguments
        switch self {
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .message(_, key, label, text):
            return ItemListTextWithLabelItem(presentationData: presentationData, label: label, text: text, style: .blocks, enabledEntityTypes: [], multiline: true, sectionId: self.section, action: {
                arguments.open(key)
            })
        case let .clear(text):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: .destructive, alignment: .center, sectionId: self.section, style: .blocks, action: {
                arguments.clear()
            })
        }
    }
}

private struct DeletedMessagesData {
    var messages: [ZalupaGramKeeper.DeletedMessage]
    var peers: [EnginePeer.Id: EnginePeer]
}

private let deletedShown = 500

public func zalupaGramDeletedMessagesController(context: AccountContext) -> ViewController {
    let keeper = ZalupaGramKeeper.forAccount(context.account.peerId.toInt64())
    let reloadPromise = ValuePromise<Int>(0, ignoreRepeated: false)
    var reloadCounter = 0
    let reload: () -> Void = {
        reloadCounter += 1
        reloadPromise.set(reloadCounter)
    }

    let dataSignal: Signal<DeletedMessagesData, NoError> = reloadPromise.get()
    |> mapToSignal { _ -> Signal<DeletedMessagesData, NoError> in
        let list = Array(keeper.deletedMessages().prefix(deletedShown))
        var peerIds = Set<EnginePeer.Id>()
        for message in list {
            peerIds.insert(zalupaGramPeerId(message.key.peerId))
            if let authorId = message.authorId {
                peerIds.insert(zalupaGramPeerId(authorId))
            }
        }
        return context.engine.data.get(
            EngineDataMap(peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init(id:))),
            EngineDataMap(list.map { TelegramEngine.EngineData.Item.Messages.Message(id: zalupaGramMessageId($0.key)) })
        )
        |> map { peerMap, messageMap -> DeletedMessagesData in
            var peers: [EnginePeer.Id: EnginePeer] = [:]
            for (id, peer) in peerMap {
                if let peer {
                    peers[id] = peer
                }
            }
            // Deleted by the user afterwards: drop them from the list too.
            var missing: [ZalupaGramKeeper.Key] = []
            var shown: [ZalupaGramKeeper.DeletedMessage] = []
            for message in list {
                if case .some(.some) = messageMap[zalupaGramMessageId(message.key)] {
                    shown.append(message)
                } else {
                    missing.append(message.key)
                }
            }
            keeper.removeDeleted(missing)
            return DeletedMessagesData(messages: shown, peers: peers)
        }
    }

    var presentControllerImpl: ((ViewController) -> Void)?
    var openChatImpl: ((EnginePeer, EngineMessage.Id) -> Void)?

    let arguments = DeletedMessagesArguments(open: { key in
        let messageId = zalupaGramMessageId(key)
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: messageId.peerId))
        |> deliverOnMainQueue).startStandalone(next: { peer in
            if let peer {
                openChatImpl?(peer, messageId)
            }
        })
    }, clear: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let ru = zalupaGramIsRussian(presentationData.strings)
        presentControllerImpl?(textAlertController(context: context, title: nil, text: ru ? "Очистить список? Сами сообщения останутся в чатах с пометкой «удалено»." : "Clear the list? The messages stay in the chats with the «deleted» mark.", actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: ru ? "Очистить" : "Clear", action: {
                keeper.clearDeleted()
                reload()
            })
        ]))
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, dataSignal)
    |> map { presentationData, data -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let ru = zalupaGramIsRussian(presentationData.strings)
        var entries: [DeletedMessagesEntry] = []
        if data.messages.isEmpty {
            entries.append(.info(ru ? "Пока ничего не удалили. Сообщения, которые удалят собеседники, останутся в чате с пометкой «удалено» и появятся здесь." : "Nothing deleted yet. Messages deleted by others stay in the chat with the «deleted» mark and show up here."))
        } else {
            entries.append(.info(ru ? "Нажмите, чтобы открыть сообщение в чате." : "Tap to open the message in the chat."))
        }
        for (index, message) in data.messages.enumerated() {
            let chatId = zalupaGramPeerId(message.key.peerId)
            let chatTitle = data.peers[chatId]?.compactDisplayTitle ?? "?"
            var author: String
            if message.outgoing {
                author = ru ? "Вы" : "You"
            } else if let authorId = message.authorId, let peer = data.peers[zalupaGramPeerId(authorId)] {
                author = peer.compactDisplayTitle
            } else {
                author = chatTitle
            }
            if message.authorId.flatMap(zalupaGramPeerId) != chatId && author != chatTitle {
                author += " → " + chatTitle
            }
            let label = author + " · " + formatKeptDate(message.timestamp, ru: ru)
            entries.append(.message(Int32(index), message.key, label, keptText(message.text, ru: ru)))
        }
        if !data.messages.isEmpty {
            entries.append(.clear(ru ? "Очистить список" : "Clear the list"))
        }
        let title = ru ? "Удалённые сообщения" : "Deleted messages"
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, emptyStateItem: nil, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    openChatImpl = { [weak controller] peer, messageId in
        guard let navigationController = controller?.navigationController as? NavigationController else {
            return
        }
        context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), subject: .message(id: .id(messageId), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false), keepStack: .always))
    }
    return controller
}
