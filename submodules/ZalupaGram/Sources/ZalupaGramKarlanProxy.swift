import Foundation
import Network
import TelegramCore

// A tiny SOCKS5 proxy on localhost for the «Карлан» page. WebKit on the
// iPhone may reach a Cloudflare site over HTTP/3 (UDP), IPv6 or the cellular
// network (Wi-Fi Assist), which can miss the VPN of the router. Through this
// proxy the page goes the way a PC in the same network does: TCP over IPv4,
// through Wi-Fi while it is up.
final class ZalupaGramKarlanProxy {
    static let shared = ZalupaGramKarlanProxy()

    private let queue = DispatchQueue(label: "zalupagram.karlan.proxy")
    private let pathMonitor = NWPathMonitor()
    private var wifiUp = false
    private var listener: NWListener?
    private var waiting: [(Int?) -> Void] = []

    // Main queue only.
    private(set) var port: Int?

    private init() {
        self.pathMonitor.pathUpdateHandler = { [weak self] path in
            self?.wifiUp = path.status == .satisfied && path.usesInterfaceType(.wifi)
        }
        self.pathMonitor.start(queue: self.queue)
    }

    // Calls back on the main queue with the listening port, nil if it failed.
    func start(_ completion: @escaping (Int?) -> Void) {
        if let port = self.port {
            completion(port)
            return
        }
        self.waiting.append(completion)
        if self.listener != nil {
            return
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        parameters.allowLocalEndpointReuse = true
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            Logger.shared.log("ZalupaGram", "karlan proxy: can't listen: \(error)")
            self.finishStart(nil)
            return
        }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            switch state {
            case .ready:
                let port = listener?.port.map { Int($0.rawValue) }
                DispatchQueue.main.async {
                    guard let self else {
                        return
                    }
                    Logger.shared.log("ZalupaGram", "karlan proxy: listening on \(port ?? 0)")
                    self.finishStart(port)
                }
            case let .failed(error):
                DispatchQueue.main.async {
                    guard let self else {
                        return
                    }
                    Logger.shared.log("ZalupaGram", "karlan proxy: failed: \(error)")
                    self.reset()
                }
            case .cancelled:
                DispatchQueue.main.async {
                    self?.reset()
                }
            default:
                break
            }
        }
        listener.start(queue: self.queue)
    }

    // After a long time in the background the listening socket may be gone.
    var isAlive: Bool {
        guard let listener = self.listener, self.port != nil else {
            return false
        }
        if case .ready = listener.state {
            return true
        }
        return false
    }

    func restartIfNeeded() {
        if self.port != nil && !self.isAlive {
            self.listener?.cancel()
            self.reset()
        }
    }

    private func reset() {
        self.listener = nil
        self.port = nil
        self.finishStart(nil)
    }

    private func finishStart(_ port: Int?) {
        self.port = port
        let waiting = self.waiting
        self.waiting.removeAll()
        for completion in waiting {
            completion(port)
        }
    }

    // MARK: - SOCKS5

    private func accept(_ client: NWConnection) {
        client.start(queue: self.queue)
        self.readGreeting(client, buffer: Data())
    }

    private func receive(_ client: NWConnection, buffer: Data, then: @escaping (Data) -> Void) {
        client.receive(minimumIncompleteLength: 1, maximumLength: 512) { data, _, _, error in
            guard error == nil, let data, !data.isEmpty else {
                client.cancel()
                return
            }
            then(buffer + data)
        }
    }

    private func readGreeting(_ client: NWConnection, buffer: Data) {
        let bytes = [UInt8](buffer)
        if bytes.count >= 2 {
            guard bytes[0] == 5 else {
                client.cancel()
                return
            }
            let length = 2 + Int(bytes[1])
            if bytes.count >= length {
                // No authentication.
                client.send(content: Data([5, 0]), completion: .contentProcessed { [weak self] error in
                    guard error == nil else {
                        client.cancel()
                        return
                    }
                    self?.readRequest(client, buffer: Data(bytes[length...]))
                })
                return
            }
        }
        self.receive(client, buffer: buffer) { [weak self] data in
            self?.readGreeting(client, buffer: data)
        }
    }

    private func readRequest(_ client: NWConnection, buffer: Data) {
        let bytes = [UInt8](buffer)
        if bytes.count >= 5 {
            var host: NWEndpoint.Host?
            var addressEnd = 0
            var isIPv6 = false
            switch bytes[3] {
            case 1:
                addressEnd = 4 + 4
                if bytes.count >= addressEnd {
                    host = IPv4Address(Data(bytes[4..<addressEnd])).map { .ipv4($0) }
                }
            case 3:
                addressEnd = 5 + Int(bytes[4])
                if bytes.count >= addressEnd, let name = String(bytes: bytes[5..<addressEnd], encoding: .utf8) {
                    host = .name(name, nil)
                }
            case 4:
                addressEnd = 4 + 16
                isIPv6 = true
                if bytes.count >= addressEnd {
                    host = IPv6Address(Data(bytes[4..<addressEnd])).map { .ipv6($0) }
                }
            default:
                self.reply(client, code: 8)
                return
            }
            if bytes.count >= addressEnd + 2 {
                guard bytes[1] == 1, let host else {
                    // Only CONNECT.
                    self.reply(client, code: 7)
                    return
                }
                let port = UInt16(bytes[addressEnd]) << 8 | UInt16(bytes[addressEnd + 1])
                self.connect(client, host: host, port: port, ipv4: !isIPv6)
                return
            }
        }
        self.receive(client, buffer: buffer) { [weak self] data in
            self?.readRequest(client, buffer: data)
        }
    }

    private func reply(_ client: NWConnection, code: UInt8, then: (() -> Void)? = nil) {
        let answer = Data([5, code, 0, 1, 0, 0, 0, 0, 0, 0])
        client.send(content: answer, completion: .contentProcessed { error in
            if code != 0 || error != nil {
                client.cancel()
            } else {
                then?()
            }
        })
    }

    private func connect(_ client: NWConnection, host: NWEndpoint.Host, port: UInt16, ipv4: Bool) {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            self.reply(client, code: 1)
            return
        }
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = 20
        let parameters = NWParameters(tls: nil, tcp: tcp)
        if ipv4, let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        if self.wifiUp {
            parameters.prohibitedInterfaceTypes = [.cellular]
        }
        parameters.preferNoProxies = true

        let remote = NWConnection(host: host, port: endpointPort, using: parameters)
        let state = ConnectState()
        remote.stateUpdateHandler = { [weak self] connectionState in
            switch connectionState {
            case .ready:
                guard !state.done else {
                    return
                }
                state.done = true
                self?.reply(client, code: 0, then: {
                    self?.pipe(from: client, to: remote)
                    self?.pipe(from: remote, to: client)
                })
            case let .waiting(error), let .failed(error):
                if !state.done {
                    state.done = true
                    Logger.shared.log("ZalupaGram", "karlan proxy: \(host):\(port) failed: \(error)")
                    self?.reply(client, code: 5)
                }
                remote.cancel()
            case .cancelled:
                remote.stateUpdateHandler = nil
                client.cancel()
            default:
                break
            }
        }
        client.stateUpdateHandler = { clientState in
            switch clientState {
            case .failed, .cancelled:
                client.stateUpdateHandler = nil
                remote.cancel()
            default:
                break
            }
        }
        remote.start(queue: self.queue)
    }

    private func pipe(from: NWConnection, to: NWConnection) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                to.send(content: data, completion: .contentProcessed { sendError in
                    if sendError != nil {
                        from.cancel()
                        to.cancel()
                    } else if isComplete {
                        from.cancel()
                        to.cancel()
                    } else {
                        self?.pipe(from: from, to: to)
                    }
                })
            } else if isComplete || error != nil {
                from.cancel()
                to.cancel()
            } else {
                self?.pipe(from: from, to: to)
            }
        }
    }
}

private final class ConnectState {
    var done = false
}
