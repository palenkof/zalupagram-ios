import Foundation
import Postbox
import ZalupaGramCore

// ZalupaGram fork: anti-delete. A message deleted by others is not removed
// from the database: it gets this attribute, the chat shows it with the
// «deleted» mark and its media stays in the cache. The server no longer
// has it, so history validation leaves such messages alone.
public final class ZalupaGramDeletedMessageAttribute: MessageAttribute {
    public let date: Int32

    public init(date: Int32) {
        self.date = date
    }

    required public init(decoder: PostboxDecoder) {
        self.date = decoder.decodeInt32ForKey("d", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.date, forKey: "d")
    }
}

extension Message {
    var zalupaGramIsKeptDeleted: Bool {
        for attribute in self.attributes {
            if attribute is ZalupaGramDeletedMessageAttribute {
                return true
            }
        }
        return false
    }
}

public extension EngineMessage {
    // When the message was deleted by others, nil if it wasn't.
    var zalupaGramDeletedDate: Int32? {
        for attribute in self.attributes {
            if let attribute = attribute as? ZalupaGramDeletedMessageAttribute {
                return attribute.date
            }
        }
        return nil
    }
}

public func zalupaGramKeeperKey(_ id: EngineMessage.Id) -> ZalupaGramKeeper.Key {
    return ZalupaGramKeeper.Key(peerId: id.peerId.toInt64(), namespace: id.namespace, id: id.id)
}

public func zalupaGramMessageId(_ key: ZalupaGramKeeper.Key) -> EngineMessage.Id {
    return EngineMessage.Id(peerId: PeerId(key.peerId), namespace: key.namespace, id: key.id)
}

public func zalupaGramPeerId(_ value: Int64) -> EnginePeer.Id {
    return PeerId(value)
}

// What the message shows instead of text, for the list of deleted messages.
private func zalupaGramMediaKind(_ message: Message) -> String? {
    for media in message.media {
        if media is TelegramMediaAction {
            return "service"
        } else if media is TelegramMediaImage {
            return "photo"
        } else if let file = media as? TelegramMediaFile {
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
        } else if media is TelegramMediaPoll {
            return "poll"
        } else if media is TelegramMediaMap {
            return "location"
        } else if media is TelegramMediaContact {
            return "contact"
        }
    }
    return nil
}

// Marks the messages that can be kept and returns the ones that have to be
// deleted as usual.
func zalupaGramKeepDeletedMessages(transaction: Transaction, accountPeerId: PeerId, ids: [MessageId]) -> [MessageId] {
    if !ZalupaGramCore.option(.keepDeleted) || ids.isEmpty {
        return ids
    }
    let now = Int32(Date().timeIntervalSince1970)
    let keeper = ZalupaGramKeeper.forAccount(accountPeerId.toInt64())
    var remaining: [MessageId] = []
    for id in ids {
        guard id.namespace == Namespaces.Message.Cloud, let message = transaction.getMessage(id) else {
            remaining.append(id)
            continue
        }
        if message.zalupaGramIsKeptDeleted {
            continue
        }
        let mediaKind = zalupaGramMediaKind(message)
        if mediaKind == "service" {
            remaining.append(id)
            continue
        }
        transaction.updateMessage(id, update: { current in
            var storeForwardInfo: StoreMessageForwardInfo?
            if let forwardInfo = current.forwardInfo {
                storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
            }
            var attributes = current.attributes
            attributes.append(ZalupaGramDeletedMessageAttribute(date: now))
            return .update(StoreMessage(id: current.id, customStableId: nil, globallyUniqueId: current.globallyUniqueId, groupingKey: current.groupingKey, threadId: current.threadId, timestamp: current.timestamp, flags: StoreMessageFlags(current.flags), tags: current.tags, globalTags: current.globalTags, localTags: current.localTags, forwardInfo: storeForwardInfo, authorId: current.author?.id, text: current.text, attributes: attributes, media: current.media))
        })
        var text = message.text
        if let mediaKind {
            text = "[\(mediaKind)]" + (text.isEmpty ? "" : " " + text)
        }
        keeper.addDeleted(ZalupaGramKeeper.DeletedMessage(key: zalupaGramKeeperKey(id), authorId: message.author?.id.toInt64(), timestamp: message.timestamp, deletedAt: now, outgoing: !message.flags.contains(.Incoming), text: text))
        Logger.shared.log("ZalupaGram", "kept deleted message \(id)")
    }
    return remaining
}

// Called before a server edit replaces the text of a message.
func zalupaGramRememberEdit(accountPeerId: PeerId, previous: Message, updatedText: String) {
    if !ZalupaGramCore.option(.keepEdits) || previous.text == updatedText || !previous.flags.contains(.Incoming) {
        return
    }
    var date = previous.timestamp
    for attribute in previous.attributes {
        if let attribute = attribute as? EditedMessageAttribute, attribute.date != 0 {
            date = attribute.date
        }
    }
    ZalupaGramKeeper.forAccount(accountPeerId.toInt64()).addEditVersion(zalupaGramKeeperKey(previous.id), text: previous.text, date: date)
}

// ZalupaGram fork: name, username and photo changes of contacts and users
// with a private chat, as the client sees them.
func zalupaGramRecordProfileChange(transaction: Transaction, accountPeerId: PeerId, previous: Peer?, updated: Peer) {
    guard ZalupaGramCore.option(.profileHistory), let previous = previous as? TelegramUser, let updatedUser = updated as? TelegramUser, previous.id != accountPeerId else {
        return
    }
    let merged = TelegramUser.merge(lhs: previous, rhs: updatedUser)
    var changes: [ZalupaGramKeeper.ProfileChange] = []
    let now = Int32(Date().timeIntervalSince1970)

    let fullName: (TelegramUser) -> String = { user in
        return [user.firstName, user.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }
    let oldName = fullName(previous)
    let newName = fullName(merged)
    if !oldName.isEmpty && !newName.isEmpty && oldName != newName {
        changes.append(ZalupaGramKeeper.ProfileChange(kind: .name, old: oldName, new: newName, date: now))
    }

    let oldUsername = previous.username ?? ""
    let newUsername = merged.username ?? ""
    if oldUsername != newUsername {
        changes.append(ZalupaGramKeeper.ProfileChange(kind: .username, old: oldUsername, new: newUsername, date: now))
    }

    let oldPhoto = Set(previous.photo.map { $0.resource.id.stringRepresentation })
    let newPhoto = Set(merged.photo.map { $0.resource.id.stringRepresentation })
    if oldPhoto.isDisjoint(with: newPhoto) && !(oldPhoto.isEmpty && newPhoto.isEmpty) {
        changes.append(ZalupaGramKeeper.ProfileChange(kind: .photo, old: oldPhoto.isEmpty ? "" : "photo", new: newPhoto.isEmpty ? "" : "photo", date: now))
    }

    if changes.isEmpty {
        return
    }
    if !transaction.isPeerContact(peerId: previous.id) && transaction.getPeerChatListIndex(previous.id) == nil {
        return
    }
    let keeper = ZalupaGramKeeper.forAccount(accountPeerId.toInt64())
    for change in changes {
        keeper.addProfileChange(peerId: previous.id.toInt64(), change)
    }
}

// ZalupaGram fork: pinned chats over the server limit. The server keeps up
// to 5 (10 with Premium), the rest are pinned only in this app: they are
// kept in the account's preferences, never sent with the pinned order and
// added back whenever the server order replaces the local one.
private let zalupaGramLocalPinsKey: ValueBoxKey = {
    let key = ValueBoxKey(length: 4)
    key.setInt32(0, value: 0x5A470001)
    return key
}()

private struct ZalupaGramLocalPins: Codable, Equatable {
    struct Group: Codable, Equatable {
        var groupId: Int32
        var peerIds: [Int64]
    }

    var groups: [Group]
}

func zalupaGramLocalPinnedItemIds(transaction: Transaction, groupId: PeerGroupId) -> [PinnedItemId] {
    let value = transaction.getPreferencesEntry(key: zalupaGramLocalPinsKey)?.get(ZalupaGramLocalPins.self) ?? ZalupaGramLocalPins(groups: [])
    let peerIds = value.groups.first(where: { $0.groupId == groupId.rawValue })?.peerIds ?? []
    return peerIds.map { .peer(PeerId($0)) }
}

private func zalupaGramSetLocalPinnedItemIds(transaction: Transaction, groupId: PeerGroupId, itemIds: [PinnedItemId]) {
    var value = transaction.getPreferencesEntry(key: zalupaGramLocalPinsKey)?.get(ZalupaGramLocalPins.self) ?? ZalupaGramLocalPins(groups: [])
    value.groups.removeAll(where: { $0.groupId == groupId.rawValue })
    let peerIds = itemIds.map { itemId -> Int64 in
        switch itemId {
        case let .peer(peerId):
            return peerId.toInt64()
        }
    }
    if !peerIds.isEmpty {
        value.groups.append(ZalupaGramLocalPins.Group(groupId: groupId.rawValue, peerIds: peerIds))
    }
    transaction.setPreferencesEntry(key: zalupaGramLocalPinsKey, value: PreferencesEntry(value))
}

// The server pinned order with the local pins after it.
func zalupaGramWithLocalPins(transaction: Transaction, groupId: PeerGroupId, serverItemIds: [PinnedItemId]) -> [PinnedItemId] {
    var result = serverItemIds
    for itemId in zalupaGramLocalPinnedItemIds(transaction: transaction, groupId: groupId) where !result.contains(itemId) {
        if case let .peer(peerId) = itemId, transaction.getPeer(peerId) != nil, transaction.getPeerChatListInclusion(peerId) != .notIncluded {
            result.append(itemId)
        }
    }
    return result
}

// Pins or unpins over the limit locally. Returns false when the usual
// server pinning has to be done.
func zalupaGramToggleLocalPin(transaction: Transaction, groupId: PeerGroupId, itemId: PinnedItemId, limitExceeded: Bool) -> Bool {
    var localItemIds = zalupaGramLocalPinnedItemIds(transaction: transaction, groupId: groupId)
    var itemIds = transaction.getPinnedItemIds(groupId: groupId)
    if let index = localItemIds.firstIndex(of: itemId) {
        localItemIds.remove(at: index)
        itemIds.removeAll(where: { $0 == itemId })
        zalupaGramSetLocalPinnedItemIds(transaction: transaction, groupId: groupId, itemIds: localItemIds)
        transaction.setPinnedItemIds(groupId: groupId, itemIds: itemIds)
        return true
    }
    if limitExceeded && ZalupaGramCore.option(.localPins) && !itemIds.contains(itemId) {
        localItemIds.append(itemId)
        itemIds.append(itemId)
        zalupaGramSetLocalPinnedItemIds(transaction: transaction, groupId: groupId, itemIds: localItemIds)
        transaction.setPinnedItemIds(groupId: groupId, itemIds: itemIds)
        return true
    }
    return false
}
