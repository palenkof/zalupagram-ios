import Foundation
import TelegramPresentationData

// ZalupaGram fork: message details, the same as in ZalupaGram Desktop:
// exact send and edit time, IDs, where it was forwarded from.
public struct ZalupaGramMessageDetails {
    public var messageId: Int32
    public var chatId: String
    public var date: Int32
    public var editDate: Int32?
    public var forwardFrom: String?
    public var forwardDate: Int32?
    public var forwardMessageId: Int32?

    public init(messageId: Int32, chatId: String, date: Int32, editDate: Int32?, forwardFrom: String?, forwardDate: Int32?, forwardMessageId: Int32?) {
        self.messageId = messageId
        self.chatId = chatId
        self.date = date
        self.editDate = editDate
        self.forwardFrom = forwardFrom
        self.forwardDate = forwardDate
        self.forwardMessageId = forwardMessageId
    }
}

public func zalupaGramMessageDetailsTitle(strings: PresentationStrings) -> String {
    return ZalupaGram.tr(strings, "Details", "Подробности")
}

public func zalupaGramMessageDetailsText(_ details: ZalupaGramMessageDetails, strings: PresentationStrings) -> String {
    let ru = zalupaGramIsRussian(strings)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: ru ? "ru_RU" : "en_US")
    formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"
    let format: (Int32) -> String = { timestamp in
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }
    var lines: [String] = []
    lines.append((ru ? "Отправлено: " : "Sent: ") + format(details.date))
    if let editDate = details.editDate {
        lines.append((ru ? "Изменено: " : "Edited: ") + format(editDate))
    }
    lines.append((ru ? "ID сообщения: " : "Message ID: ") + "\(details.messageId)")
    lines.append((ru ? "ID чата: " : "Chat ID: ") + details.chatId)
    if let forwardFrom = details.forwardFrom {
        lines.append((ru ? "Переслано от: " : "Forwarded from: ") + forwardFrom)
    }
    if let forwardDate = details.forwardDate {
        lines.append((ru ? "Оригинал отправлен: " : "Original sent: ") + format(forwardDate))
    }
    if let forwardMessageId = details.forwardMessageId {
        lines.append((ru ? "ID оригинала: " : "Original ID: ") + "\(forwardMessageId)")
    }
    return lines.joined(separator: "\n")
}
