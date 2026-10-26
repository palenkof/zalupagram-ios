import Foundation
import Postbox
internal import TelegramApi
import SwiftSignalKit

// ZalupaGram fork: chat statistics. The history is loaded from the server
// page by page (100 messages) and counted on the fly: messages are not kept,
// so even hundreds of thousands fit in memory. Nothing is stored.
public struct ZalupaGramChatStats {
    public struct Author {
        public var peerId: EnginePeer.Id
        public var messages: Int
        public var characters: Int
        // Seconds between someone else's message and this author's answer.
        public var responseTimes: [Int32]
    }

    public var total: Int
    public var firstDate: Int32
    public var lastDate: Int32
    public var authors: [Author]
    public var byHour: [Int]
    // Monday first.
    public var byWeekday: [Int]
    public var topWords: [(String, Int)]
    public var media: [(String, Int)]
    public var peers: [EnginePeer.Id: EnginePeer]
    // False when the loading stopped before the beginning of the chat.
    public var isComplete: Bool
}

private func statsMediaKind(_ media: [Media]) -> String? {
    for item in media {
        if item is TelegramMediaAction {
            return "service"
        } else if item is TelegramMediaImage {
            return "photo"
        } else if let file = item as? TelegramMediaFile {
            if file.isSticker || file.isAnimatedSticker || file.isVideoSticker {
                return "sticker"
            } else if file.isVoice {
                return "voice"
            } else if file.isInstantVideo {
                return "round"
            } else if file.isAnimated {
                return "gif"
            } else if file.isVideo {
                return "video"
            } else if file.isMusic {
                return "music"
            } else {
                return "file"
            }
        } else if item is TelegramMediaPoll {
            return "poll"
        } else if item is TelegramMediaWebpage {
            return "link"
        } else if item is TelegramMediaMap {
            return "location"
        }
    }
    return nil
}

// Messages come newest first.
private final class ChatStatsAccumulator {
    private static let maxWords = 150000

    var total = 0
    var firstDate: Int32 = 0
    var lastDate: Int32 = 0
    var authors: [PeerId: ZalupaGramChatStats.Author] = [:]
    var byHour = Array(repeating: 0, count: 24)
    var byWeekday = Array(repeating: 0, count: 7)
    var words: [String: Int] = [:]
    var media: [String: Int] = [:]
    var peers: [PeerId: Peer] = [:]
    private var newer: (authorId: PeerId, timestamp: Int32)?
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar
    }()

    func add(authorId: PeerId, timestamp: Int32, text: String, mediaKind: String?) {
        if mediaKind == "service" {
            return
        }
        self.total += 1
        if self.lastDate == 0 {
            self.lastDate = timestamp
        }
        self.firstDate = timestamp

        var author = self.authors[authorId] ?? ZalupaGramChatStats.Author(peerId: authorId, messages: 0, characters: 0, responseTimes: [])
        author.messages += 1
        author.characters += text.count
        self.authors[authorId] = author

        // The newer message answers this one when the authors differ.
        if let newer = self.newer, newer.authorId != authorId {
            let gap = newer.timestamp - timestamp
            if gap >= 0 && gap < 6 * 60 * 60 {
                self.authors[newer.authorId]?.responseTimes.append(gap)
            }
        }
        self.newer = (authorId, timestamp)

        let components = self.calendar.dateComponents([.hour, .weekday], from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
        if let hour = components.hour, hour >= 0 && hour < 24 {
            self.byHour[hour] += 1
        }
        if let weekday = components.weekday {
            // Calendar: Sunday = 1.
            self.byWeekday[(weekday + 5) % 7] += 1
        }
        if let mediaKind {
            self.media[mediaKind, default: 0] += 1
        }
        if !text.isEmpty {
            for word in text.lowercased().components(separatedBy: CharacterSet.letters.inverted) where word.count >= 4 {
                self.words[word, default: 0] += 1
            }
            if self.words.count > ChatStatsAccumulator.maxWords {
                // Rare words can't get to the top anyway.
                self.words = self.words.filter { $0.value > 1 }
            }
        }
    }

    func result(isComplete: Bool) -> ZalupaGramChatStats {
        var peers: [EnginePeer.Id: EnginePeer] = [:]
        for (id, peer) in self.peers where self.authors[id] != nil {
            peers[id] = EnginePeer(peer)
        }
        return ZalupaGramChatStats(
            total: self.total,
            firstDate: self.firstDate,
            lastDate: self.lastDate,
            authors: self.authors.values.sorted(by: { $0.messages > $1.messages }),
            byHour: self.byHour,
            byWeekday: self.byWeekday,
            topWords: Array(self.words.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }).prefix(20)).map { ($0.key, $0.value) },
            media: self.media.sorted(by: { $0.value > $1.value }).map { ($0.key, $0.value) },
            peers: peers,
            isComplete: isComplete
        )
    }
}

// Requests pages one after another from the network callbacks, so the
// chain doesn't grow with the number of pages.
private final class ChatStatsLoader {
    private let account: Account
    private let inputPeer: Api.InputPeer
    private let isForum: Bool
    private let limit: Int?
    private let progress: (Int) -> Void
    private let completion: (ZalupaGramChatStats) -> Void
    private let queue = Queue()
    private let accumulator = ChatStatsAccumulator()
    private let disposable = MetaDisposable()
    private var loaded = 0
    private var cancelled = false

    init(account: Account, inputPeer: Api.InputPeer, isForum: Bool, limit: Int?, progress: @escaping (Int) -> Void, completion: @escaping (ZalupaGramChatStats) -> Void) {
        self.account = account
        self.inputPeer = inputPeer
        self.isForum = isForum
        self.limit = limit
        self.progress = progress
        self.completion = completion
    }

    func start() {
        self.queue.async {
            self.request(offsetId: 0)
        }
    }

    func cancel() {
        self.queue.async {
            self.cancelled = true
            self.disposable.dispose()
        }
    }

    private func request(offsetId: Int32) {
        let signal = self.account.network.request(Api.functions.messages.getHistory(peer: self.inputPeer, offsetId: offsetId, offsetDate: 0, addOffset: 0, limit: 100, maxId: 0, minId: 0, hash: 0))
        |> map(Optional.init)
        |> `catch` { _ -> Signal<Api.messages.Messages?, NoError> in
            return .single(nil)
        }
        |> deliverOn(self.queue)
        self.disposable.set(signal.start(next: { [weak self] result in
            self?.process(result)
        }))
    }

    private func process(_ result: Api.messages.Messages?) {
        if self.cancelled {
            return
        }
        guard let result else {
            // A failed page: what is counted so far.
            self.completion(self.accumulator.result(isComplete: false))
            return
        }
        var apiMessages: [Api.Message] = []
        var apiChats: [Api.Chat] = []
        var apiUsers: [Api.User] = []
        switch result {
        case let .messages(data):
            apiMessages = data.messages
            apiChats = data.chats
            apiUsers = data.users
        case let .messagesSlice(data):
            apiMessages = data.messages
            apiChats = data.chats
            apiUsers = data.users
        case let .channelMessages(data):
            apiMessages = data.messages
            apiChats = data.chats
            apiUsers = data.users
        default:
            break
        }
        for chat in apiChats {
            if let peer = parseTelegramGroupOrChannel(chat: chat), self.accumulator.peers[peer.id] == nil {
                self.accumulator.peers[peer.id] = peer
            }
        }
        for user in apiUsers {
            let peer = TelegramUser(user: user)
            if self.accumulator.peers[peer.id] == nil {
                self.accumulator.peers[peer.id] = peer
            }
        }
        var minId: Int32?
        for apiMessage in apiMessages {
            guard let message = StoreMessage(apiMessage: apiMessage, accountPeerId: self.account.peerId, peerIsForum: self.isForum), case let .Id(id) = message.id else {
                continue
            }
            minId = min(minId ?? id.id, id.id)
            var authorId = message.authorId ?? id.peerId
            if message.authorId == nil && !message.flags.contains(.Incoming) {
                authorId = self.account.peerId
            }
            self.accumulator.add(authorId: authorId, timestamp: message.timestamp, text: message.text, mediaKind: statsMediaKind(message.media))
            self.loaded += 1
        }
        self.progress(self.loaded)

        guard let minId, minId > 1, !apiMessages.isEmpty else {
            self.completion(self.accumulator.result(isComplete: true))
            return
        }
        if let limit = self.limit, self.loaded >= limit {
            self.completion(self.accumulator.result(isComplete: false))
            return
        }
        self.request(offsetId: minId)
    }
}

// `limit` messages from the end, nil for the whole chat. `progress` gets
// the number of loaded messages. Disposing stops the loading.
public func zalupaGramCollectChatStats(engine: TelegramEngine, peerId: EnginePeer.Id, limit: Int?, progress: @escaping (Int) -> Void) -> Signal<ZalupaGramChatStats?, NoError> {
    let account = engine.account
    return account.postbox.transaction { transaction -> (Api.InputPeer, Bool)? in
        guard let peer = transaction.getPeer(peerId), let inputPeer = apiInputPeer(peer) else {
            return nil
        }
        return (inputPeer, peer.isForum)
    }
    |> mapToSignal { value -> Signal<ZalupaGramChatStats?, NoError> in
        guard let (inputPeer, isForum) = value else {
            return .single(nil)
        }
        return Signal { subscriber in
            let loader = ChatStatsLoader(account: account, inputPeer: inputPeer, isForum: isForum, limit: limit, progress: progress, completion: { stats in
                subscriber.putNext(stats)
                subscriber.putCompletion()
            })
            loader.start()
            return ActionDisposable {
                loader.cancel()
            }
        }
    }
}
