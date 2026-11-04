import Foundation
import UIKit
import CryptoKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import PresentationDataUtils
import AccountContext
import AppBundle
import ZalupaGramCore
import ZalupaGramSky
import PromptUI

// ZalupaGram fork: chats hidden behind a PIN, the panic link and the
// ZalupaGram theme. Hidden chats are left out of the chat list until the
// PIN is entered and come back hidden when the app goes to the background
// or on zalupagram://panic (a Back Tap shortcut can open it).

public enum ZalupaGramHiddenChats {
    private static let pinKey = "zg_hidden_pin"
    private static let lock = NSLock()
    private static var cache: [Int64: Set<Int64>] = [:]
    private static var isUnlocked = false
    private static var observer: NSObjectProtocol?
    private static let updatesPromise = ValuePromise<Int>(0, ignoreRepeated: false)
    private static var updatesCounter = 0

    // Fires when the list of hidden chats or the lock changes.
    public static var updates: Signal<Int, NoError> {
        return updatesPromise.get()
    }

    private static func key(_ accountPeerId: Int64) -> String {
        return "zg_hidden_chats_\(accountPeerId)"
    }

    private static func notify() {
        Queue.mainQueue().async {
            updatesCounter += 1
            updatesPromise.set(updatesCounter)
        }
    }

    public static func hiddenPeerIds(accountPeerId: Int64) -> Set<Int64> {
        lock.lock()
        defer {
            lock.unlock()
        }
        if let value = cache[accountPeerId] {
            return value
        }
        let value = Set((UserDefaults.standard.stringArray(forKey: key(accountPeerId)) ?? []).compactMap { Int64($0) })
        cache[accountPeerId] = value
        return value
    }

    // True when the chat has to be left out of the chat list now.
    public static func isHidden(accountPeerId: Int64, peerId: Int64) -> Bool {
        lock.lock()
        let unlocked = isUnlocked
        lock.unlock()
        if unlocked {
            return false
        }
        return hiddenPeerIds(accountPeerId: accountPeerId).contains(peerId)
    }

    public static func isMarkedHidden(accountPeerId: Int64, peerId: Int64) -> Bool {
        return hiddenPeerIds(accountPeerId: accountPeerId).contains(peerId)
    }

    public static func setHidden(accountPeerId: Int64, peerId: Int64, _ hidden: Bool) {
        var value = hiddenPeerIds(accountPeerId: accountPeerId)
        if hidden {
            value.insert(peerId)
        } else {
            value.remove(peerId)
        }
        lock.lock()
        cache[accountPeerId] = value
        lock.unlock()
        UserDefaults.standard.set(value.map { String($0) }, forKey: key(accountPeerId))
        notify()
    }

    public static var unlocked: Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        return isUnlocked
    }

    public static func setUnlocked(_ value: Bool) {
        lock.lock()
        isUnlocked = value
        lock.unlock()
        if value && observer == nil {
            observer = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: { _ in
                ZalupaGramHiddenChats.setUnlocked(false)
            })
        }
        notify()
    }

    private static func hash(_ pin: String) -> String {
        let digest = SHA256.hash(data: Data(("zalupagram:" + pin).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static var hasPin: Bool {
        return UserDefaults.standard.string(forKey: pinKey) != nil
    }

    public static func setPin(_ pin: String) {
        UserDefaults.standard.set(hash(pin), forKey: pinKey)
    }

    public static func checkPin(_ pin: String) -> Bool {
        return UserDefaults.standard.string(forKey: pinKey) == hash(pin)
    }
}

// Asks for a new PIN twice, then calls done.
public func zalupaGramSetupHiddenPin(context: AccountContext, present: @escaping (ViewController) -> Void, done: @escaping () -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let ru = zalupaGramIsRussian(presentationData.strings)
    let alert: (String) -> Void = { text in
        present(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]))
    }
    present(promptController(context: context, text: ru ? "PIN для скрытых чатов" : "PIN for hidden chats", titleFont: .bold, subtitle: ru ? "Не меньше 4 символов. Забудете — скрытые чаты можно будет вернуть, только сбросив настройки ZalupaGram." : "At least 4 characters. If you forget it, hidden chats come back only after resetting the ZalupaGram settings.", value: "", placeholder: "PIN", characterLimit: 32, apply: { value in
        guard let value else {
            return
        }
        let pin = value.trimmingCharacters(in: .whitespaces)
        if pin.count < 4 {
            alert(ru ? "PIN слишком короткий." : "The PIN is too short.")
            return
        }
        present(promptController(context: context, text: ru ? "Повторите PIN" : "Repeat the PIN", titleFont: .bold, value: "", placeholder: "PIN", characterLimit: 32, apply: { repeated in
            guard let repeated else {
                return
            }
            if repeated.trimmingCharacters(in: .whitespaces) != pin {
                alert(ru ? "PIN не совпадает." : "The PINs don't match.")
                return
            }
            ZalupaGramHiddenChats.setPin(pin)
            done()
        }))
    }))
}

// Asks for the PIN and shows the hidden chats until the app goes to the background.
public func zalupaGramUnlockHiddenChats(context: AccountContext, present: @escaping (ViewController) -> Void, done: @escaping () -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let ru = zalupaGramIsRussian(presentationData.strings)
    present(promptController(context: context, text: ru ? "Введите PIN" : "Enter the PIN", titleFont: .bold, value: "", placeholder: "PIN", characterLimit: 32, apply: { value in
        guard let value else {
            return
        }
        if ZalupaGramHiddenChats.checkPin(value.trimmingCharacters(in: .whitespaces)) {
            ZalupaGramHiddenChats.setUnlocked(true)
            done()
        } else {
            present(textAlertController(context: context, title: nil, text: ru ? "Неверный PIN." : "Wrong PIN.", actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]))
        }
    }))
}

public func zalupaGramHideChatTitle(context: AccountContext, peerId: EnginePeer.Id, strings: PresentationStrings) -> String {
    if ZalupaGramHiddenChats.isMarkedHidden(accountPeerId: context.account.peerId.toInt64(), peerId: peerId.toInt64()) {
        return ZalupaGram.tr(strings, "👁 Don't hide the chat", "👁 Не скрывать чат")
    }
    return ZalupaGram.tr(strings, "🙈 Hide the chat", "🙈 Скрыть чат")
}

// Hides or shows a chat, asking to set up a PIN first.
public func zalupaGramToggleHiddenChat(context: AccountContext, peerId: EnginePeer.Id, present: @escaping (ViewController) -> Void) {
    let accountPeerId = context.account.peerId.toInt64()
    let isHidden = ZalupaGramHiddenChats.isMarkedHidden(accountPeerId: accountPeerId, peerId: peerId.toInt64())
    if isHidden {
        ZalupaGramHiddenChats.setHidden(accountPeerId: accountPeerId, peerId: peerId.toInt64(), false)
        return
    }
    let hide = {
        ZalupaGramHiddenChats.setHidden(accountPeerId: accountPeerId, peerId: peerId.toInt64(), true)
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let ru = zalupaGramIsRussian(presentationData.strings)
        if ZalupaGramHiddenChats.unlocked {
            present(textAlertController(context: context, title: nil, text: ru ? "Чат скрыт. Сейчас скрытые чаты открыты, он пропадёт из списка, когда приложение уйдёт в фон." : "The chat is hidden. Hidden chats are open now, it disappears from the list when the app goes to the background.", actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]))
        }
    }
    if ZalupaGramHiddenChats.hasPin {
        hide()
    } else {
        zalupaGramSetupHiddenPin(context: context, present: present, done: hide)
    }
}

// zalupagram://panic: hidden chats hidden again, the passcode lock on, back
// to the chat list.
public func zalupaGramPanic(context: AccountContext) {
    ZalupaGramHiddenChats.setUnlocked(false)
    context.sharedContext.appLockContext.lock()
    if let navigationController = context.sharedContext.mainWindow?.viewController as? NavigationController {
        navigationController.popToRoot(animated: false)
    }
}

// MARK: Theme

public enum ZalupaGramThemeVariant {
    case dark
    case light
    // Light by day and dark by night, following iOS.
    case system
    // «Night sky»: the night theme with violet -> pink bubbles, the animated
    // pixel sky and bubble outlines, the same as in ZalupaGram Desktop.
    case sky
    case skyDay
    case skyCycle
}

private let zalupaGramSkyAppliedKey = "zg_sky_theme_applied"

private func zalupaGramSkyAccent(outline: Bool) -> PresentationThemeAccentColor {
    let colors = (outline ? zalupaGramSkyBubbleColors : zalupaGramSkyPlainBubbleColors).map { 0xff000000 | $0 }
    return PresentationThemeAccentColor(index: outline ? 7703 : 7704, baseColor: .custom, accentColor: 0xFFB36AF3, bubbleColors: colors)
}

private func zalupaGramIsSkyAccent(_ accent: PresentationThemeAccentColor?) -> Bool {
    return accent?.index == 7703 || accent?.index == 7704
}

// The bundled wallpaper stored as a local image wallpaper, like a photo
// picked from the gallery. PNG keeps the pixel art sharp.
private func zalupaGramSkyWallpaper(context: AccountContext) -> TelegramWallpaper? {
    guard let image = UIImage(bundleImageName: "ZalupaGram/SkyWallpaper"), let data = image.pngData() else {
        return nil
    }
    let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    let thumbnailSize = size.fitted(CGSize(width: 320.0, height: 320.0))
    guard let thumbnail = generateScaledImage(image: image, size: thumbnailSize, scale: 1.0), let thumbnailData = thumbnail.jpegData(compressionQuality: 0.6) else {
        return nil
    }
    let store: (Data) -> LocalFileMediaResource = { data in
        let resource = LocalFileMediaResource(fileId: Int64.random(in: Int64.min ... Int64.max))
        context.sharedContext.accountManager.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: data, synchronous: true)
        context.engine.resources.storeResourceData(id: EngineMediaResource.Id(resource.id), data: data, synchronous: true)
        return resource
    }
    return .image([
        TelegramMediaImageRepresentation(dimensions: PixelDimensions(thumbnailSize), resource: store(thumbnailData), progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false),
        TelegramMediaImageRepresentation(dimensions: PixelDimensions(size), resource: store(data), progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)
    ], WallpaperSettings())
}

// Violet from the icon, the same as in ZalupaGram Desktop. Dark and light
// turn the automatic night theme off: with it on and iOS in the dark mode
// Telegram kept showing the night theme over the light one.
public func zalupaGramApplyTheme(context: AccountContext, variant: ZalupaGramThemeVariant) {
    let night: PresentationThemeReference = .builtin(.night)
    let day: PresentationThemeReference = .builtin(.day)
    let isSky = variant == .sky || variant == .skyDay || variant == .skyCycle
    if isSky {
        ZalupaGramSky.mode = (variant == .skyDay) ? .day : (variant == .skyCycle) ? .cycle : .night
    }
    let nightAccent: PresentationThemeAccentColor
    if isSky {
        nightAccent = zalupaGramSkyAccent(outline: ZalupaGramCore.option(.bubbleOutline))
    } else {
        nightAccent = PresentationThemeAccentColor(index: 7701, baseColor: .custom, accentColor: 0xFF9B7BFF, bubbleColors: [0xFF5B3FC4])
    }
    let dayAccent = PresentationThemeAccentColor(index: 7702, baseColor: .custom, accentColor: 0xFF7C4DFF, bubbleColors: [0xFFE9E0FF])
    let reference = (variant == .dark || isSky) ? night : day
    let skyWallpaper = isSky ? zalupaGramSkyWallpaper(context: context) : nil
    let _ = updatePresentationThemeSettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
        var accentColors = current.themeSpecificAccentColors
        accentColors[night.index] = nightAccent
        accentColors[day.index] = dayAccent
        var chatWallpapers = current.themeSpecificChatWallpapers
        if let skyWallpaper {
            for outline in [true, false] {
                chatWallpapers[coloredThemeIndex(reference: night, accentColor: zalupaGramSkyAccent(outline: outline))] = skyWallpaper
            }
        }
        var automaticThemeSwitchSetting = current.automaticThemeSwitchSetting
        automaticThemeSwitchSetting.theme = night
        switch variant {
        case .dark, .light, .sky, .skyDay, .skyCycle:
            automaticThemeSwitchSetting.force = false
            automaticThemeSwitchSetting.trigger = .explicitNone
        case .system:
            automaticThemeSwitchSetting.trigger = .system
        }
        return PresentationThemeSettings(theme: reference, themePreferredBaseTheme: current.themePreferredBaseTheme, themeSpecificAccentColors: accentColors, themeSpecificChatWallpapers: chatWallpapers, useSystemFont: current.useSystemFont, fontSize: current.fontSize, listsFontSize: current.listsFontSize, chatBubbleSettings: current.chatBubbleSettings, automaticThemeSwitchSetting: automaticThemeSwitchSetting, largeEmoji: current.largeEmoji, reduceMotion: current.reduceMotion)
    }).startStandalone()
}

// The animated sky answers to the messenger: a pigeon with a letter on a new
// message, a salute on the birthday of the user from the profile.
private var zalupaGramSkyDisposable: Disposable?

public func zalupaGramStartSky(context: AccountContext) {
    let sky = ZalupaGramSky.shared
    zalupaGramSkyDisposable?.dispose()
    zalupaGramSkyDisposable = (context.account.stateManager.notificationMessages
    |> deliverOnMainQueue).startStrict(next: { list in
        for item in list {
            for message in item.0 where message.flags.contains(.Incoming) {
                sky.fire(.received)
                if ZalupaGramCore.isCongrats(message.text) {
                    sky.fire(.congrats)
                }
            }
        }
    })
    let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Birthday(id: context.account.peerId))
    |> deliverOnMainQueue).startStandalone(next: { birthday in
        guard let birthday else {
            return
        }
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        guard Int(birthday.day) == parts.day, Int(birthday.month) == parts.month else {
            return
        }
        let stamp = "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
        if UserDefaults.standard.string(forKey: "zg_sky_birthday_fired") == stamp {
            return
        }
        UserDefaults.standard.set(stamp, forKey: "zg_sky_birthday_fired")
        Queue.mainQueue().after(3.0) {
            sky.fire(.birthday)
        }
    })
}

// «Night sky» is the default theme: applied once on the first start of a
// version that has it, after that the user's choice stays.
public func zalupaGramApplySkyThemeOnce(context: AccountContext) {
    if UserDefaults.standard.bool(forKey: zalupaGramSkyAppliedKey) {
        return
    }
    UserDefaults.standard.set(true, forKey: zalupaGramSkyAppliedKey)
    zalupaGramApplyTheme(context: context, variant: .sky)
}

// The outline switch picks the «Night sky» variant with or without outlines.
public func zalupaGramRefreshSkyOutline(context: AccountContext) {
    let night: PresentationThemeReference = .builtin(.night)
    let _ = updatePresentationThemeSettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
        guard let accent = current.themeSpecificAccentColors[night.index], zalupaGramIsSkyAccent(accent) else {
            return current
        }
        var accentColors = current.themeSpecificAccentColors
        accentColors[night.index] = zalupaGramSkyAccent(outline: ZalupaGramCore.option(.bubbleOutline))
        return current.withUpdatedThemeSpecificAccentColors(accentColors)
    }).startStandalone()
}
