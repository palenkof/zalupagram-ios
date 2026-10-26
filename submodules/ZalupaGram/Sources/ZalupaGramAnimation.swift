import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext

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
    private let deliveredDisposable = MetaDisposable()
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
        self.deliveredDisposable.dispose()
        self.editDisposable.dispose()
        self.timer?.invalidate()
    }

    func start(threadId: Int64?, replyTo: EngineMessageReplySubject?) {
        let pendingMessageManager = self.context.account.pendingMessageManager!
        let correlationId = self.correlationId
        self.deliveredDisposable.set((pendingMessageManager.deliveredMessageEvents(peerId: self.peerId)
        |> deliverOnMainQueue).start(next: { [weak self] events in
            guard let self, self.messageId == nil, !self.finished else {
                return
            }
            if let id = pendingMessageManager.synchronouslyLookupCorrelationId(correlationId: correlationId), events.contains(where: { $0.id == id }) {
                self.sent(id)
            }
        }))

        let first = self.frames[0]
        var attributes: [EngineMessage.Attribute] = []
        if !first.1.isEmpty {
            attributes.append(TextEntitiesMessageAttribute(entities: first.1))
        }
        let message: EnqueueMessage = .message(text: first.0, attributes: attributes, inlineStickers: [:], mediaReference: nil, threadId: threadId, replyToMessageId: replyTo, replyToStoryId: nil, localGroupingKey: nil, correlationId: correlationId, bubbleUpEmojiOrStickersets: [])
        let _ = enqueueMessages(account: self.context.account, peerId: self.peerId, messages: [message]).start()

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
        self.messageId = id
        self.deliveredDisposable.set(nil)
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
        }, error: { [weak self] _ in
            guard let self else {
                return
            }
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
        self.timer?.invalidate()
        self.timer = nil
        self.deliveredDisposable.set(nil)
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

// The list of templates with their durations, pinned ones first.
public func zalupaGramPresentAnimationPicker(presentationData: PresentationData, phrase: String, present: @escaping (ViewController) -> Void, chosen: @escaping (Int) -> Void) {
    let ru = zalupaGramIsRussian(presentationData.strings)
    let templates = zalupaGramAnimationTemplates(ru: ru)
    let actionSheet = ActionSheetController(presentationData: presentationData)

    let title: (Int) -> String = { index in
        let item = templates[index]
        // Some templates depend on the phrase length.
        let count = item.frames(phrase).count + 1
        return item.icon + "  " + item.title + "  •  " + durationText(animationDuration(framesCount: count), ru: ru)
    }

    var items: [ActionSheetItem] = []
    items.append(ActionSheetTextItem(title: (ru ? "Анимировать фразу" : "Animate the phrase") + " · " + formatSeconds(zalupaGramAnimationFrameDelay, ru: ru) + (ru ? " на кадр" : " per frame")))
    for id in animationPins {
        if let index = templates.firstIndex(where: { $0.id == id }) {
            items.append(ActionSheetButtonItem(title: "📌 " + title(index), action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                chosen(index)
            }))
        }
    }
    for category in ZalupaGramAnimationCategory.allCases {
        items.append(ActionSheetTextItem(title: zalupaGramAnimationCategoryTitle(category, ru: ru)))
        for index in 0 ..< templates.count where templates[index].category == category {
            items.append(ActionSheetButtonItem(title: title(index), action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                chosen(index)
            }))
        }
    }
    items.append(ActionSheetButtonItem(title: ru ? "📌 Закрепить наверху…" : "📌 Pin to the top…", action: { [weak actionSheet] in
        actionSheet?.dismissAnimated()
        presentPinsPicker(presentationData: presentationData, templates: templates, ru: ru, present: present)
    }))
    items.append(ActionSheetButtonItem(title: (ru ? "⏱ Время на кадр: " : "⏱ Time per frame: ") + formatSeconds(zalupaGramAnimationFrameDelay, ru: ru), action: { [weak actionSheet] in
        actionSheet?.dismissAnimated()
        presentFrameDelayPicker(presentationData: presentationData, present: present, done: {
            zalupaGramPresentAnimationPicker(presentationData: presentationData, phrase: phrase, present: present, chosen: chosen)
        })
    }))

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

private func presentPinsPicker(presentationData: PresentationData, templates: [ZalupaGramAnimationTemplate], ru: Bool, present: @escaping (ViewController) -> Void) {
    let actionSheet = ActionSheetController(presentationData: presentationData)
    var items: [ActionSheetItem] = []
    items.append(ActionSheetTextItem(title: ru ? "Закреплённые идут первыми в списке" : "Pinned ones go first in the list"))
    let pins = animationPins
    for item in templates {
        let mark = pins.contains(item.id) ? "✅ " : "▫️ "
        let id = item.id
        items.append(ActionSheetButtonItem(title: mark + item.icon + "  " + item.title, action: { [weak actionSheet] in
            actionSheet?.dismissAnimated()
            togglePin(id)
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
