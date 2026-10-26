import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import ContextUI
import PromptUI
import ZalupaGramCore

// ZalupaGram fork: local notes on messages, reply templates and
// translation of the input text before sending.

// MARK: Notes

public func zalupaGramNote(context: AccountContext, messageId: EngineMessage.Id) -> String? {
    return ZalupaGramKeeper.forAccount(context.account.peerId.toInt64()).note(zalupaGramKeeperKey(messageId))
}

// «Note» in the message menu, or the note itself when there is one.
public func zalupaGramNoteMenuTitle(strings: PresentationStrings, note: String?) -> String {
    if let note {
        return "📝 " + note
    }
    return ZalupaGram.tr(strings, "Add a note", "Добавить заметку")
}

public func zalupaGramEditNote(context: AccountContext, messageId: EngineMessage.Id, present: @escaping (ViewController) -> Void, completion: @escaping () -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let ru = zalupaGramIsRussian(presentationData.strings)
    let keeper = ZalupaGramKeeper.forAccount(context.account.peerId.toInt64())
    let key = zalupaGramKeeperKey(messageId)
    let controller = promptController(context: context, text: ru ? "Заметка к сообщению" : "Note on the message", titleFont: .bold, subtitle: ru ? "Видна только вам. Пустая заметка удаляется." : "Only you see it. An empty note is removed.", value: keeper.note(key) ?? "", placeholder: ru ? "Заметка" : "Note", characterLimit: 4000, apply: { value in
        guard let value else {
            return
        }
        keeper.setNote(key, value)
        completion()
    })
    present(controller)
}

// MARK: Reply templates

private let templatesKey = "zg_reply_templates"

public enum ZalupaGramTemplates {
    public static var all: [String] {
        return UserDefaults.standard.stringArray(forKey: templatesKey) ?? []
    }

    public static func add(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return
        }
        var values = all
        values.removeAll(where: { $0 == text })
        values.insert(text, at: 0)
        UserDefaults.standard.set(values, forKey: templatesKey)
    }

    public static func remove(_ text: String) {
        var values = all
        values.removeAll(where: { $0 == text })
        UserDefaults.standard.set(values, forKey: templatesKey)
    }
}

public func zalupaGramReplyTemplateTitle(strings: PresentationStrings) -> String {
    return ZalupaGram.tr(strings, "Reply with a template", "Ответить шаблоном")
}

private func templatePreview(_ text: String) -> String {
    let line = text.replacingOccurrences(of: "\n", with: " ")
    if line.count > 60 {
        return String(line.prefix(60)) + "…"
    }
    return line
}

// A menu at the send button opens above it and can't scroll: long lists
// go by pages, the rest behind «More…».
func zalupaGramPagedMenuItems(_ items: [ContextMenuItem], strings: PresentationStrings, pageSize: Int = 5) -> [ContextMenuItem] {
    if items.count <= pageSize + 1 {
        return items
    }
    let rest = Array(items.dropFirst(pageSize))
    var page = Array(items.prefix(pageSize))
    page.append(.separator)
    page.append(.action(ContextMenuActionItem(text: ZalupaGram.tr(strings, "More…", "Ещё…"), icon: { _ in
        return nil
    }, action: { c, _ in
        var next: [ContextMenuItem] = []
        next.append(.action(ContextMenuActionItem(text: strings.Common_Back, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Back"), color: theme.contextMenu.primaryColor)
        }, iconPosition: .left, action: { c, _ in
            c?.popItems()
        })))
        next.append(.separator)
        next.append(contentsOf: zalupaGramPagedMenuItems(rest, strings: strings, pageSize: pageSize))
        c?.pushItems(items: .single(ContextController.Items(content: .list(next))))
    })))
    return page
}

// The list of templates for a context menu, with «Back» on top.
public func zalupaGramTemplateMenuItems(strings: PresentationStrings, back: ((ContextControllerProtocol?) -> Void)?, chosen: @escaping (String, ContextControllerProtocol?) -> Void) -> [ContextMenuItem] {
    var items: [ContextMenuItem] = []
    if let back {
        items.append(.action(ContextMenuActionItem(text: strings.Common_Back, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Back"), color: theme.contextMenu.primaryColor)
        }, iconPosition: .left, action: { c, _ in
            back(c)
        })))
        items.append(.separator)
    }
    var templateItems: [ContextMenuItem] = []
    for text in ZalupaGramTemplates.all {
        templateItems.append(.action(ContextMenuActionItem(text: templatePreview(text), icon: { _ in
            return nil
        }, action: { c, _ in
            chosen(text, c)
        })))
    }
    items.append(contentsOf: zalupaGramPagedMenuItems(templateItems, strings: strings))
    return items
}

// MARK: Templates screen

private final class TemplatesArguments {
    let add: () -> Void
    let remove: (String) -> Void

    init(add: @escaping () -> Void, remove: @escaping (String) -> Void) {
        self.add = add
        self.remove = remove
    }
}

private enum TemplatesEntry: ItemListNodeEntry {
    case add(String)
    case template(Int32, String)
    case info(String)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case .add:
            return 0
        case let .template(index, _):
            return 1 + index
        case .info:
            return Int32.max
        }
    }

    static func ==(lhs: TemplatesEntry, rhs: TemplatesEntry) -> Bool {
        switch lhs {
        case let .add(text):
            if case .add(text) = rhs {
                return true
            }
            return false
        case let .template(index, text):
            if case .template(index, text) = rhs {
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

    static func <(lhs: TemplatesEntry, rhs: TemplatesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! TemplatesArguments
        switch self {
        case let .add(text):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.add()
            })
        case let .template(_, text):
            return ItemListTextWithLabelItem(presentationData: presentationData, label: "", text: text, style: .blocks, enabledEntityTypes: [], multiline: true, sectionId: self.section, action: {
                arguments.remove(text)
            })
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func zalupaGramTemplatesController(context: AccountContext) -> ViewController {
    let updated = ValuePromise<Int>(0, ignoreRepeated: false)
    var counter = 0
    let reload: () -> Void = {
        counter += 1
        updated.set(counter)
    }
    var presentControllerImpl: ((ViewController) -> Void)?

    let arguments = TemplatesArguments(add: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let ru = zalupaGramIsRussian(presentationData.strings)
        presentControllerImpl?(promptController(context: context, text: ru ? "Новый шаблон" : "New template", titleFont: .bold, value: "", placeholder: ru ? "Текст ответа" : "Reply text", characterLimit: 4096, apply: { value in
            if let value {
                ZalupaGramTemplates.add(value)
                reload()
            }
        }))
    }, remove: { text in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let ru = zalupaGramIsRussian(presentationData.strings)
        presentControllerImpl?(textAlertController(context: context, title: nil, text: ru ? "Удалить шаблон?" : "Delete the template?", actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: presentationData.strings.Common_Delete, action: {
                ZalupaGramTemplates.remove(text)
                reload()
            })
        ]))
    })

    let signal = combineLatest(context.sharedContext.presentationData, updated.get())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let ru = zalupaGramIsRussian(presentationData.strings)
        var entries: [TemplatesEntry] = []
        entries.append(.add(ru ? "➕ Добавить шаблон" : "➕ Add a template"))
        for (index, text) in ZalupaGramTemplates.all.enumerated() {
            entries.append(.template(Int32(index), text))
        }
        entries.append(.info(ru ? "Шаблон вставляется в поле ввода: меню сообщения → «Ответить шаблоном» или зажатая кнопка отправки → «Шаблоны». Нажмите на шаблон, чтобы удалить его." : "A template goes to the input field: message menu → «Reply with a template» or hold the send button → «Templates». Tap a template to delete it."))
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ru ? "Шаблоны ответов" : "Reply templates"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, emptyStateItem: nil, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}

// MARK: Send menu: templates and translation

// The send button menu fills these for text messages, nil otherwise.
public enum ZalupaGramSendMenuExtra {
    public static var saveTemplate: (() -> Void)?
    public static var openTemplates: (() -> Void)?
    public static var translate: (() -> Void)?
}

private let translateLanguageKey = "zg_send_translate_language"

private let translateLanguages: [(code: String, english: String, russian: String)] = [
    ("en", "🇬🇧 English", "🇬🇧 Английский"),
    ("ru", "🇷🇺 Russian", "🇷🇺 Русский"),
    ("uk", "🇺🇦 Ukrainian", "🇺🇦 Украинский"),
    ("de", "🇩🇪 German", "🇩🇪 Немецкий"),
    ("fr", "🇫🇷 French", "🇫🇷 Французский"),
    ("es", "🇪🇸 Spanish", "🇪🇸 Испанский"),
    ("it", "🇮🇹 Italian", "🇮🇹 Итальянский"),
    ("pl", "🇵🇱 Polish", "🇵🇱 Польский"),
    ("tr", "🇹🇷 Turkish", "🇹🇷 Турецкий"),
    ("zh-CN", "🇨🇳 Chinese", "🇨🇳 Китайский"),
    ("ja", "🇯🇵 Japanese", "🇯🇵 Японский"),
    ("ar", "🇸🇦 Arabic", "🇸🇦 Арабский"),
]

// Languages for the translation of the input text, the last used first.
public func zalupaGramTranslateMenuItems(strings: PresentationStrings, chosen: @escaping (String) -> Void) -> [ContextMenuItem] {
    let ru = zalupaGramIsRussian(strings)
    var languages = translateLanguages
    if let last = UserDefaults.standard.string(forKey: translateLanguageKey), let index = languages.firstIndex(where: { $0.code == last }) {
        languages.insert(languages.remove(at: index), at: 0)
    }
    var items: [ContextMenuItem] = []
    for language in languages {
        items.append(.action(ContextMenuActionItem(text: ru ? language.russian : language.english, icon: { _ in
            return nil
        }, action: { c, _ in
            UserDefaults.standard.set(language.code, forKey: translateLanguageKey)
            c?.dismiss(completion: nil)
            chosen(language.code)
        })))
    }
    return zalupaGramPagedMenuItems(items, strings: strings)
}

// Translates through Google, the result comes on the main queue.
public func zalupaGramTranslateInput(_ text: String, to language: String, completion: @escaping (String?) -> Void) {
    ZalupaGramTranslate.translate(text, to: language, completion: { result in
        Queue.mainQueue().async {
            completion(result)
        }
    })
}

public func zalupaGramTemplateSavedText(strings: PresentationStrings) -> String {
    return ZalupaGram.tr(strings, "Saved to reply templates", "Сохранено в шаблоны ответов")
}

public func zalupaGramTranslateFailedText(strings: PresentationStrings) -> String {
    return ZalupaGram.tr(strings, "Couldn't translate, check the connection", "Не удалось перевести, проверьте соединение")
}
