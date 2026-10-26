import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import AppBundle
import ContextUI

// ZalupaGram fork: "Animate the phrase". The phrase is sent as the first
// frame of a template, then the message is edited once a frame, like bots
// do, and stops at the phrase itself. Works for the recipient in any client.

// Set by the chat while the send button menu is open: animates the text
// that is in the input field.
public enum ZalupaGramSendMenu {
    public static var animate: (() -> Void)?
}

public enum ZalupaGramAnimationStartResult {
    case started(duration: Double)
    case tooManyRunning
    case emptyPhrase
}

// Telegram limits edits of one message: about one a second is safe,
// faster gives FLOOD_WAIT and the edits are blocked for a while.
private let minFrameDelay: Double = 1.0
private let maxFrameDelay: Double = 3.0
private let defaultFrameDelay: Double = 1.5
private let frameDelayOptions: [Double] = [1.0, 1.2, 1.5, 2.0, 2.5, 3.0]
private let sendTimeout: Double = 30.0
private let maxRunning = 3

private let delayKey = "zg_animation_delay"
private let pinsKey = "zg_animation_pins"

func zalupaGramIsRussian(_ strings: PresentationStrings) -> Bool {
    return strings.baseLanguageCode == "ru" || strings.primaryComponent.languageCode == "ru"
}

public var zalupaGramAnimationFrameDelay: Double {
    get {
        let value = UserDefaults.standard.double(forKey: delayKey)
        if value <= 0.0 {
            return defaultFrameDelay
        }
        return max(minFrameDelay, min(maxFrameDelay, value))
    }
    set {
        UserDefaults.standard.set(max(minFrameDelay, min(maxFrameDelay, newValue)), forKey: delayKey)
    }
}

private var animationPins: [String] {
    get {
        return UserDefaults.standard.stringArray(forKey: pinsKey) ?? []
    }
    set {
        UserDefaults.standard.set(newValue, forKey: pinsKey)
    }
}

private func togglePin(_ id: String) {
    var pins = animationPins
    if let index = pins.firstIndex(of: id) {
        pins.remove(at: index)
    } else {
        pins.append(id)
    }
    animationPins = pins
}

func formatSeconds(_ value: Double, ru: Bool) -> String {
    var text = String(format: "%.1f", value)
    if text.hasSuffix(".0") {
        text.removeLast(2)
    }
    if ru {
        text = text.replacingOccurrences(of: ".", with: ",")
    }
    return text + (ru ? " с" : " s")
}

private func durationText(_ duration: Double, ru: Bool) -> String {
    return "\(Int(duration.rounded(.up)))" + (ru ? " с" : " s")
}

private func animationDuration(framesCount: Int) -> Double {
    return Double(max(framesCount - 1, 0)) * zalupaGramAnimationFrameDelay
}

private final class ZalupaGramAnimation {
    private let context: AccountContext
    private let peerId: EnginePeer.Id
    private let frames: [(String, [MessageTextEntity])]
    private let delay: Double
    private let correlationId = Int64.random(in: Int64.min ... Int64.max)
    private let onFinish: (ZalupaGramAnimation) -> Void

    private var index = 0
    private var messageId: EngineMessage.Id?
    private var timer: SwiftSignalKit.Timer?
    private var sentTimer: SwiftSignalKit.Timer?
    private let editDisposable = MetaDisposable()
    private(set) var finished = false

    init(context: AccountContext, peerId: EnginePeer.Id, frames: [(String, [MessageTextEntity])], onFinish: @escaping (ZalupaGramAnimation) -> Void) {
        self.context = context
        self.peerId = peerId
        self.frames = frames
        self.delay = zalupaGramAnimationFrameDelay
        self.onFinish = onFinish
    }

    deinit {
        self.editDisposable.dispose()
        self.timer?.invalidate()
        self.sentTimer?.invalidate()
    }

    func start(threadId: Int64?, replyTo: EngineMessageReplySubject?) {
        // The first frame gets its cloud id when the server accepts it, the
        // pending message manager remembers it by the correlation id.
        let pendingMessageManager = self.context.account.pendingMessageManager!
        let correlationId = self.correlationId
        let sentTimer = SwiftSignalKit.Timer(timeout: 0.3, repeat: true, completion: { [weak self] in
            guard let self, self.messageId == nil, !self.finished else {
                return
            }
            if let id = pendingMessageManager.synchronouslyLookupCorrelationId(correlationId: correlationId) {
                self.sent(id)
            }
        }, queue: Queue.mainQueue())
        self.sentTimer = sentTimer
        sentTimer.start()

        let first = self.frames[0]
        var attributes: [EngineMessage.Attribute] = []
        if !first.1.isEmpty {
            attributes.append(TextEntitiesMessageAttribute(entities: first.1))
        }
        let message: EnqueueMessage = .message(text: first.0, attributes: attributes, inlineStickers: [:], mediaReference: nil, threadId: threadId, replyToMessageId: replyTo, replyToStoryId: nil, localGroupingKey: nil, correlationId: correlationId, bubbleUpEmojiOrStickersets: [])
        let _ = enqueueMessages(account: self.context.account, peerId: self.peerId, messages: [message]).start()
        Logger.shared.log("ZalupaGram", "animation: first of \(self.frames.count) frames enqueued in \(self.peerId)")

        // Nothing was sent, for example writing is not allowed in the chat.
        self.schedule(after: sendTimeout)
    }

    private func schedule(after timeout: Double) {
        self.timer?.invalidate()
        let timer = SwiftSignalKit.Timer(timeout: timeout, repeat: false, completion: { [weak self] in
            self?.editNext()
        }, queue: Queue.mainQueue())
        self.timer = timer
        timer.start()
    }

    private func sent(_ id: EngineMessage.Id) {
        Logger.shared.log("ZalupaGram", "animation: sent as \(id)")
        self.messageId = id
        self.sentTimer?.invalidate()
        self.sentTimer = nil
        self.index = 0
        self.schedule(after: self.delay)
    }

    private func editNext() {
        guard let messageId = self.messageId else {
            self.finish()
            return
        }
        self.index += 1
        if self.index >= self.frames.count {
            self.finish()
            return
        }
        let frame = self.frames[self.index]
        let last = self.index == self.frames.count - 1
        let context = self.context

        self.editDisposable.set((context.engine.data.get(TelegramEngine.EngineData.Item.Messages.Message(id: messageId))
        |> castError(RequestEditMessageError.self)
        |> mapToSignal { message -> Signal<RequestEditMessageResult?, RequestEditMessageError> in
            guard message != nil else {
                // Deleted while animating.
                return .single(nil)
            }
            return context.engine.messages.requestEditMessage(messageId: messageId, text: frame.0, media: .keep, entities: TextEntitiesMessageAttribute(entities: frame.1), richText: nil, inlineStickers: [:], disableUrlPreview: true)
            |> map(Optional.init)
        }
        |> deliverOnMainQueue).start(next: { [weak self] result in
            guard let self else {
                return
            }
            guard let result else {
                Logger.shared.log("ZalupaGram", "animation: message \(messageId) is gone")
                self.finish()
                return
            }
            if case .done = result {
                if last {
                    self.finish()
                } else {
                    self.schedule(after: self.delay)
                }
            }
        }, error: { [weak self] error in
            guard let self else {
                return
            }
            Logger.shared.log("ZalupaGram", "animation: edit \(self.index) of \(messageId) failed: \(error)")
            if last {
                self.finish()
            } else {
                // Most likely FLOOD_WAIT: wait a bit and jump right to the phrase.
                self.index = self.frames.count - 2
                self.schedule(after: 5.0)
            }
        }))
    }

    private func finish() {
        if self.finished {
            return
        }
        self.finished = true
        Logger.shared.log("ZalupaGram", "animation: finished at frame \(self.index) of \(self.frames.count), id \(String(describing: self.messageId))")
        self.timer?.invalidate()
        self.timer = nil
        self.sentTimer?.invalidate()
        self.sentTimer = nil
        self.onFinish(self)
    }
}

private var runningAnimations: [ZalupaGramAnimation] = []

public func zalupaGramStartAnimation(context: AccountContext, peerId: EnginePeer.Id, threadId: Int64?, replyTo: EngineMessageReplySubject?, phrase: String, entities: [MessageTextEntity], templateIndex: Int, strings: PresentationStrings) -> ZalupaGramAnimationStartResult {
    let templates = zalupaGramAnimationTemplates(ru: zalupaGramIsRussian(strings))
    guard templateIndex >= 0 && templateIndex < templates.count else {
        return .emptyPhrase
    }
    if phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return .emptyPhrase
    }
    if runningAnimations.filter({ !$0.finished }).count >= maxRunning {
        return .tooManyRunning
    }
    let chosen = templates[templateIndex]
    var frames: [(String, [MessageTextEntity])] = chosen.frames(phrase).map { zalupaGramParseAnimationFrame($0) }
    frames.append(zalupaGramParseAnimationFrame(chosen.last(), phrase: phrase, phraseEntities: entities))
    let duration = animationDuration(framesCount: frames.count)

    let animation = ZalupaGramAnimation(context: context, peerId: peerId, frames: frames, onFinish: { animation in
        runningAnimations.removeAll(where: { $0 === animation })
    })
    runningAnimations.append(animation)
    animation.start(threadId: threadId, replyTo: replyTo)
    return .started(duration: duration)
}

public func zalupaGramAnimationStartedText(duration: Double, strings: PresentationStrings) -> String {
    let ru = zalupaGramIsRussian(strings)
    let value = durationText(duration, ru: ru)
    return ru ? "Анимация займёт около \(value), потом сообщение останется как есть." : "The animation takes about \(value), then the message stays as is."
}

public func zalupaGramAnimationTooManyText(strings: PresentationStrings) -> String {
    return zalupaGramIsRussian(strings) ? "Подождите, пока закончатся предыдущие анимации." : "Wait for the previous animations to finish."
}

private func emojiIcon(_ emoji: String) -> UIImage? {
    return generateImage(CGSize(width: 24.0, height: 24.0), rotatedContext: { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))
        UIGraphicsPushContext(context)
        let string = NSAttributedString(string: emoji, attributes: [.font: UIFont.systemFont(ofSize: 19.0)])
        let bounds = string.boundingRect(with: size, options: .usesLineFragmentOrigin, context: nil)
        string.draw(at: CGPoint(x: floor((size.width - bounds.width) / 2.0), y: floor((size.height - bounds.height) / 2.0)))
        UIGraphicsPopContext()
    })
}

private func categoryParts(_ category: ZalupaGramAnimationCategory, ru: Bool) -> (String, String) {
    let title = zalupaGramAnimationCategoryTitle(category, ru: ru)
    guard let space = title.firstIndex(of: " ") else {
        return ("", title)
    }
    return (String(title[..<space]), String(title[title.index(after: space)...]))
}

// The menu at the send button: pinned templates first, then categories that
// open as submenus, then pins and the time per frame.
public func zalupaGramAnimationMenuItems(presentationData: PresentationData, phrase: String, chosen: @escaping (Int) -> Void) -> [ContextMenuItem] {
    let ru = zalupaGramIsRussian(presentationData.strings)
    let templates = zalupaGramAnimationTemplates(ru: ru)
    let strings = presentationData.strings

    let backItem: (@escaping (ContextControllerProtocol?) -> Void) -> ContextMenuItem = { back in
        return .action(ContextMenuActionItem(text: strings.Common_Back, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Back"), color: theme.contextMenu.primaryColor)
        }, iconPosition: .left, action: { c, _ in
            back(c)
        }))
    }
    let templateItem: (Int) -> ContextMenuItem = { index in
        let item = templates[index]
        // Some templates depend on the phrase length.
        let duration = durationText(animationDuration(framesCount: item.frames(phrase).count + 1), ru: ru)
        return .action(ContextMenuActionItem(text: item.title, textLayout: .secondLineWithValue(duration), icon: { _ in
            return emojiIcon(item.icon)
        }, action: { c, _ in
            c?.dismiss(completion: {
                chosen(index)
            })
        }))
    }

    func mainItems() -> [ContextMenuItem] {
        var items: [ContextMenuItem] = []
        let pins = animationPins
        for id in pins {
            if let index = templates.firstIndex(where: { $0.id == id }) {
                items.append(templateItem(index))
            }
        }
        if !items.isEmpty {
            items.append(.separator)
        }
        for category in ZalupaGramAnimationCategory.allCases {
            let (emoji, title) = categoryParts(category, ru: ru)
            items.append(.action(ContextMenuActionItem(text: title, icon: { _ in
                return emojiIcon(emoji)
            }, action: { c, _ in
                var subItems: [ContextMenuItem] = [backItem({ c in
                    c?.popItems()
                }), .separator]
                for index in 0 ..< templates.count where templates[index].category == category {
                    subItems.append(templateItem(index))
                }
                c?.pushItems(items: .single(ContextController.Items(content: .list(subItems))))
            })))
        }
        items.append(.separator)
        items.append(.action(ContextMenuActionItem(text: ru ? "Закрепить наверху" : "Pin to the top", icon: { _ in
            return emojiIcon("📌")
        }, action: { c, _ in
            c?.setItems(.single(ContextController.Items(content: .list(pinItems()))), minHeight: nil, animated: true)
        })))
        items.append(.action(ContextMenuActionItem(text: ru ? "Время на кадр" : "Time per frame", textLayout: .secondLineWithValue(formatSeconds(zalupaGramAnimationFrameDelay, ru: ru)), icon: { _ in
            return emojiIcon("⏱")
        }, action: { c, _ in
            c?.setItems(.single(ContextController.Items(content: .list(delayItems()))), minHeight: nil, animated: true)
        })))
        return items
    }

    func pinItems() -> [ContextMenuItem] {
        var items: [ContextMenuItem] = [backItem({ c in
            c?.setItems(.single(ContextController.Items(content: .list(mainItems()))), minHeight: nil, animated: true)
        }), .separator]
        let pins = animationPins
        for item in templates {
            let id = item.id
            let isPinned = pins.contains(id)
            items.append(.action(ContextMenuActionItem(text: item.icon + "  " + item.title, icon: { theme in
                return isPinned ? generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Check"), color: theme.contextMenu.primaryColor) : nil
            }, action: { c, _ in
                togglePin(id)
                c?.setItems(.single(ContextController.Items(content: .list(pinItems()))), minHeight: nil, animated: false)
            })))
        }
        return items
    }

    func delayItems() -> [ContextMenuItem] {
        var items: [ContextMenuItem] = [backItem({ c in
            c?.setItems(.single(ContextController.Items(content: .list(mainItems()))), minHeight: nil, animated: true)
        }), .separator]
        let current = zalupaGramAnimationFrameDelay
        for value in frameDelayOptions {
            let isCurrent = abs(value - current) < 0.05
            items.append(.action(ContextMenuActionItem(text: formatSeconds(value, ru: ru), icon: { theme in
                return isCurrent ? generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Check"), color: theme.contextMenu.primaryColor) : nil
            }, action: { c, _ in
                zalupaGramAnimationFrameDelay = value
                c?.setItems(.single(ContextController.Items(content: .list(mainItems()))), minHeight: nil, animated: true)
            })))
        }
        return items
    }

    return mainItems()
}

func presentFrameDelayPicker(presentationData: PresentationData, present: @escaping (ViewController) -> Void, done: @escaping () -> Void) {
    let ru = zalupaGramIsRussian(presentationData.strings)
    let actionSheet = ActionSheetController(presentationData: presentationData)
    var items: [ActionSheetItem] = []
    items.append(ActionSheetTextItem(title: ru ? "Кадров столько же, меняется только длительность" : "The frames stay the same, only the duration changes"))
    let current = zalupaGramAnimationFrameDelay
    for value in frameDelayOptions {
        let mark = abs(value - current) < 0.05 ? "✅ " : ""
        items.append(ActionSheetButtonItem(title: mark + formatSeconds(value, ru: ru), action: { [weak actionSheet] in
            actionSheet?.dismissAnimated()
            zalupaGramAnimationFrameDelay = value
            done()
        }))
    }
    actionSheet.setItemGroups([
        ActionSheetItemGroup(items: items),
        ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])
    ])
    present(actionSheet)
}
