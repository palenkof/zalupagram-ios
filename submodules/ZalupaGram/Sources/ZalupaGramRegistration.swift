import Foundation
import TelegramPresentationData

// ZalupaGram fork: approximate registration date by the user id, the same as
// in ZalupaGram Desktop (zg_regdate.cpp).
//
// Known (user id, registration date) points, interpolated in between.
// Data: https://github.com/wjclub/telegram-bot-getids (src/ages.json),
// MIT License, Copyright (c) 2019 Jonas Zohren. Dates are made
// non-decreasing to smooth out a few noisy 2015 points.
private let knownPoints: [(userId: Int64, date: Int32)] = [
    (2768409, 1383264000),
    (7679610, 1388448000),
    (11538514, 1391212000),
    (15835244, 1392940000),
    (23646077, 1393459000),
    (38015510, 1393632000),
    (44634663, 1399334000),
    (46145305, 1400198000),
    (54845238, 1411257000),
    (63263518, 1414454000),
    (101260938, 1425600000),
    (101323197, 1426204000),
    (103151531, 1433376000),
    (103258382, 1433376000),
    (109393468, 1439078000),
    (111220210, 1439078000),
    (112594714, 1439683000),
    (116812045, 1439683000),
    (122600695, 1439683000),
    (124872445, 1439856000),
    (125828524, 1444003000),
    (130029930, 1444003000),
    (133909606, 1444176000),
    (143445125, 1448928000),
    (148670295, 1452211000),
    (152079341, 1453420000),
    (157242073, 1453420000),
    (171295414, 1457481000),
    (181783990, 1460246000),
    (222021233, 1465344000),
    (225034354, 1466208000),
    (278941742, 1473465000),
    (285253072, 1476835000),
    (294851037, 1479600000),
    (297621225, 1481846000),
    (328594461, 1482969000),
    (337808429, 1487707000),
    (341546272, 1487782000),
    (352940995, 1487894000),
    (369669043, 1490918000),
    (400169472, 1501459000),
    (805158066, 1563208000),
    (1974255900, 1634000000),
    (5795034000, 1662076800),
    (6227468000, 1679270400),
    (7583599300, 1739664000),
    (7947063900, 1754092800),
    (8235679900, 1758758400),
]

private enum RegistrationBound {
    case before
    case around
    case after
}

private func estimateRegistration(userId: Int64) -> (Int32, RegistrationBound)? {
    guard userId > 0, let first = knownPoints.first, let last = knownPoints.last else {
        return nil
    }
    if userId <= first.userId {
        return (first.date, .before)
    } else if userId >= last.userId {
        return (last.date, .after)
    }
    guard let upperIndex = knownPoints.firstIndex(where: { $0.userId >= userId }), upperIndex > 0 else {
        return nil
    }
    let lower = knownPoints[upperIndex - 1]
    let upper = knownPoints[upperIndex]
    let ratio = Double(userId - lower.userId) / Double(upper.userId - lower.userId)
    let date = lower.date + Int32(ratio * Double(upper.date - lower.date))
    return (date, .around)
}

public func zalupaGramRegistrationText(userId: Int64, strings: PresentationStrings) -> String? {
    guard let (date, bound) = estimateRegistration(userId: userId) else {
        return nil
    }
    let ru = zalupaGramIsRussian(strings)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: ru ? "ru_RU" : "en_US")
    let value = Date(timeIntervalSince1970: TimeInterval(date))
    switch bound {
    case .before:
        formatter.dateFormat = "MM.yyyy"
        return (ru ? "до " : "before ") + formatter.string(from: value)
    case .after:
        formatter.dateFormat = "MM.yyyy"
        return (ru ? "после " : "after ") + formatter.string(from: value)
    case .around:
        formatter.dateFormat = "LLLL yyyy"
        return "≈ " + formatter.string(from: value)
    }
}

// Peer id the way Bot API shows it: 123, -123 for chats, -100123 for channels.
public func zalupaGramBotApiId(rawId: Int64, isUser: Bool, isChannel: Bool) -> String {
    if isUser {
        return "\(rawId)"
    } else if isChannel {
        return "-100\(rawId)"
    } else {
        return "-\(rawId)"
    }
}
