import Foundation

// ZalupaGram fork options, kept in UserDefaults so the upstream settings
// storage stays untouched. TelegramCore reads them, so this module has no
// dependencies. Peers are kept as PeerId.toInt64() values.
public enum ZalupaGramCore {
    public enum Option: String, CaseIterable {
        case ghostRead = "zg_ghost_read" // Don't send read receipts.
        case ghostOnline = "zg_ghost_online" // Always appear offline.
        case ghostTyping = "zg_ghost_typing" // Don't send "typing...".
        case timeWithSeconds = "zg_time_with_seconds" // 14:05:37 in messages.

        var defaultValue: Bool {
            switch self {
            case .timeWithSeconds:
                return true
            default:
                return false
            }
        }
    }

    private static let ghostExceptionsKey = "zg_ghost_exceptions"

    public static func option(_ option: Option) -> Bool {
        if UserDefaults.standard.object(forKey: option.rawValue) == nil {
            return option.defaultValue
        }
        return UserDefaults.standard.bool(forKey: option.rawValue)
    }

    public static func setOption(_ option: Option, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: option.rawValue)
    }

    // Chats where ghost mode is off: messages are read and typing is shown
    // as usual. The list is shared by all accounts.
    public static var ghostExceptions: Set<Int64> {
        let values = UserDefaults.standard.stringArray(forKey: ghostExceptionsKey) ?? []
        return Set(values.compactMap { Int64($0) })
    }

    public static func isGhostException(peerId: Int64) -> Bool {
        return ghostExceptions.contains(peerId)
    }

    public static func setGhostException(peerId: Int64, _ except: Bool) {
        var values = ghostExceptions
        if except {
            values.insert(peerId)
        } else {
            values.remove(peerId)
        }
        UserDefaults.standard.set(values.map { String($0) }, forKey: ghostExceptionsKey)
    }

    public static func clearGhostExceptions() {
        UserDefaults.standard.removeObject(forKey: ghostExceptionsKey)
    }

    // Ghost options with the chat exceptions applied.
    public static func ghostRead(peerId: Int64) -> Bool {
        return option(.ghostRead) && !isGhostException(peerId: peerId)
    }

    public static func ghostTyping(peerId: Int64) -> Bool {
        return option(.ghostTyping) && !isGhostException(peerId: peerId)
    }

    public static var ghostOnline: Bool {
        return option(.ghostOnline)
    }
}
