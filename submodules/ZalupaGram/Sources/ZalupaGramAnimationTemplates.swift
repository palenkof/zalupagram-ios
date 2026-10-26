import Foundation
import TelegramCore

// ZalupaGram fork: templates of the animated phrases, the same as in
// ZalupaGram Desktop (zg_animate_templates.cpp).
//
// Frames are written with a small markup: **bold**, ~~strike~~,
// ||spoiler|| and ```monospace block```. The last frame has
// zalupaGramAnimationPhrase where the phrase goes with its own formatting.

let zalupaGramAnimationPhrase = "\u{1}"

enum ZalupaGramAnimationCategory: CaseIterable {
    case classic
    case hacker
    case media
    case legion
    case other
}

struct ZalupaGramAnimationTemplate {
    let id: String // Stable, used for pinned templates.
    let category: ZalupaGramAnimationCategory
    let icon: String
    let title: String
    // Frames before the last one, the phrase is put in as plain text.
    let frames: (String) -> [String]
    // The last frame, with zalupaGramAnimationPhrase.
    let last: () -> String
}

func zalupaGramAnimationCategoryTitle(_ category: ZalupaGramAnimationCategory, ru: Bool) -> String {
    switch category {
    case .classic:
        return ru ? "⏳ Классика" : "⏳ Classic"
    case .hacker:
        return ru ? "💻 Хакерское" : "💻 Hacker"
    case .media:
        return ru ? "📰 Медиа" : "📰 Media"
    case .legion:
        return ru ? "🎖 Легион" : "🎖 Legion"
    case .other:
        return ru ? "🎲 Другое" : "🎲 Other"
    }
}

private func bar(_ percent: Int, width: Int = 10) -> String {
    let filled = (percent * width + 50) / 100
    return String(repeating: "\u{25B0}", count: filled) + String(repeating: "\u{25B1}", count: width - filled) + " \(percent)%"
}

private func today() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "dd.MM.yyyy"
    return formatter.string(from: Date())
}

// Up to 7 steps of the phrase appearing, by words or by letters.
private func typewriter(_ phrase: String) -> [String] {
    let characters = Array(phrase)
    var cuts: [Int] = []
    if characters.count > 1 {
        for i in 1 ..< characters.count {
            if characters[i] == " " && characters[i - 1] != " " {
                cuts.append(i)
            }
        }
        if cuts.count < 3 {
            cuts = Array(1 ..< characters.count)
        }
    }
    let steps = 7
    var result: [String] = ["▌"]
    if cuts.isEmpty {
        return result
    }
    let count = min(cuts.count, steps)
    for i in 1 ... count {
        let cut = cuts[(i * cuts.count) / (count + 1)]
        let frame = String(characters[0 ..< cut]) + "▌"
        if !result.contains(frame) {
            result.append(frame)
        }
    }
    return result
}

// Each next frame adds one more part to the previous one.
private func grow(_ text: String, _ parts: [String]) -> [String] {
    var text = text
    var result: [String] = []
    for part in parts {
        text += part
        result.append(text)
    }
    return result
}

func zalupaGramAnimationTemplates(ru: Bool) -> [ZalupaGramAnimationTemplate] {
    let t: (String, String) -> String = { english, russian in
        return ru ? russian : english
    }
    let P = zalupaGramAnimationPhrase
    var result: [ZalupaGramAnimationTemplate] = []
    let add: (String, ZalupaGramAnimationCategory, String, String, @escaping (String) -> [String], @escaping () -> String) -> Void = { id, category, icon, title, frames, last in
        result.append(ZalupaGramAnimationTemplate(id: id, category: category, icon: icon, title: title, frames: frames, last: last))
    }

    // Classic.

    add("loading", .classic, "⏳", t("Loading", "Загрузка"), { _ in
        let title = t("⏳ Loading a thought...\n", "⏳ Загружаю мысль…\n")
        return [
            title + bar(0),
            title + bar(17),
            title + bar(46),
            title + bar(83),
            title + bar(99),
            title + bar(99) + t("\nabout 3 years left", "\nосталось примерно 3 года"),
            title + bar(99) + t("\nlooking for drivers...", "\nищу драйвера…"),
            title + bar(100),
        ]
    }, {
        return "✅ " + P
    })

    add("typing", .classic, "⌨️", t("Typing", "Печатает"), typewriter, {
        return P
    })

    // Hacker.

    add("pentagon", .hacker, "💻", t("Hacking the Pentagon", "Взлом Пентагона"), { _ in
        return [
            t("💻 Connecting to the Pentagon...", "💻 Подключаюсь к Пентагону…"),
            t("🔓 Bypassing the firewall... █▒▒▒▒", "🔓 Обхожу защиту… █▒▒▒▒"),
            t("🔓 Bypassing the firewall... ███▒▒", "🔓 Обхожу защиту… ███▒▒"),
            t("📡 Decrypting top secret data...", "📡 Расшифровываю секретные данные…"),
            t("⚠️ **ACCESS GRANTED**", "⚠️ **ДОСТУП ПОЛУЧЕН**"),
        ]
    }, {
        return t("📂 **Top secret:**\n", "📂 **Совершенно секретно:**\n") + P
    })

    // Media.

    add("news", .media, "📢", t("Breaking news", "Срочные новости"), { _ in
        return [
            t("🔴 **LIVE**", "🔴 **ПРЯМОЙ ЭФИР**"),
            t("🚨 **BREAKING** 🚨", "🚨 **СРОЧНО** 🚨"),
            t("📢 **ATTENTION, AN IMPORTANT STATEMENT**", "📢 **ВНИМАНИЕ, ВАЖНОЕ ЗАЯВЛЕНИЕ**"),
            t("📢 Sources report...", "📢 Источники сообщают…"),
        ]
    }, {
        return "📰 " + P
    })

    let duma: (String) -> String = { phrase in
        return t("⚡️**«", "⚡️**«") + phrase + t("», the State Duma said.**", "», — заявили в Госдуме.**")
    }
    let dumaBody: () -> [String] = {
        return [
            t("\n\nThe statement was made today at a plenary session.", "\n\nСоответствующее заявление прозвучало сегодня на пленарном заседании."),
            t(" The initiative was backed by **412 deputies**, none against, one abstained.", " Инициативу поддержали **412 депутатов**, против — 0, воздержался 1."),
            t("\n\nThe Kremlin has not commented yet.", "\n\nВ Кремле заявление пока не комментируют."),
        ]
    }
    add("topor", .media, "⚡️", t("Topor Live post", "Пост «Топор Live»"), { phrase in
        let breaking = t("⚡️**The State Duma made an urgent statement**", "⚡️**В Госдуме сделали срочное заявление**")
        var result: [String] = [
            "⚡️",
            t("⚡️**Breaking**", "⚡️**Срочно**"),
            breaking,
            breaking + t("\n\nDetails are being clarified.", "\n\nПодробности уточняются."),
        ]
        let head = duma(phrase)
        result.append(head)
        result.append(contentsOf: grow(head, dumaBody()))
        return result
    }, {
        return duma(P) + dumaBody().joined() + t("\n\n👉 Topor Live. Subscribe", "\n\n👉 Топор Live. Подписаться")
    })

    let infobizHead: () -> String = {
        return t("🔥 **HOW I MADE 1 000 000 ₽ IN A WEEK** 🔥", "🔥 **КАК Я ЗАРАБОТАЛ 1 000 000 ₽ ЗА НЕДЕЛЮ** 🔥")
    }
    let infobizList: () -> [String] = {
        return [
            t("\n✅ no investments", "\n✅ без вложений"),
            t("\n✅ no experience", "\n✅ без опыта"),
            t("\n✅ lying on the couch 🛋", "\n✅ лёжа на диване 🛋"),
        ]
    }
    add("infobiz", .media, "🔥", t("Info gypsy", "Инфоцыган"), { _ in
        let head = infobizHead()
        var result: [String] = [
            "🔥",
            "🔥🔥",
            "🔥🔥🔥",
            t("🔥 **HOW I MADE**", "🔥 **КАК Я ЗАРАБОТАЛ**"),
            t("🔥 **HOW I MADE 1 000 000 ₽**", "🔥 **КАК Я ЗАРАБОТАЛ 1 000 000 ₽**"),
            head,
        ]
        var list = infobizList()
        list.append(t("\n✅ no registration and SMS", "\n✅ без регистрации и СМС"))
        result.append(contentsOf: grow(head + "\n", list))
        let all = result[result.count - 1]
        let read = all + t("\n\n👇 read till the end 👇", "\n\n👇 читай до конца 👇")
        result.append(read)
        result.append(read + t("\n\n💸 the secret is simple...", "\n\n💸 секрет прост…"))
        result.append(read + t("\n\n💸 the secret is simple...\n🤫 but not everyone is ready to hear it", "\n\n💸 секрет прост…\n🤫 но не все готовы его услышать"))
        return result
    }, {
        return infobizHead() + "\n" + infobizList().joined()
            + t("\n\n💡 **The secret:**\n", "\n\n💡 **Секрет:**\n")
            + P
            + t("\n\n📈 The «Successful success» course: ~~199 990 ₽~~ **99 990 ₽**\n⏳ 3 places left", "\n\n📈 Курс «Успешный успех»: ~~199 990 ₽~~ **99 990 ₽**\n⏳ осталось 3 места")
    })

    // Legion.

    let legionHead: () -> String = {
        return t("🎖 **Dear members of the Legion!**", "🎖 **Уважаемые члены Легиона!**")
    }
    add("legion", .legion, "🎖", t("Emergency Legion meeting", "Срочное собрание Легиона"), { name in
        let head = legionHead()
        let sad = head + t("\n\nUnfortunately, we have sad news. 😔", "\n\nК сожалению, у нас печальные новости. 😔")
        let tests = t("\n\n🧪 Tests: ", "\n\n🧪 Анализы: ")
        let found = head + t("\n\n🩺 The doctors came to the conclusion\nthat **", "\n\n🩺 Врачи пришли к выводу,\nчто у **") + name + t("** has…", "** обнаружен…")
        let expel = head + t("\n\n⛔️ Expelling ", "\n\n⛔️ Исключение ") + name + t(" from the Legion:\n", " из Легиона:\n")
        return [
            "🚨",
            t("🚨 **ATTENTION**", "🚨 **ВНИМАНИЕ**"),
            t("🚨 **ATTENTION, LEGION** 🚨\n\n📢 emergency meeting", "🚨 **ВНИМАНИЕ, ЛЕГИОН** 🚨\n\n📢 экстренное собрание"),
            head,
            sad,
            sad + tests + bar(30),
            sad + tests + bar(70),
            sad + tests + bar(100) + " ✅",
            found,
            found + t("\n\n🦠 **S Y P H I L I S** 🦠", "\n\n🦠 **С И Ф И Л И С** 🦠"),
            expel + bar(40),
            expel + bar(100) + " ✅",
        ]
    }, {
        return legionHead()
            + t("\n\nUnfortunately, the doctors came to the conclusion that **", "\n\nК сожалению, врачи пришли к выводу, что у **")
            + P
            + t("** has **syphilis** 🦠\n\n⛔️ Therefore he must be **expelled from the Legion immediately**.\n\n🫡 Thank you for your attention.\n— Command of the «Legion» PMC", "** обнаружен **сифилис** 🦠\n\n⛔️ Поэтому он должен быть **немедленно исключён из Легиона**.\n\n🫡 Спасибо за внимание.\n— Командование ЧВК «Легион»")
    })

    let order: () -> String = {
        return t("🎓 **POLYTECH** · Dean's office\n\n📄 **ORDER No. 69-O**\nof ", "🎓 **ПОЛИТЕХ** · Деканат\n\n📄 **ПРИКАЗ № 69-О**\nот ")
            + today()
            + t("\non the expulsion of a student", "\nоб отчислении обучающегося")
    }
    let reasons: () -> String = {
        return t("\n\nFor systematically missed classes, 7 academic debts and a suspiciously good mood", "\n\nЗа систематические пропуски пар, 7 академических задолженностей и подозрительно хорошее настроение")
    }
    let rector: () -> String = {
        return t("\n\n🖊 Rector A. I. Rudskoy", "\n\n🖊 Ректор А. И. Рудской")
    }
    add("polytech", .legion, "🎓", t("Expulsion from Polytech", "Отчисление из Политеха"), { name in
        let doc = order()
        let why = doc + reasons()
        let expel = why + t("\n\n**EXPEL:**\n", "\n\n**ОТЧИСЛИТЬ:**\n") + name
        return [
            "🎓",
            t("🎓 **POLYTECH**", "🎓 **ПОЛИТЕХ**"),
            t("🎓 **POLYTECH** · Dean's office", "🎓 **ПОЛИТЕХ** · Деканат"),
            doc,
            doc + t("\n\nFor systematically missed classes…", "\n\nЗа систематические пропуски пар…"),
            why,
            why + t("\n\n**EXPEL:**", "\n\n**ОТЧИСЛИТЬ:**"),
            expel,
            expel + rector() + " ✍️…",
            expel + rector() + " ✍️" + t("\n🔏 Stamping…", "\n🔏 Ставлю печать…"),
            expel + rector() + " ✍️" + t("\n🔏 Stamped ✅", "\n🔏 Печать поставлена ✅"),
        ]
    }, {
        return order() + reasons()
            + t("\n\n**EXPEL:**\n", "\n\n**ОТЧИСЛИТЬ:**\n") + P
            + rector() + " ✍️ · 🔏 " + t("Seal", "М. П.")
            + t("\n🪖 A copy of the order was sent to the military enlistment office", "\n🪖 Копия приказа направлена в военкомат")
    })

    // Other.

    let anonymous: () -> String = {
        return t("🎭 **We are Anonymous.**", "🎭 **Мы — Анонимус.**")
    }
    add("anonymous", .other, "🎭", t("Anonymous", "Анонимус"), { _ in
        var result: [String] = ["🎭"]
        result.append(contentsOf: grow(anonymous(), [
            "",
            t("\nWe are Legion.", "\nМы — легион."),
            t("\nWe do not forgive.", "\nМы не прощаем."),
            t("\nWe do not forget.", "\nМы не забываем."),
            t("\n\nExpect us.", "\n\nЖдите нас."),
        ]))
        result.append(anonymous() + t("\n\n📡 A new message intercepted…", "\n\n📡 Перехвачено новое послание…"))
        return result
    }, {
        return anonymous()
            + t(" We are Legion.", " Мы — легион.")
            + t("\n\n📡 **Our message:**\n", "\n\n📡 **Наше послание:**\n")
            + P
            + t("\n\nExpect us.", "\n\nЖдите нас.")
    })

    let prophecy: () -> String = {
        return t("📜 **The prophecy of Nostradamus**\n1555", "📜 **Пророчество Нострадамуса**\n1555 год")
    }
    add("nostradamus", .other, "📜", t("Nostradamus", "Нострадамус"), { _ in
        var result: [String] = ["📜"]
        result.append(contentsOf: grow(prophecy(), [
            "",
            t("\n\n«And a day shall come…", "\n\n«И придёт день…"),
            t("\nwhen the stars align over the North…", "\nкогда сойдутся звёзды над Севером…"),
            t("\nand the great Polytech falls…", "\nи падёт великий Политех…"),
            t("\nand then he shall say:»", "\nи тогда скажет он:»"),
        ]))
        return result
    }, {
        return prophecy()
            + t("\n\n«…and then he shall say: **", "\n\n«…и тогда скажет он: **")
            + P
            + t("**»\n\n— Century VI, quatrain 69", "**»\n\n— Центурия VI, катрен 69")
    })

    add("ads", .other, "📺", t("Ad break", "Рекламная пауза"), { _ in
        let skip: (Int) -> String = { seconds in
            return t("\n\n⏭ Skip in \(seconds)", "\n\n⏭ Пропустить через \(seconds)")
        }
        let shampoo = t("📺 **Ad**\n\n🧴 «Bull Power» shampoo — for real men 🐂", "📺 **Реклама**\n\n🧴 Шампунь «Бычья мощь» — для настоящих мужиков 🐂")
        let snack = t("📺 **Ad**\n\n🍫 «Breakie» chocolate bar — take a break 😋", "📺 **Реклама**\n\n🍫 Батончик «Перерывчик» — сделай паузу 😋")
        return [
            t("📺 **Ad**", "📺 **Реклама**"),
            shampoo,
            shampoo + skip(5),
            shampoo + skip(4),
            snack + skip(3),
            snack + skip(2),
            snack + skip(1),
            snack + t("\n\n⏭ **Skip the ad**", "\n\n⏭ **Пропустить рекламу**"),
        ]
    }, {
        return t("▶️ **Back to the message:**\n", "▶️ **Возвращаемся к сообщению:**\n") + P
    })

    add("rpg", .other, "🐉", t("Text RPG", "Текстовая RPG"), { _ in
        let dragon = t("🐉 **A dragon appeared!**", "🐉 **Появился дракон!**")
        return [
            t("⚔️ You enter a dark cave…", "⚔️ Вы входите в тёмную пещеру…"),
            t("🔦 It's dark around. Smells like socks.", "🔦 Вокруг темно. Пахнет носками."),
            dragon + "\n❤️ 100/100",
            dragon + t("\n🗡 You attack! 🎲 roll: 1", "\n🗡 Вы атакуете! 🎲 бросок: 1"),
            dragon + t("\n🐉 The dragon laughs", "\n🐉 Дракон смеётся"),
            dragon + t("\n🔥 The dragon breathes fire!\n❤️ 3/100", "\n🔥 Дракон дышит огнём!\n❤️ 3/100"),
            t("💀 **YOU DIED**", "💀 **ВЫ ПОГИБЛИ**"),
        ]
    }, {
        return t("💀 **YOU DIED**\n\nBut before dying you managed to say:\n", "💀 **ВЫ ПОГИБЛИ**\n\nНо перед смертью вы успели сказать:\n")
            + P
            + t("\n\n🔄 Load the save?", "\n\n🔄 Загрузить сохранение?")
    })

    add("icq", .other, "🌼", t("ICQ 2007", "ICQ 2007"), { _ in
        let head = t("🌼 **ICQ** · Online: 3", "🌼 **ICQ** · В сети: 3")
        return [
            t("🌼 *uh-oh!*", "🌼 *о-оу!*"),
            head,
            head + t("\n📟 Status: ✨AnGrY✨", "\n📟 Статус: ✨Зл0й✨"),
            head + t("\n💬 where did u gO??? (((", "\n💬 ты где прОпАл??? ((("),
            head + t("\n💬 where did u gO??? (((\n💬 hello", "\n💬 ты где прОпАл??? (((\n💬 ау"),
            head + t("\n💬 where did u gO??? (((\n💬 hello\n💬 answer plz", "\n💬 ты где прОпАл??? (((\n💬 ау\n💬 ответь пжлст"),
            head + t("\n🎵 now playing: t.A.T.u. — Not Gonna Get Us", "\n🎵 сейчас играет: Тату — Нас не догонят"),
        ]
    }, {
        return "🌼 **ICQ** · 2007\n\n💬 "
            + P
            + t(" ))))\n\n(c) all rights reserved 2007", " ))))\n\n(c) все права защищены 2007")
    })

    let toast: () -> String = {
        return t("🥂 **Dear guests!**", "🥂 **Дорогие гости!**")
    }
    add("toast", .other, "🥂", t("Toastmaster", "Тост тамады"), { _ in
        var result: [String] = ["🥂"]
        result.append(contentsOf: grow(toast(), [
            "",
            t("\nAttention, please!", "\nПрошу внимания!"),
            t("\n\n🎤 The toastmaster checks the mic… *fooo-fooo*", "\n\n🎤 Тамада проверяет микрофон… *фууу-фууу*"),
            t("\n🎵 the accordion is playing", "\n🎵 играет баян"),
        ]))
        let speech = t("🥂 **Let me say a toast!**", "🥂 **Позвольте сказать тост!**")
        result.append(speech)
        result.append(speech + t("\n\nTo the fact that…", "\n\nЗа то, что…"))
        return result
    }, {
        return t("🥂 **Let me say a toast!**\n\nTo the fact that ", "🥂 **Позвольте сказать тост!**\n\nЗа то, что ")
            + P
            + t("!\n\n🍻 **CHEERS!**", "!\n\n🍻 **ГОРЬКО!**")
    })

    return result
}

// The markup to text with entities, the phrase replaces zalupaGramAnimationPhrase.
// Entity ranges are in UTF-16 code units, as Telegram expects.
func zalupaGramParseAnimationFrame(_ markup: String, phrase: String = "", phraseEntities: [MessageTextEntity] = []) -> (String, [MessageTextEntity]) {
    let markers: [(String, MessageTextEntityType)] = [
        ("```", .Pre(language: nil)),
        ("**", .Bold),
        ("~~", .Strikethrough),
        ("||", .Spoiler),
    ]
    var text = ""
    var entities: [MessageTextEntity] = []
    var open: [Int] = Array(repeating: -1, count: markers.count)
    var rest = Substring(markup)
    while !rest.isEmpty {
        var matched = false
        for (index, marker) in markers.enumerated() {
            if !rest.hasPrefix(marker.0) {
                continue
            }
            let position = text.utf16.count
            if open[index] < 0 {
                open[index] = position
            } else {
                let from = open[index]
                if position > from {
                    entities.append(MessageTextEntity(range: from ..< position, type: marker.1))
                }
                open[index] = -1
            }
            rest = rest.dropFirst(marker.0.count)
            matched = true
            break
        }
        if !matched {
            text.append(rest.removeFirst())
        }
    }

    // Put the phrase in with its own formatting.
    if let placeholder = text.range(of: zalupaGramAnimationPhrase) {
        let at = text.utf16.distance(from: text.utf16.startIndex, to: placeholder.lowerBound)
        let delta = phrase.utf16.count - 1
        entities = entities.map { entity in
            let from = entity.range.lowerBound
            let till = entity.range.upperBound
            if from > at {
                return MessageTextEntity(range: (from + delta) ..< (till + delta), type: entity.type)
            } else if till > at {
                return MessageTextEntity(range: from ..< (till + delta), type: entity.type)
            } else {
                return entity
            }
        }
        text.replaceSubrange(placeholder, with: phrase)
        for entity in phraseEntities {
            entities.append(MessageTextEntity(range: (entity.range.lowerBound + at) ..< (entity.range.upperBound + at), type: entity.type))
        }
        entities.sort(by: { $0.range.lowerBound < $1.range.lowerBound })
    }
    return (text, entities)
}
