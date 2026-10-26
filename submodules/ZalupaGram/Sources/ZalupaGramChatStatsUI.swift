import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

// ZalupaGram fork: the chat statistics screen, opened from the chat list
// menu: who writes how much, when, answer times, top words and media.

public func zalupaGramChatStatsTitle(strings: PresentationStrings) -> String {
    return ZalupaGram.tr(strings, "📊 Chat statistics", "📊 Статистика чата")
}

private enum StatsState {
    case loading(Int)
    case done(ZalupaGramChatStats)
    case failed
}

private enum StatsEntry: ItemListNodeEntry {
    case header(Int32, String)
    case row(Int32, Int32, String, String)
    case info(Int32, String)

    var section: ItemListSectionId {
        switch self {
        case let .header(section, _), let .row(section, _, _, _), let .info(section, _):
            return section
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(section, _):
            return section * 10000
        case let .row(section, index, _, _):
            return section * 10000 + 1 + index
        case let .info(section, _):
            return section * 10000 + 9999
        }
    }

    static func ==(lhs: StatsEntry, rhs: StatsEntry) -> Bool {
        switch lhs {
        case let .header(section, text):
            if case .header(section, text) = rhs {
                return true
            }
            return false
        case let .row(section, index, label, text):
            if case .row(section, index, label, text) = rhs {
                return true
            }
            return false
        case let .info(section, text):
            if case .info(section, text) = rhs {
                return true
            }
            return false
        }
    }

    static func <(lhs: StatsEntry, rhs: StatsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .row(_, _, label, text):
            return ItemListTextWithLabelItem(presentationData: presentationData, label: label, text: text, style: .blocks, enabledEntityTypes: [], multiline: true, sectionId: self.section, action: nil)
        case let .info(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func formatNumber(_ value: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = " "
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}

private func formatDuration(_ seconds: Int32, ru: Bool) -> String {
    if seconds < 60 {
        return "\(seconds)" + (ru ? " с" : " s")
    } else if seconds < 3600 {
        return "\(seconds / 60)" + (ru ? " мин" : " min")
    } else {
        let hours = Double(seconds) / 3600.0
        return String(format: "%.1f", hours) + (ru ? " ч" : " h")
    }
}

private func bar(_ value: Int, max: Int) -> String {
    if max <= 0 {
        return ""
    }
    let width = Int((Double(value) / Double(max) * 16.0).rounded())
    return String(repeating: "▇", count: Swift.max(value > 0 ? 1 : 0, width))
}

private func mediaTitle(_ kind: String, ru: Bool) -> String {
    let titles: [String: (String, String)] = [
        "photo": ("📷 Photos", "📷 Фото"),
        "video": ("🎥 Videos", "🎥 Видео"),
        "gif": ("🎞 GIFs", "🎞 GIF"),
        "voice": ("🎤 Voice", "🎤 Голосовые"),
        "round": ("⭕️ Round videos", "⭕️ Кружки"),
        "sticker": ("🎭 Stickers", "🎭 Стикеры"),
        "music": ("🎵 Music", "🎵 Музыка"),
        "file": ("📎 Files", "📎 Файлы"),
        "poll": ("📊 Polls", "📊 Опросы"),
        "link": ("🔗 Links", "🔗 Ссылки"),
        "location": ("📍 Locations", "📍 Геопозиции"),
    ]
    if let title = titles[kind] {
        return ru ? title.1 : title.0
    }
    return kind
}

private func statsEntries(state: StatsState, accountPeerId: EnginePeer.Id, presentationData: PresentationData) -> [StatsEntry] {
    let ru = zalupaGramIsRussian(presentationData.strings)
    var entries: [StatsEntry] = []
    switch state {
    case let .loading(count):
        entries.append(.info(0, (ru ? "Загружено сообщений: " : "Messages loaded: ") + formatNumber(count) + (ru ? "\n\nБольшие чаты грузятся долго: около минуты на 20 000 сообщений. Не уходите с этого экрана." : "\n\nBig chats take a while: about a minute per 20,000 messages. Stay on this screen.")))
        return entries
    case .failed:
        entries.append(.info(0, ru ? "Не удалось загрузить историю." : "Couldn't load the history."))
        return entries
    case let .done(stats):
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: ru ? "ru_RU" : "en_US")
        dateFormatter.dateFormat = "dd.MM.yyyy"
        let date: (Int32) -> String = { dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval($0))) }

        entries.append(.header(0, ru ? "ВСЕГО" : "TOTAL"))
        entries.append(.row(0, 0, ru ? "Сообщений" : "Messages", formatNumber(stats.total) + (stats.isComplete ? "" : (ru ? " (последние)" : " (latest)"))))
        if stats.total > 0 {
            entries.append(.row(0, 1, ru ? "Период" : "Period", date(stats.firstDate) + " — " + date(stats.lastDate)))
            let days = max(1, Int((stats.lastDate - stats.firstDate) / 86400) + 1)
            entries.append(.row(0, 2, ru ? "В среднем за день" : "Per day on average", formatNumber(stats.total / days)))
        }

        let name: (EnginePeer.Id) -> String = { peerId in
            if peerId == accountPeerId {
                return ru ? "Вы" : "You"
            }
            return stats.peers[peerId]?.compactDisplayTitle ?? (ru ? "Без имени" : "Unknown")
        }
        entries.append(.header(1, ru ? "КТО СКОЛЬКО ПИШЕТ" : "WHO WRITES HOW MUCH"))
        for (index, author) in stats.authors.prefix(30).enumerated() {
            let percent = stats.total > 0 ? author.messages * 100 / stats.total : 0
            var text = formatNumber(author.messages) + " (\(percent)%) · " + formatNumber(author.characters) + (ru ? " симв." : " chars")
            if !author.responseTimes.isEmpty {
                let sorted = author.responseTimes.sorted()
                text += (ru ? " · отвечает за " : " · answers in ") + formatDuration(sorted[sorted.count / 2], ru: ru)
            }
            entries.append(.row(1, Int32(index), name(author.peerId), text))
        }
        if stats.authors.count > 30 {
            entries.append(.info(1, (ru ? "И ещё участников: " : "More members: ") + "\(stats.authors.count - 30)"))
        }

        let maxHour = stats.byHour.max() ?? 0
        var hours: [String] = []
        for hour in 0 ..< 24 {
            hours.append(String(format: "%02d  ", hour) + bar(stats.byHour[hour], max: maxHour) + " \(stats.byHour[hour])")
        }
        entries.append(.header(2, ru ? "ПО ЧАСАМ" : "BY HOUR"))
        entries.append(.row(2, 0, "", hours.joined(separator: "\n")))

        let weekdays = ru ? ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"] : ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
        let maxDay = stats.byWeekday.max() ?? 0
        var days: [String] = []
        for day in 0 ..< 7 {
            days.append(weekdays[day] + "  " + bar(stats.byWeekday[day], max: maxDay) + " \(stats.byWeekday[day])")
        }
        entries.append(.header(3, ru ? "ПО ДНЯМ НЕДЕЛИ" : "BY WEEKDAY"))
        entries.append(.row(3, 0, "", days.joined(separator: "\n")))

        if !stats.topWords.isEmpty {
            entries.append(.header(4, ru ? "ЧАСТЫЕ СЛОВА (ОТ 4 БУКВ)" : "TOP WORDS (4+ LETTERS)"))
            entries.append(.row(4, 0, "", stats.topWords.enumerated().map { "\($0.offset + 1). \($0.element.0) — \(formatNumber($0.element.1))" }.joined(separator: "\n")))
        }
        if !stats.media.isEmpty {
            entries.append(.header(5, ru ? "МЕДИА" : "MEDIA"))
            for (index, item) in stats.media.enumerated() {
                entries.append(.row(5, Int32(index), mediaTitle(item.0, ru: ru), formatNumber(item.1)))
            }
        }
        entries.append(.info(6, ru ? "Считается на телефоне по истории с сервера, никуда не отправляется. Время ответа — медиана, паузы дольше 6 часов не учитываются." : "Counted on the phone from the server history, sent nowhere. The answer time is the median, pauses over 6 hours are left out."))
        return entries
    }
}

private func statsController(context: AccountContext, peerId: EnginePeer.Id, limit: Int?) -> ViewController {
    let statePromise = Promise<StatsState>(.loading(0))
    let progressPromise = ValuePromise<Int>(0, ignoreRepeated: true)
    let loadDisposable = (zalupaGramCollectChatStats(engine: context.engine, peerId: peerId, limit: limit, progress: { count in
        progressPromise.set(count)
    })
    |> deliverOnMainQueue).startStrict(next: { stats in
        if let stats {
            statePromise.set(.single(.done(stats)))
        } else {
            statePromise.set(.single(.failed))
        }
    })

    let state: Signal<StatsState, NoError> = combineLatest(statePromise.get(), progressPromise.get())
    |> map { state, progress -> StatsState in
        if case .loading = state {
            return .loading(progress)
        }
        return state
    }

    let accountPeerId = context.account.peerId
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, state)
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let title = ZalupaGram.tr(presentationData.strings, "Statistics", "Статистика")
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: statsEntries(state: state, accountPeerId: accountPeerId, presentationData: presentationData), style: .blocks, emptyStateItem: nil, animateChanges: false)
        return (controllerState, (listState, Void()))
    }
    |> afterDisposed {
        // Leaving the screen stops the loading.
        loadDisposable.dispose()
    }
    return ItemListController(context: context, state: signal)
}

// Asks how much of the history to count, then opens the statistics.
public func zalupaGramOpenChatStats(context: AccountContext, peerId: EnginePeer.Id, present: @escaping (ViewController) -> Void, push: @escaping (ViewController) -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let ru = zalupaGramIsRussian(presentationData.strings)
    present(textAlertController(context: context, title: ru ? "Статистика чата" : "Chat statistics", text: ru ? "Сколько сообщений посчитать? Вся история большого чата грузится долго: 300 000 сообщений — минут 10–15." : "How many messages to count? The whole history of a big chat takes long: 300,000 messages is 10–15 minutes.", actions: [
        TextAlertAction(type: .genericAction, title: ru ? "Последние 5 000" : "Last 5,000", action: {
            push(statsController(context: context, peerId: peerId, limit: 5000))
        }),
        TextAlertAction(type: .genericAction, title: ru ? "Последние 50 000" : "Last 50,000", action: {
            push(statsController(context: context, peerId: peerId, limit: 50000))
        }),
        TextAlertAction(type: .genericAction, title: ru ? "Всю историю" : "The whole history", action: {
            push(statsController(context: context, peerId: peerId, limit: nil))
        }),
        TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_Cancel, action: {})
    ], actionLayout: .vertical))
}
