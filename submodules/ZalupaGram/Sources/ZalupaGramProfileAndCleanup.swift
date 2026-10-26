import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import OverlayStatusController
import ZalupaGramCore

// ZalupaGram fork: the profile history of a user and the removal of all
// your own messages in a group.

// MARK: Profile history

private func formatChangeDate(_ timestamp: Int32, ru: Bool) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: ru ? "ru_RU" : "en_US")
    formatter.dateFormat = "dd.MM.yyyy HH:mm"
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
}

private func changeTitle(_ change: ZalupaGramKeeper.ProfileChange, ru: Bool) -> String {
    switch change.kind {
    case .name:
        return ru ? "Имя" : "Name"
    case .username:
        return ru ? "Юзернейм" : "Username"
    case .photo:
        return ru ? "Аватарка" : "Photo"
    }
}

private func changeText(_ change: ZalupaGramKeeper.ProfileChange, ru: Bool) -> String {
    switch change.kind {
    case .name:
        return change.old + " → " + change.new
    case .username:
        let none = ru ? "нет" : "none"
        return (change.old.isEmpty ? none : "@" + change.old) + " → " + (change.new.isEmpty ? none : "@" + change.new)
    case .photo:
        if change.new.isEmpty {
            return ru ? "удалена" : "removed"
        } else if change.old.isEmpty {
            return ru ? "поставлена" : "set"
        } else {
            return ru ? "сменена" : "changed"
        }
    }
}

// The newest change in one line, nil if nothing was noticed.
public func zalupaGramProfileHistorySummary(context: AccountContext, peerId: EnginePeer.Id, strings: PresentationStrings) -> String? {
    let changes = ZalupaGramKeeper.forAccount(context.account.peerId.toInt64()).profileChanges(peerId: peerId.toInt64())
    guard let last = changes.last else {
        return nil
    }
    let ru = zalupaGramIsRussian(strings)
    let count = changes.count
    let more = count > 1 ? (ru ? " (всего \(count))" : " (\(count) in total)") : ""
    return changeTitle(last, ru: ru) + ": " + changeText(last, ru: ru) + more
}

public func zalupaGramProfileHistoryTitle(strings: PresentationStrings) -> String {
    return ZalupaGram.tr(strings, "Profile history", "История профиля")
}

private enum ProfileHistoryEntry: ItemListNodeEntry {
    case change(Int32, String, String)
    case info(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case let .change(index, _, _):
            return index
        case .info:
            return Int32.max
        }
    }

    static func ==(lhs: ProfileHistoryEntry, rhs: ProfileHistoryEntry) -> Bool {
        switch lhs {
        case let .change(index, label, text):
            if case .change(index, label, text) = rhs {
                return true
            }
            return false
        case let .info(text):
            if case .info(text) = rhs {
                return true
            }
            return false
        }
    }

    static func <(lhs: ProfileHistoryEntry, rhs: ProfileHistoryEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .change(_, label, text):
            return ItemListTextWithLabelItem(presentationData: presentationData, label: label, text: text, style: .blocks, enabledEntityTypes: [], multiline: true, sectionId: self.section, action: nil)
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func zalupaGramProfileHistoryController(context: AccountContext, peerId: EnginePeer.Id) -> ViewController {
    let changes = ZalupaGramKeeper.forAccount(context.account.peerId.toInt64()).profileChanges(peerId: peerId.toInt64())
    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let ru = zalupaGramIsRussian(presentationData.strings)
        var entries: [ProfileHistoryEntry] = []
        for (index, change) in changes.reversed().enumerated() {
            entries.append(.change(Int32(index), changeTitle(change, ru: ru) + " · " + formatChangeDate(change.date, ru: ru), changeText(change, ru: ru)))
        }
        entries.append(.info(ru ? "Изменения, которые заметило приложение, новые сверху. Время — когда приложение их увидело, а не когда их сделали." : "Changes the app has noticed, newest first. The time is when the app saw them, not when they were made."))
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(zalupaGramProfileHistoryTitle(strings: presentationData.strings)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, emptyStateItem: nil, animateChanges: false)
        return (controllerState, (listState, Void()))
    }
    return ItemListController(context: context, state: signal)
}

// MARK: Delete my messages

public func zalupaGramDeleteMyMessagesTitle(strings: PresentationStrings) -> String {
    return ZalupaGram.tr(strings, "🧹 Delete my messages", "🧹 Удалить мои сообщения")
}

private let searchPageLimit: Int32 = 100
private let maxSearchPages = 300

// All messages of the account in the chat, found through the server search.
private func myMessageIds(context: AccountContext, peerId: EnginePeer.Id) -> Signal<[EngineMessage.Id], NoError> {
    let location: SearchMessagesLocation = .peer(peerId: peerId, fromId: context.account.peerId, tags: nil, reactions: nil, threadId: nil, minDate: nil, maxDate: nil)
    func page(_ state: SearchMessagesState?, _ collected: [EngineMessage.Id], _ pageIndex: Int) -> Signal<[EngineMessage.Id], NoError> {
        return context.engine.messages.searchMessages(location: location, query: "", state: state, limit: searchPageLimit)
        |> take(1)
        |> mapToSignal { result, nextState -> Signal<[EngineMessage.Id], NoError> in
            var collected = collected
            var known = Set(collected)
            var added = 0
            for message in result.messages.map(EngineMessage.init) where message.id.peerId == peerId && message.author?.id == context.account.peerId && !known.contains(message.id) {
                collected.append(message.id)
                known.insert(message.id)
                added += 1
            }
            if result.completed || added == 0 || pageIndex + 1 >= maxSearchPages {
                return .single(collected)
            }
            return page(nextState, collected, pageIndex + 1)
        }
    }
    return page(nil, [], 0)
}

public func zalupaGramDeleteMyMessages(context: AccountContext, peerId: EnginePeer.Id, present: @escaping (ViewController) -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let ru = zalupaGramIsRussian(presentationData.strings)
    let alert: (String) -> Void = { text in
        present(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]))
    }

    let searching = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
    present(searching)
    let _ = (myMessageIds(context: context, peerId: peerId)
    |> deliverOnMainQueue).startStandalone(next: { ids in
        searching.dismiss()
        if ids.isEmpty {
            alert(ru ? "Ваших сообщений в этом чате не найдено." : "No messages of yours in this chat.")
            return
        }
        present(textAlertController(context: context, title: ru ? "Удалить мои сообщения" : "Delete my messages", text: ru ? "Найдено ваших сообщений: \(ids.count). Удалить их у всех? Это нельзя отменить." : "Messages of yours found: \(ids.count). Delete them for everyone? This can't be undone.", actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: presentationData.strings.Common_Delete, action: {
                let deleting = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
                present(deleting)
                // One chunk after another.
                var chain: Signal<Never, NoError> = .complete()
                var index = 0
                while index < ids.count {
                    let chunk = Array(ids[index ..< min(index + 100, ids.count)])
                    chain = chain |> then(context.engine.messages.deleteMessagesInteractively(messageIds: chunk, type: .forEveryone) |> ignoreValues)
                    index += 100
                }
                let _ = (chain
                |> deliverOnMainQueue).startStandalone(completed: {
                    deleting.dismiss()
                    alert(ru ? "Удалено сообщений: \(ids.count)." : "Messages deleted: \(ids.count).")
                })
            })
        ]))
    })
}
