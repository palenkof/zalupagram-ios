import Foundation

// ZalupaGram fork: the list of messages deleted by others, previous
// versions of edited messages, local notes on messages and the profile
// changes of users, kept per account in a JSON file in Application Support. The deleted message itself stays in the chat
// (TelegramCore marks it), this list feeds the «Deleted messages» screen
// and the edit history. Nothing here is sent anywhere.
public final class ZalupaGramKeeper {
    public struct Key: Hashable, Codable {
        public var peerId: Int64
        public var namespace: Int32
        public var id: Int32

        public init(peerId: Int64, namespace: Int32, id: Int32) {
            self.peerId = peerId
            self.namespace = namespace
            self.id = id
        }
    }

    public struct EditVersion: Codable, Equatable {
        public var text: String
        public var date: Int32

        public init(text: String, date: Int32) {
            self.text = text
            self.date = date
        }
    }

    public struct DeletedMessage: Codable {
        public var key: Key
        public var authorId: Int64?
        public var timestamp: Int32
        public var deletedAt: Int32
        public var outgoing: Bool
        public var text: String

        public init(key: Key, authorId: Int64?, timestamp: Int32, deletedAt: Int32, outgoing: Bool, text: String) {
            self.key = key
            self.authorId = authorId
            self.timestamp = timestamp
            self.deletedAt = deletedAt
            self.outgoing = outgoing
            self.text = text
        }
    }

    public struct ProfileChange: Codable {
        public enum Kind: String, Codable {
            case name
            case username
            case photo
        }

        public var kind: Kind
        public var old: String
        public var new: String
        public var date: Int32

        public init(kind: Kind, old: String, new: String, date: Int32) {
            self.kind = kind
            self.old = old
            self.new = new
            self.date = date
        }
    }

    private struct EditEntry: Codable {
        var key: Key
        var versions: [EditVersion]
    }

    private struct NoteEntry: Codable {
        var key: Key
        var text: String
    }

    private struct ProfileEntry: Codable {
        var peerId: Int64
        var changes: [ProfileChange]
    }

    // Fields added later are optional, so older files still load.
    private struct Storage: Codable {
        var deleted: [DeletedMessage] = []
        var edits: [EditEntry] = []
        var notes: [NoteEntry]?
        var profiles: [ProfileEntry]?
    }

    private static let maxDeleted = 3000
    private static let maxEditedMessages = 2000
    private static let maxVersions = 20
    private static let maxTextLength = 4000
    private static let maxProfileChanges = 50
    private static let maxProfiles = 1000

    private final class Registry {
        let lock = NSLock()
        var keepers: [Int64: ZalupaGramKeeper] = [:]
    }

    private static let registry = Registry()

    public static func forAccount(_ accountPeerId: Int64) -> ZalupaGramKeeper {
        let registry = ZalupaGramKeeper.registry
        registry.lock.lock()
        defer {
            registry.lock.unlock()
        }
        if let keeper = registry.keepers[accountPeerId] {
            return keeper
        }
        let keeper = ZalupaGramKeeper(accountPeerId: accountPeerId)
        registry.keepers[accountPeerId] = keeper
        return keeper
    }

    private let url: URL?
    private let lock = NSLock()
    private let saveQueue = DispatchQueue(label: "ZalupaGramKeeper")
    private var deleted: [Key: DeletedMessage] = [:]
    private var edits: [Key: [EditVersion]] = [:]
    private var notes: [Key: String] = [:]
    private var profiles: [Int64: [ProfileChange]] = [:]
    private var saveScheduled = false

    private init(accountPeerId: Int64) {
        if let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let directory = base.appendingPathComponent("ZalupaGram", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.url = directory.appendingPathComponent("kept-\(accountPeerId).json")
        } else {
            self.url = nil
        }
        if let url = self.url, let data = try? Data(contentsOf: url), let storage = try? JSONDecoder().decode(Storage.self, from: data) {
            for message in storage.deleted {
                self.deleted[message.key] = message
            }
            for entry in storage.edits {
                self.edits[entry.key] = entry.versions
            }
            for entry in storage.notes ?? [] {
                self.notes[entry.key] = entry.text
            }
            for entry in storage.profiles ?? [] {
                self.profiles[entry.peerId] = entry.changes
            }
        }
    }

    private static func clipped(_ text: String) -> String {
        if text.count <= ZalupaGramKeeper.maxTextLength {
            return text
        }
        return String(text.prefix(ZalupaGramKeeper.maxTextLength)) + "…"
    }

    // MARK: Deleted messages

    public func addDeleted(_ message: DeletedMessage) {
        var message = message
        message.text = ZalupaGramKeeper.clipped(message.text)
        self.lock.lock()
        self.deleted[message.key] = message
        if self.deleted.count > ZalupaGramKeeper.maxDeleted {
            let removed = self.deleted.values.sorted(by: { $0.deletedAt < $1.deletedAt }).prefix(self.deleted.count - ZalupaGramKeeper.maxDeleted)
            for item in removed {
                self.deleted.removeValue(forKey: item.key)
            }
        }
        self.lock.unlock()
        self.scheduleSave()
    }

    // Newest first.
    public func deletedMessages() -> [DeletedMessage] {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.deleted.values.sorted(by: { lhs, rhs in
            if lhs.deletedAt != rhs.deletedAt {
                return lhs.deletedAt > rhs.deletedAt
            }
            return lhs.timestamp > rhs.timestamp
        })
    }

    public var deletedCount: Int {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.deleted.count
    }

    public func removeDeleted(_ keys: [Key]) {
        if keys.isEmpty {
            return
        }
        self.lock.lock()
        for key in keys {
            self.deleted.removeValue(forKey: key)
        }
        self.lock.unlock()
        self.scheduleSave()
    }

    public func clearDeleted() {
        self.lock.lock()
        self.deleted.removeAll()
        self.lock.unlock()
        self.scheduleSave()
    }

    // MARK: Edit history

    // Remembers the text a message had before an edit.
    public func addEditVersion(_ key: Key, text: String, date: Int32) {
        let version = EditVersion(text: ZalupaGramKeeper.clipped(text), date: date)
        self.lock.lock()
        var versions = self.edits[key] ?? []
        if versions.last != version {
            versions.append(version)
            if versions.count > ZalupaGramKeeper.maxVersions {
                versions.removeFirst(versions.count - ZalupaGramKeeper.maxVersions)
            }
            self.edits[key] = versions
        }
        if self.edits.count > ZalupaGramKeeper.maxEditedMessages {
            let removed = self.edits.sorted(by: { ($0.value.last?.date ?? 0) < ($1.value.last?.date ?? 0) }).prefix(self.edits.count - ZalupaGramKeeper.maxEditedMessages)
            for item in removed {
                self.edits.removeValue(forKey: item.key)
            }
        }
        self.lock.unlock()
        self.scheduleSave()
    }

    // Previous versions, oldest first, without the current text.
    public func editVersions(_ key: Key) -> [EditVersion] {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.edits[key] ?? []
    }

    public var editedCount: Int {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.edits.count
    }

    public func clearEdits() {
        self.lock.lock()
        self.edits.removeAll()
        self.lock.unlock()
        self.scheduleSave()
    }

    // MARK: Notes

    // Local notes on messages, never sent anywhere.
    public func note(_ key: Key) -> String? {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.notes[key]
    }

    public func setNote(_ key: Key, _ text: String?) {
        let text = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.lock.lock()
        if text.isEmpty {
            self.notes.removeValue(forKey: key)
        } else {
            self.notes[key] = ZalupaGramKeeper.clipped(text)
        }
        self.lock.unlock()
        self.scheduleSave()
    }

    public var notesCount: Int {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.notes.count
    }

    // MARK: Profile changes

    public func addProfileChange(peerId: Int64, _ change: ProfileChange) {
        self.lock.lock()
        var changes = self.profiles[peerId] ?? []
        changes.append(change)
        if changes.count > ZalupaGramKeeper.maxProfileChanges {
            changes.removeFirst(changes.count - ZalupaGramKeeper.maxProfileChanges)
        }
        self.profiles[peerId] = changes
        if self.profiles.count > ZalupaGramKeeper.maxProfiles {
            let removed = self.profiles.sorted(by: { ($0.value.last?.date ?? 0) < ($1.value.last?.date ?? 0) }).prefix(self.profiles.count - ZalupaGramKeeper.maxProfiles)
            for item in removed {
                self.profiles.removeValue(forKey: item.key)
            }
        }
        self.lock.unlock()
        self.scheduleSave()
    }

    // Oldest first.
    public func profileChanges(peerId: Int64) -> [ProfileChange] {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return self.profiles[peerId] ?? []
    }

    public func clearProfileChanges(peerId: Int64) {
        self.lock.lock()
        self.profiles.removeValue(forKey: peerId)
        self.lock.unlock()
        self.scheduleSave()
    }

    // MARK: Storage

    private func scheduleSave() {
        self.lock.lock()
        if self.saveScheduled {
            self.lock.unlock()
            return
        }
        self.saveScheduled = true
        self.lock.unlock()
        self.saveQueue.asyncAfter(deadline: .now() + 1.0, execute: { [weak self] in
            self?.save()
        })
    }

    private func save() {
        guard let url = self.url else {
            return
        }
        self.lock.lock()
        self.saveScheduled = false
        var storage = Storage()
        storage.deleted = Array(self.deleted.values)
        storage.edits = self.edits.map { EditEntry(key: $0.key, versions: $0.value) }
        storage.notes = self.notes.map { NoteEntry(key: $0.key, text: $0.value) }
        storage.profiles = self.profiles.map { ProfileEntry(peerId: $0.key, changes: $0.value) }
        self.lock.unlock()
        if let data = try? JSONEncoder().encode(storage) {
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}
