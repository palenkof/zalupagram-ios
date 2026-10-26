import Foundation
import UIKit
import Network
import SwiftSignalKit
import TelegramCore
import ZalupaGramXray

// ZalupaGram fork: VPN subscriptions like in Happ / v2rayN, the same as in
// ZalupaGram Desktop. A subscription url gives vless / vmess / trojan /
// shadowsocks servers, the chosen one runs in Xray-core inside the app as
// a local SOCKS5 proxy and only Telegram goes through it. iOS freezes the
// app in the background, so the proxy works while the app is open; it is
// restarted when the app comes back.

public final class ZalupaGramVpn {
    public struct Server {
        public let name: String
        public let proto: String
        public let address: String
        public let port: Int
        let outbound: [String: Any]
    }

    public struct Subscription {
        public var title: String = ""
        public var servers: [Server] = []
        public var upload: Int64 = 0
        public var download: Int64 = 0
        public var total: Int64 = 0
        public var expire: Int32 = 0
        public var updated: Int32 = 0
    }

    public enum Status: Equatable {
        case disconnected
        case loading
        case connecting
        case connected
        case failed(String)
    }

    public static let shared = ZalupaGramVpn()

    private enum Key {
        static let url = "zg_vpn_url"
        static let body = "zg_vpn_body"
        static let userInfo = "zg_vpn_userinfo"
        static let title = "zg_vpn_title"
        static let updated = "zg_vpn_updated"
        static let selected = "zg_vpn_selected"
        static let connected = "zg_vpn_connected"
        static let port = "zg_vpn_port"
        static let hwid = "zg_vpn_hwid"
    }

    private static let defaultPort = 47961
    private static let refreshInterval: Double = 12 * 60 * 60

    public private(set) var status: Status = .disconnected
    public private(set) var subscription = Subscription()
    public private(set) var selected: Int = 0
    public private(set) var pings: [Int: Int] = [:]
    private var accountManager: AccountManager<TelegramAccountManagerTypes>?
    private var started = false
    private var observers: [NSObjectProtocol] = []
    private let xrayQueue = Queue()
    private let changesPromise = ValuePromise<Int>(0, ignoreRepeated: false)
    private var changesCounter = 0

    // Fires on any change of the state, subscription, selection or pings.
    public var changes: Signal<Int, NoError> {
        return self.changesPromise.get()
    }

    private func notify() {
        self.changesCounter += 1
        self.changesPromise.set(self.changesCounter)
    }

    private func setStatus(_ status: Status) {
        self.status = status
        self.notify()
    }

    public var subscriptionUrl: String {
        return UserDefaults.standard.string(forKey: Key.url) ?? ""
    }

    public var isConnected: Bool {
        return UserDefaults.standard.bool(forKey: Key.connected)
    }

    private var port: Int {
        let value = UserDefaults.standard.integer(forKey: Key.port)
        return value > 0 ? value : ZalupaGramVpn.defaultPort
    }

    // Early on launch: Telegram may already connect through the saved proxy.
    public func start() {
        if self.started {
            return
        }
        self.started = true
        self.selected = UserDefaults.standard.integer(forKey: Key.selected)
        if let body = UserDefaults.standard.data(forKey: Key.body), !body.isEmpty {
            self.applySubscription(body: body, userInfo: UserDefaults.standard.string(forKey: Key.userInfo) ?? "", title: UserDefaults.standard.string(forKey: Key.title) ?? "", fresh: false)
            self.subscription.updated = Int32(UserDefaults.standard.integer(forKey: Key.updated))
        }
        if self.isConnected {
            self.startXray()
        }
        // A suspended app may lose its listening socket: start again on return.
        self.observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main, using: { [weak self] _ in
            guard let self else {
                return
            }
            if self.isConnected {
                self.startXray()
            }
            if !self.subscriptionUrl.isEmpty && Int32(Date().timeIntervalSince1970) - self.subscription.updated > Int32(ZalupaGramVpn.refreshInterval) {
                self.refresh()
            }
        }))
    }

    // When the accounts are ready, the proxy settings can be changed.
    public func attach(accountManager: AccountManager<TelegramAccountManagerTypes>) {
        self.accountManager = accountManager
        if !self.subscriptionUrl.isEmpty && Int32(Date().timeIntervalSince1970) - self.subscription.updated > Int32(ZalupaGramVpn.refreshInterval) {
            self.refresh()
        }
    }

    // MARK: Subscription

    public func setSubscriptionUrl(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == self.subscriptionUrl {
            return
        }
        UserDefaults.standard.set(trimmed, forKey: Key.url)
        UserDefaults.standard.removeObject(forKey: Key.body)
        self.subscription = Subscription()
        self.pings = [:]
        self.selected = 0
        self.notify()
        if trimmed.isEmpty {
            self.disconnect()
        } else {
            self.refresh()
        }
    }

    private var hwid: String {
        if let value = UserDefaults.standard.string(forKey: Key.hwid) {
            return value
        }
        let value = UUID().uuidString.lowercased()
        UserDefaults.standard.set(value, forKey: Key.hwid)
        return value
    }

    public func refresh() {
        guard let url = URL(string: self.subscriptionUrl), url.scheme != nil else {
            self.setStatus(.failed(zalupaGramVpnText("Paste a subscription link first.", "Сначала вставьте ссылку на подписку.")))
            return
        }
        if self.status != .connected {
            self.setStatus(.loading)
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30.0)
        // Panels choose the format by the client: ask for plain share links.
        request.setValue("v2rayN/7.13 ZalupaGram/\(ZalupaGram.version)", forHTTPHeaderField: "User-Agent")
        request.setValue(self.hwid, forHTTPHeaderField: "x-hwid")
        request.setValue("iOS", forHTTPHeaderField: "x-device-os")
        request.setValue(UIDevice.current.systemVersion, forHTTPHeaderField: "x-ver-os")
        request.setValue("ZalupaGram", forHTTPHeaderField: "x-device-model")
        URLSession.shared.dataTask(with: request, completionHandler: { [weak self] data, response, error in
            Queue.mainQueue().async {
                guard let self else {
                    return
                }
                let http = response as? HTTPURLResponse
                guard let data, error == nil, let http, http.statusCode == 200 else {
                    let text = error?.localizedDescription ?? "HTTP \(http?.statusCode ?? 0)"
                    Logger.shared.log("ZalupaGram", "VPN: subscription failed, \(text)")
                    if self.status != .connected {
                        self.setStatus(.failed(text))
                    }
                    return
                }
                Logger.shared.log("ZalupaGram", "VPN: subscription \(data.count) bytes")
                self.applySubscription(body: data, userInfo: http.value(forHTTPHeaderField: "subscription-userinfo") ?? "", title: http.value(forHTTPHeaderField: "profile-title") ?? "", fresh: true)
            }
        }).resume()
    }

    private func applySubscription(body: Data, userInfo: String, title: String, fresh: Bool) {
        let servers = zalupaGramParseSubscription(body)
        if fresh {
            Logger.shared.log("ZalupaGram", "VPN: \(servers.count) servers: " + servers.map { "\($0.proto) \($0.port)" }.joined(separator: ", "))
        }
        if servers.isEmpty {
            if fresh && self.status != .connected {
                self.setStatus(.failed(zalupaGramVpnText("No supported servers in the subscription.", "В подписке нет поддерживаемых серверов.")))
            }
            return
        }
        let wasName = self.selected < self.subscription.servers.count ? self.subscription.servers[self.selected].name : nil

        var subscription = Subscription()
        subscription.title = zalupaGramDecodeTitle(title)
        subscription.servers = servers
        for part in userInfo.split(separator: ";") {
            let pair = part.split(separator: "=").map { $0.trimmingCharacters(in: .whitespaces) }
            if pair.count != 2 {
                continue
            }
            let value = Int64(pair[1]) ?? 0
            switch pair[0] {
            case "upload":
                subscription.upload = value
            case "download":
                subscription.download = value
            case "total":
                subscription.total = value
            case "expire":
                subscription.expire = Int32(clamping: value)
            default:
                break
            }
        }
        subscription.updated = fresh ? Int32(Date().timeIntervalSince1970) : self.subscription.updated
        self.subscription = subscription
        self.pings = [:]
        if let wasName, let index = servers.firstIndex(where: { $0.name == wasName }) {
            self.selected = index
        }
        if self.selected < 0 || self.selected >= servers.count {
            self.selected = 0
        }
        if fresh {
            UserDefaults.standard.set(body, forKey: Key.body)
            UserDefaults.standard.set(userInfo, forKey: Key.userInfo)
            UserDefaults.standard.set(title, forKey: Key.title)
            UserDefaults.standard.set(Int(subscription.updated), forKey: Key.updated)
            UserDefaults.standard.set(self.selected, forKey: Key.selected)
            if case .loading = self.status {
                self.setStatus(.disconnected)
            } else if case .failed = self.status {
                self.setStatus(.disconnected)
            }
        }
        self.notify()
    }

    public func select(_ index: Int) {
        if index < 0 || index >= self.subscription.servers.count || index == self.selected {
            return
        }
        self.selected = index
        UserDefaults.standard.set(index, forKey: Key.selected)
        self.notify()
        if self.isConnected {
            self.startXray()
        }
    }

    // MARK: Connection

    public func connect() {
        if self.subscription.servers.isEmpty {
            self.setStatus(.failed(zalupaGramVpnText("Update the subscription first.", "Сначала обновите подписку.")))
            return
        }
        UserDefaults.standard.set(true, forKey: Key.connected)
        self.startXray()
    }

    public func disconnect() {
        UserDefaults.standard.set(false, forKey: Key.connected)
        self.xrayQueue.async {
            ZGXrayRunner.stop()
        }
        self.applyProxy(enabled: false)
        self.setStatus(.disconnected)
    }

    private func startXray() {
        guard self.selected < self.subscription.servers.count else {
            return
        }
        let server = self.subscription.servers[self.selected]
        self.setStatus(.connecting)
        let firstPort = self.port
        self.xrayQueue.async { [weak self] in
            // The port may be taken by another app: try a few others.
            var candidates = [firstPort]
            for _ in 0 ..< 4 {
                candidates.append(Int.random(in: 40000 ... 60000))
            }
            var lastError: String?
            var usedPort: Int?
            for port in candidates {
                guard let config = zalupaGramXrayConfig(server: server, socksPort: port) else {
                    lastError = "config"
                    break
                }
                if let error = ZGXrayRunner.start(withConfig: config) {
                    lastError = error
                    Logger.shared.log("ZalupaGram", "VPN: Xray on \(port) failed: \(error)")
                    if !error.contains("address already in use") {
                        break
                    }
                } else {
                    usedPort = port
                    break
                }
            }
            Queue.mainQueue().async {
                guard let self else {
                    return
                }
                if let usedPort {
                    Logger.shared.log("ZalupaGram", "VPN: Xray started, \(server.proto) on \(usedPort)")
                    UserDefaults.standard.set(usedPort, forKey: Key.port)
                    self.applyProxy(enabled: true)
                    self.setStatus(.connected)
                } else {
                    // Telegram goes directly rather than through a dead proxy.
                    self.applyProxy(enabled: false)
                    self.setStatus(.failed(lastError ?? "?"))
                }
            }
        }
    }

    private func isOurs(_ server: ProxyServerSettings) -> Bool {
        if case .socks5 = server.connection, server.host == "127.0.0.1" {
            return true
        }
        return false
    }

    private func applyProxy(enabled: Bool) {
        guard let accountManager = self.accountManager else {
            return
        }
        let ours = ProxyServerSettings(host: "127.0.0.1", port: Int32(self.port), connection: .socks5(username: nil, password: nil))
        let _ = updateProxySettingsInteractively(accountManager: accountManager, { [weak self] settings in
            guard let self else {
                return settings
            }
            var settings = settings
            let wasOurs = settings.activeServer.flatMap { self.isOurs($0) } ?? false
            settings.servers.removeAll(where: { self.isOurs($0) })
            if enabled {
                settings.servers.insert(ours, at: 0)
                settings.activeServer = ours
                settings.enabled = true
            } else if wasOurs {
                settings.activeServer = nil
                settings.enabled = false
            }
            return settings
        }).startStandalone()
    }

    // The proxy settings may still point to the VPN from the last launch.
    public func syncProxy() {
        self.applyProxy(enabled: self.isConnected && self.status == .connected)
    }

    // MARK: Ping

    public func ping() {
        let servers = self.subscription.servers
        self.pings = [:]
        self.notify()
        for (index, server) in servers.enumerated() {
            guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: server.port)) else {
                continue
            }
            let connection = NWConnection(host: NWEndpoint.Host(server.address), port: port, using: .tcp)
            let startTime = CFAbsoluteTimeGetCurrent()
            let state = PingState()
            let finish: (Int) -> Void = { [weak self] value in
                Queue.mainQueue().async {
                    if state.finished {
                        return
                    }
                    state.finished = true
                    connection.cancel()
                    self?.pings[index] = value
                    self?.notify()
                }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000.0))
                case .failed, .waiting:
                    finish(-1)
                default:
                    break
                }
            }
            connection.start(queue: .global())
            Queue.mainQueue().after(4.0, {
                finish(-1)
            })
        }
    }
}

private final class PingState {
    var finished = false
}

func zalupaGramVpnText(_ english: String, _ russian: String) -> String {
    let language = Locale.preferredLanguages.first ?? ""
    return language.hasPrefix("ru") ? russian : english
}

// MARK: Parsing

private func decodeBase64(_ value: String) -> Data? {
    var text = value.components(separatedBy: .whitespacesAndNewlines).joined()
    text = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while text.count % 4 != 0 {
        text.append("=")
    }
    return Data(base64Encoded: text)
}

private func zalupaGramDecodeTitle(_ title: String) -> String {
    let value = title.trimmingCharacters(in: .whitespaces)
    if value.hasPrefix("base64:"), let data = decodeBase64(String(value.dropFirst(7))), let decoded = String(data: data, encoding: .utf8) {
        return decoded
    }
    return value
}

private struct ShareUrl {
    let user: String
    let password: String
    let host: String
    let port: Int
    let params: [String: String]
    let name: String
}

private func parseShareUrl(_ link: String) -> ShareUrl? {
    guard let components = URLComponents(string: link), let host = components.host, !host.isEmpty, let port = components.port, port > 0 else {
        return nil
    }
    var params: [String: String] = [:]
    for item in components.queryItems ?? [] {
        params[item.name.lowercased()] = item.value ?? ""
    }
    var host_ = host
    if host_.hasPrefix("[") && host_.hasSuffix("]") {
        host_ = String(host_.dropFirst().dropLast())
    }
    let fragment = (components.fragment ?? "").trimmingCharacters(in: .whitespaces)
    return ShareUrl(user: components.user ?? "", password: components.password ?? "", host: host_, port: port, params: params, name: fragment.isEmpty ? "\(host_):\(port)" : fragment)
}

private func isTrue(_ value: String?) -> Bool {
    return value == "1" || value?.lowercased() == "true"
}

private func splitList(_ value: String) -> [String] {
    return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

// Xray streamSettings from share-link parameters.
private func streamSettings(_ p: [String: String], defaultSecurity: String) -> [String: Any] {
    var network = (p["type"] ?? "tcp").lowercased()
    if network.isEmpty {
        network = "tcp"
    }
    if network == "splithttp" {
        network = "xhttp"
    } else if network == "raw" {
        network = "tcp"
    }
    let security = (p["security"].flatMap { $0.isEmpty ? nil : $0 } ?? defaultSecurity).lowercased()
    let path = p["path"] ?? ""
    let host = p["host"] ?? ""

    var result: [String: Any] = ["network": network]
    switch network {
    case "ws":
        result["wsSettings"] = ["path": path.isEmpty ? "/" : path, "host": host]
    case "grpc":
        result["grpcSettings"] = ["serviceName": p["servicename"] ?? path, "multiMode": p["mode"] == "multi"]
    case "xhttp":
        var settings: [String: Any] = ["path": path.isEmpty ? "/" : path, "host": host, "mode": (p["mode"].flatMap { $0.isEmpty ? nil : $0 }) ?? "auto"]
        if let extra = p["extra"], let data = extra.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings["extra"] = object
        }
        result["xhttpSettings"] = settings
    case "httpupgrade":
        result["httpupgradeSettings"] = ["path": path.isEmpty ? "/" : path, "host": host]
    case "tcp":
        if p["headertype"] == "http" {
            result["tcpSettings"] = ["header": ["type": "http", "request": ["path": [path.isEmpty ? "/" : path], "headers": ["Host": [host]]]]]
        }
    default:
        break
    }

    let sni = p["sni"].flatMap { $0.isEmpty ? nil : $0 } ?? p["peer"].flatMap { $0.isEmpty ? nil : $0 } ?? host
    let fingerprint = p["fp"] ?? ""
    if security == "tls" {
        var tls: [String: Any] = ["serverName": sni, "allowInsecure": isTrue(p["allowinsecure"]) || isTrue(p["insecure"])]
        if !fingerprint.isEmpty {
            tls["fingerprint"] = fingerprint
        }
        if let alpn = p["alpn"], !alpn.isEmpty {
            tls["alpn"] = splitList(alpn)
        }
        result["security"] = "tls"
        result["tlsSettings"] = tls
    } else if security == "reality" {
        result["security"] = "reality"
        result["realitySettings"] = [
            "serverName": sni,
            "fingerprint": fingerprint.isEmpty ? "chrome" : fingerprint,
            "publicKey": p["pbk"] ?? "",
            "shortId": p["sid"] ?? "",
            "spiderX": p["spx"] ?? "",
        ]
    }
    return result
}

private func parseVless(_ link: String) -> ZalupaGramVpn.Server? {
    guard let url = parseShareUrl(link), !url.user.isEmpty else {
        return nil
    }
    var user: [String: Any] = ["id": url.user, "encryption": url.params["encryption"].flatMap { $0.isEmpty ? nil : $0 } ?? "none"]
    if let flow = url.params["flow"], !flow.isEmpty {
        user["flow"] = flow
    }
    return ZalupaGramVpn.Server(name: url.name, proto: "vless", address: url.host, port: url.port, outbound: [
        "protocol": "vless",
        "settings": ["vnext": [["address": url.host, "port": url.port, "users": [user]]]],
        "streamSettings": streamSettings(url.params, defaultSecurity: "none"),
    ])
}

private func parseTrojan(_ link: String) -> ZalupaGramVpn.Server? {
    guard let url = parseShareUrl(link), !url.user.isEmpty else {
        return nil
    }
    return ZalupaGramVpn.Server(name: url.name, proto: "trojan", address: url.host, port: url.port, outbound: [
        "protocol": "trojan",
        "settings": ["servers": [["address": url.host, "port": url.port, "password": url.user]]],
        "streamSettings": streamSettings(url.params, defaultSecurity: "tls"),
    ])
}

private func parseVmess(_ link: String) -> ZalupaGramVpn.Server? {
    guard let data = decodeBase64(String(link.dropFirst("vmess://".count))), let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return nil
    }
    let string: (String) -> String = { key in
        if let value = json[key] as? String {
            return value
        } else if let value = json[key] as? NSNumber {
            return value.stringValue
        }
        return ""
    }
    let address = string("add")
    let port = Int(string("port")) ?? 0
    let id = string("id")
    if address.isEmpty || port <= 0 || id.isEmpty {
        return nil
    }
    var p: [String: String] = [
        "type": string("net").isEmpty ? "tcp" : string("net"),
        "security": string("tls"),
        "sni": string("sni"),
        "host": string("host"),
        "path": string("path"),
        "alpn": string("alpn"),
        "fp": string("fp"),
        "headertype": string("type"),
    ]
    if p["type"] == "grpc" {
        p["servicename"] = p["path"]
        p["mode"] = string("type")
    }
    let name = string("ps")
    return ZalupaGramVpn.Server(name: name.isEmpty ? "\(address):\(port)" : name, proto: "vmess", address: address, port: port, outbound: [
        "protocol": "vmess",
        "settings": ["vnext": [["address": address, "port": port, "users": [[
            "id": id,
            "alterId": Int(string("aid")) ?? 0,
            "security": string("scy").isEmpty ? "auto" : string("scy"),
        ]]]]],
        "streamSettings": streamSettings(p, defaultSecurity: "none"),
    ])
}

private func parseShadowsocks(_ link: String) -> ZalupaGramVpn.Server? {
    var parsed = parseShareUrl(link)
    var method = ""
    var password = ""
    if parsed == nil {
        // Legacy: ss://base64(method:password@host:port)#name
        let body = String(link.dropFirst("ss://".count))
        let parts = body.split(separator: "#", maxSplits: 1)
        guard let data = decodeBase64(String(parts.first ?? "")), let decoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        parsed = parseShareUrl("ss://" + decoded + (parts.count > 1 ? "#" + parts[1] : ""))
        method = parsed?.user ?? ""
        password = parsed?.password ?? ""
    } else if let current = parsed, current.password.isEmpty {
        // SIP002: ss://base64url(method:password)@host:port#name
        if let data = decodeBase64(current.user), let decoded = String(data: data, encoding: .utf8), let colon = decoded.firstIndex(of: ":") {
            method = String(decoded[..<colon])
            password = String(decoded[decoded.index(after: colon)...])
        }
    } else if let current = parsed {
        method = current.user
        password = current.password
    }
    guard let url = parsed, !method.isEmpty, !password.isEmpty, url.params["plugin"] == nil else {
        return nil
    }
    return ZalupaGramVpn.Server(name: url.name, proto: "shadowsocks", address: url.host, port: url.port, outbound: [
        "protocol": "shadowsocks",
        "settings": ["servers": [["address": url.host, "port": url.port, "method": method, "password": password]]],
    ])
}

// One entry of a JSON subscription: a full Xray config with "remarks".
private func parseXrayConfig(_ config: [String: Any]) -> ZalupaGramVpn.Server? {
    for value in config["outbounds"] as? [[String: Any]] ?? [] {
        var outbound = value
        let proto = outbound["protocol"] as? String ?? ""
        if !["vless", "vmess", "trojan", "shadowsocks"].contains(proto) {
            continue
        }
        let settings = outbound["settings"] as? [String: Any] ?? [:]
        var endpoint = (settings["vnext"] as? [[String: Any]])?.first ?? (settings["servers"] as? [[String: Any]])?.first ?? settings
        if endpoint.isEmpty {
            endpoint = settings
        }
        let address = endpoint["address"] as? String ?? ""
        let port = (endpoint["port"] as? NSNumber)?.intValue ?? 0
        if address.isEmpty || port <= 0 {
            continue
        }
        outbound.removeValue(forKey: "tag")
        let remarks = config["remarks"] as? String ?? ""
        return ZalupaGramVpn.Server(name: remarks.isEmpty ? "\(address):\(port)" : remarks, proto: proto, address: address, port: port, outbound: outbound)
    }
    return nil
}

func zalupaGramParseLink(_ link: String) -> ZalupaGramVpn.Server? {
    let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = trimmed.lowercased()
    if lower.hasPrefix("vless://") {
        return parseVless(trimmed)
    } else if lower.hasPrefix("trojan://") {
        return parseTrojan(trimmed)
    } else if lower.hasPrefix("vmess://") {
        return parseVmess(trimmed)
    } else if lower.hasPrefix("ss://") {
        return parseShadowsocks(trimmed)
    }
    return nil
}

func zalupaGramParseSubscription(_ body: Data) -> [ZalupaGramVpn.Server] {
    guard var text = String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
        return []
    }
    if text.hasPrefix("[") || text.hasPrefix("{") {
        guard let data = text.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        let configs = (json as? [[String: Any]]) ?? ((json as? [String: Any]).map { [$0] } ?? [])
        return configs.compactMap(parseXrayConfig)
    }
    if !text.contains("://"), let data = decodeBase64(text), let decoded = String(data: data, encoding: .utf8) {
        text = decoded
    }
    return text.components(separatedBy: .newlines).compactMap(zalupaGramParseLink)
}

func zalupaGramXrayConfig(server: ZalupaGramVpn.Server, socksPort: Int) -> String? {
    var proxy = server.outbound
    proxy["tag"] = "proxy"
    let config: [String: Any] = [
        "log": ["loglevel": "warning"],
        "inbounds": [[
            "tag": "socks-in",
            "listen": "127.0.0.1",
            "port": socksPort,
            "protocol": "socks",
            "settings": ["auth": "noauth", "udp": true],
        ]],
        "outbounds": [
            proxy,
            ["tag": "direct", "protocol": "freedom"],
        ],
    ]
    guard JSONSerialization.isValidJSONObject(config), let data = try? JSONSerialization.data(withJSONObject: config) else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}
