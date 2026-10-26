import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import PromptUI

// ZalupaGram fork: the VPN screen in ZalupaGram settings.

public func zalupaGramVpnStatusLabel(strings: PresentationStrings) -> String {
    let vpn = ZalupaGramVpn.shared
    switch vpn.status {
    case .connected:
        return ZalupaGram.tr(strings, "On", "Вкл.")
    case .connecting:
        return "…"
    default:
        return vpn.isConnected ? "…" : ZalupaGram.tr(strings, "Off", "Выкл.")
    }
}

private final class VpnArguments {
    let toggle: (Bool) -> Void
    let editUrl: () -> Void
    let refresh: () -> Void
    let select: (Int) -> Void
    let ping: () -> Void

    init(toggle: @escaping (Bool) -> Void, editUrl: @escaping () -> Void, refresh: @escaping () -> Void, select: @escaping (Int) -> Void, ping: @escaping () -> Void) {
        self.toggle = toggle
        self.editUrl = editUrl
        self.refresh = refresh
        self.select = select
        self.ping = ping
    }
}

private enum VpnEntry: ItemListNodeEntry {
    case toggle(String, Bool)
    case status(String)
    case subscriptionHeader(String)
    case url(String, String)
    case refresh(String)
    case subscriptionInfo(String)
    case serversHeader(String)
    case server(Int32, String, String, Bool)
    case ping(String)
    case info(String)

    var section: ItemListSectionId {
        switch self {
        case .toggle, .status:
            return 0
        case .subscriptionHeader, .url, .refresh, .subscriptionInfo:
            return 1
        case .serversHeader, .server, .ping:
            return 2
        case .info:
            return 3
        }
    }

    var stableId: Int32 {
        switch self {
        case .toggle:
            return 0
        case .status:
            return 1
        case .subscriptionHeader:
            return 10
        case .url:
            return 11
        case .refresh:
            return 12
        case .subscriptionInfo:
            return 13
        case .serversHeader:
            return 20
        case let .server(index, _, _, _):
            return 100 + index
        case .ping:
            return 100000
        case .info:
            return 100001
        }
    }

    static func ==(lhs: VpnEntry, rhs: VpnEntry) -> Bool {
        switch lhs {
        case let .toggle(text, value):
            if case .toggle(text, value) = rhs {
                return true
            }
            return false
        case let .status(text):
            if case .status(text) = rhs {
                return true
            }
            return false
        case let .subscriptionHeader(text):
            if case .subscriptionHeader(text) = rhs {
                return true
            }
            return false
        case let .url(text, value):
            if case .url(text, value) = rhs {
                return true
            }
            return false
        case let .refresh(text):
            if case .refresh(text) = rhs {
                return true
            }
            return false
        case let .subscriptionInfo(text):
            if case .subscriptionInfo(text) = rhs {
                return true
            }
            return false
        case let .serversHeader(text):
            if case .serversHeader(text) = rhs {
                return true
            }
            return false
        case let .server(index, title, subtitle, checked):
            if case .server(index, title, subtitle, checked) = rhs {
                return true
            }
            return false
        case let .ping(text):
            if case .ping(text) = rhs {
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

    static func <(lhs: VpnEntry, rhs: VpnEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! VpnArguments
        switch self {
        case let .toggle(text, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: text, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(value)
            })
        case let .status(text), let .subscriptionInfo(text), let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .subscriptionHeader(text), let .serversHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .url(text, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: text, label: value, sectionId: self.section, style: .blocks, action: {
                arguments.editUrl()
            })
        case let .refresh(text):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.refresh()
            })
        case let .server(index, title, subtitle, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, subtitle: subtitle, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: {
                arguments.select(Int(index))
            })
        case let .ping(text):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.ping()
            })
        }
    }
}

private func formatBytes(_ value: Int64) -> String {
    return String(format: "%.1f", Double(value) / 1024.0 / 1024.0 / 1024.0)
}

private func vpnEntries(presentationData: PresentationData) -> [VpnEntry] {
    let ru = zalupaGramIsRussian(presentationData.strings)
    let t: (String, String) -> String = { english, russian in
        return ru ? russian : english
    }
    let vpn = ZalupaGramVpn.shared
    let subscription = vpn.subscription
    var entries: [VpnEntry] = []

    entries.append(.toggle(t("VPN for ZalupaGram", "VPN для ZalupaGram"), vpn.isConnected))
    let serverName = vpn.selected < subscription.servers.count ? subscription.servers[vpn.selected].name : ""
    switch vpn.status {
    case .connected:
        entries.append(.status(t("Connected: ", "Подключено: ") + serverName))
    case .connecting:
        entries.append(.status(t("Connecting…", "Подключаюсь…")))
    case .loading:
        entries.append(.status(t("Loading the subscription…", "Загружаю подписку…")))
    case let .failed(error):
        entries.append(.status(t("Error: ", "Ошибка: ") + error))
    case .disconnected:
        entries.append(.status(t("Off. Only ZalupaGram goes through the VPN, other apps don't.", "Выключен. Через VPN идёт только ZalupaGram, другие приложения — напрямую.")))
    }

    entries.append(.subscriptionHeader(t("SUBSCRIPTION", "ПОДПИСКА")))
    let url = vpn.subscriptionUrl
    let shortUrl: String
    if url.isEmpty {
        shortUrl = t("not set", "не задана")
    } else {
        shortUrl = URL(string: url)?.host ?? String(url.prefix(24))
    }
    entries.append(.url(t("Subscription link", "Ссылка на подписку"), shortUrl))
    if !url.isEmpty {
        entries.append(.refresh(t("Update the subscription", "Обновить подписку")))
    }
    var details: [String] = []
    if !subscription.title.isEmpty {
        details.append(subscription.title)
    }
    if subscription.total > 0 {
        details.append(t("Traffic: ", "Трафик: ") + formatBytes(subscription.upload + subscription.download) + t(" of ", " из ") + formatBytes(subscription.total) + t(" GB", " ГБ"))
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: ru ? "ru_RU" : "en_US")
    formatter.dateFormat = "dd.MM.yyyy HH:mm"
    if subscription.expire > 0 {
        details.append(t("Until ", "До ") + formatter.string(from: Date(timeIntervalSince1970: TimeInterval(subscription.expire))))
    }
    if subscription.updated > 0 {
        details.append(t("Updated ", "Обновлена ") + formatter.string(from: Date(timeIntervalSince1970: TimeInterval(subscription.updated))))
    }
    if !details.isEmpty {
        entries.append(.subscriptionInfo(details.joined(separator: "\n")))
    }

    if !subscription.servers.isEmpty {
        entries.append(.serversHeader(t("SERVERS", "СЕРВЕРЫ")))
        for (index, server) in subscription.servers.enumerated() {
            var subtitle = server.proto
            if let ping = vpn.pings[index] {
                subtitle += " · " + (ping < 0 ? t("unreachable", "недоступен") : "\(ping)" + t(" ms", " мс"))
            }
            entries.append(.server(Int32(index), server.name, subtitle, index == vpn.selected))
        }
        entries.append(.ping(t("Check the ping", "Проверить пинг")))
    }

    entries.append(.info(t(
        "Links like in Happ and v2rayN: vless, vmess, trojan, shadowsocks and JSON configs; happ://crypt links are not supported. iOS freezes apps in the background, so the VPN works while ZalupaGram is open and reconnects in a second when you come back.",
        "Подписки как в Happ и v2rayN: vless, vmess, trojan, shadowsocks и JSON-конфиги; зашифрованные happ://crypt не поддерживаются. iOS замораживает свёрнутые приложения, поэтому VPN работает, пока ZalupaGram открыт, и переподключается за секунду при возвращении."
    )))
    return entries
}

public func zalupaGramVpnController(context: AccountContext) -> ViewController {
    let vpn = ZalupaGramVpn.shared
    vpn.attach(accountManager: context.sharedContext.accountManager)
    var presentControllerImpl: ((ViewController) -> Void)?

    let arguments = VpnArguments(toggle: { value in
        if value {
            vpn.connect()
        } else {
            vpn.disconnect()
        }
    }, editUrl: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let ru = zalupaGramIsRussian(presentationData.strings)
        presentControllerImpl?(promptController(context: context, text: ru ? "Ссылка на подписку" : "Subscription link", titleFont: .bold, subtitle: ru ? "https://… из Happ, v2rayN или панели вашего VPN. Пустая — удалить подписку." : "https://… from Happ, v2rayN or your VPN panel. Empty to remove it.", value: vpn.subscriptionUrl, placeholder: "https://", characterLimit: 2048, apply: { value in
            if let value {
                vpn.setSubscriptionUrl(value)
            }
        }))
    }, refresh: {
        vpn.refresh()
    }, select: { index in
        vpn.select(index)
    }, ping: {
        vpn.ping()
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, vpn.changes)
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("VPN"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: vpnEntries(presentationData: presentationData), style: .blocks, emptyStateItem: nil, animateChanges: false)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
