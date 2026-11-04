import Foundation
import UIKit
import ZalupaGramCore
import ZalupaGramSkyCore

// The animated sky of the «Night sky» themes: one engine for all the chats,
// it runs only while a sky view is on the screen and the app is active.
public final class ZalupaGramSky {
    public static let shared = ZalupaGramSky()

    private static let cityKey = "zg_sky_city"
    private static let caughtKey = "zg_sky_caught"
    private static let cols = 90

    private let sky: OpaquePointer
    private var views: [Weak<ZalupaGramSkyView>] = []
    private var timer: Timer?
    private var lastTick: Date?
    private var grid: (Int, Int) = (0, 0)
    private var image: CGImage?
    private var weather: Int32 = 0
    private var lastPigeon: Date?
    private var weatherTimer: Timer?

    private init() {
        self.sky = zg_sky_create()
        ZalupaGramCore.skyEventHandler = { event in
            DispatchQueue.main.async {
                ZalupaGramSky.shared.fire(event)
            }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.lastTick = nil
            self?.update()
        })
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.update()
        })
        self.refreshWeather()
    }

    // MARK: Options

    public static var city: String {
        get {
            return UserDefaults.standard.string(forKey: cityKey) ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: cityKey)
            ZalupaGramSky.shared.refreshWeather()
        }
    }

    public static var caught: [String: Int] {
        return (UserDefaults.standard.dictionary(forKey: caughtKey) as? [String: Int]) ?? [:]
    }

    // MARK: Views

    fileprivate func add(_ view: ZalupaGramSkyView) {
        self.views.removeAll(where: { $0.value == nil || $0.value === view })
        self.views.append(Weak(view))
        self.update()
    }

    fileprivate func remove(_ view: ZalupaGramSkyView) {
        self.views.removeAll(where: { $0.value == nil || $0.value === view })
        self.update()
    }

    private var visibleViews: [ZalupaGramSkyView] {
        return self.views.compactMap({ $0.value }).filter({ $0.window != nil && $0.bounds.width > 0.0 })
    }

    fileprivate func update() {
        let active = UIApplication.shared.applicationState != .background && !self.visibleViews.isEmpty
        if active {
            if self.timer == nil {
                self.tick()
            }
        } else {
            self.timer?.invalidate()
            self.timer = nil
            self.lastTick = nil
        }
    }

    private var calm: Bool {
        return UIAccessibility.isReduceMotionEnabled || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private func applyOptions() {
        let date = Date()
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let minutes = Double(parts.hour ?? 0) * 60.0 + Double(parts.minute ?? 0) + Double(parts.second ?? 0) / 60.0
        zg_sky_set_time(self.sky, Int32(parts.year ?? 2026), Int32((parts.month ?? 1) - 1), Int32(parts.day ?? 1), minutes)
        zg_sky_set_mode(self.sky, Int32(ZG_SKY_MODE_CYCLE))
        zg_sky_set_weather(self.sky, self.weather)
        zg_sky_set_events(self.sky, self.calm ? 0 : 1)
        zg_sky_set_chat(self.sky, 1, 0.0, 0)
        zg_sky_set_launch_point(self.sky, 0.8, 0.92)
        let ghost = ZalupaGramCore.ghostOnline || ZalupaGramCore.option(.ghostRead) || ZalupaGramCore.option(.ghostTyping)
        zg_sky_set_ghost(self.sky, ghost ? 1 : 0)
    }

    private func tick() {
        self.timer?.invalidate()
        self.timer = nil
        let views = self.visibleViews
        guard let first = views.first, UIApplication.shared.applicationState != .background else {
            self.lastTick = nil
            return
        }
        let size = first.bounds.size
        let cell = size.width / CGFloat(ZalupaGramSky.cols)
        let rows = max(Int(ceil(size.height / cell)), 1)
        if self.grid != (ZalupaGramSky.cols, rows) {
            self.grid = (ZalupaGramSky.cols, rows)
            zg_sky_set_size(self.sky, Int32(ZalupaGramSky.cols), Int32(rows))
            self.image = nil
        }
        self.applyOptions()

        let now = Date()
        let dt = self.lastTick.map({ min(now.timeIntervalSince($0), 1.5) }) ?? 0.0
        self.lastTick = now
        let changed = zg_sky_advance(self.sky, dt, nil, 0)
        if changed > 0 || self.image == nil {
            self.image = self.makeImage()
        }
        for view in views {
            view.show(self.image)
        }
        let delay = max(Double(zg_sky_next_delay_ms(self.sky)) / 1000.0, 1.0 / 30.0)
        let timer = Timer(timeInterval: delay, repeats: false, block: { [weak self] _ in
            self?.tick()
        })
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func makeImage() -> CGImage? {
        let (cols, rows) = self.grid
        guard cols > 0, rows > 0, let pixels = zg_sky_pixels(self.sky) else {
            return nil
        }
        let data = Data(bytes: UnsafeRawPointer(pixels), count: cols * rows * 4)
        guard let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }
        let info = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue)
        return CGImage(width: cols, height: rows, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: cols * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    // MARK: Events

    public func fire(_ event: ZalupaGramCore.SkyEvent) {
        if event == .received {
            let now = Date()
            if let last = self.lastPigeon, now.timeIntervalSince(last) < 120.0 {
                return
            }
            self.lastPigeon = now
        }
        guard !self.visibleViews.isEmpty else {
            return
        }
        zg_sky_fire(self.sky, Int32(event.rawValue))
        self.timer?.invalidate()
        self.timer = nil
        self.tick()
    }

    fileprivate func tryCatch(view: ZalupaGramSkyView, point: CGPoint) -> String? {
        let (cols, rows) = self.grid
        guard cols > 0, rows > 0, view.bounds.width > 0.0 else {
            return nil
        }
        let cell = view.bounds.width / CGFloat(cols)
        guard let name = zg_sky_catch(self.sky, Int32(point.x / cell), Int32(point.y / cell)) else {
            return nil
        }
        let title = String(cString: name)
        var saved = ZalupaGramSky.caught
        saved[title] = (saved[title] ?? 0) + 1
        UserDefaults.standard.set(saved, forKey: ZalupaGramSky.caughtKey)
        return title
    }

    // MARK: Weather

    public func refreshWeather() {
        self.weatherTimer?.invalidate()
        self.weatherTimer = nil
        let city = ZalupaGramSky.city.trimmingCharacters(in: .whitespacesAndNewlines)
        if city.isEmpty {
            self.weather = 0
            return
        }
        let timer = Timer(timeInterval: 30.0 * 60.0, repeats: false, block: { [weak self] _ in
            self?.refreshWeather()
        })
        RunLoop.main.add(timer, forMode: .common)
        self.weatherTimer = timer

        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1"), URLQueryItem(name: "language", value: "ru")]
        guard let url = components.url else {
            return
        }
        URLSession.shared.dataTask(with: url, completionHandler: { [weak self] data, _, _ in
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let results = json["results"] as? [[String: Any]], let place = results.first, let latitude = place["latitude"] as? Double, let longitude = place["longitude"] as? Double else {
                return
            }
            self?.requestWeather(latitude: latitude, longitude: longitude)
        }).resume()
    }

    private func requestWeather(latitude: Double, longitude: Double) {
        // api.open-meteo.com is not reachable from some networks, met.no is.
        var components = URLComponents(string: "https://api.met.no/weatherapi/locationforecast/2.0/compact")!
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(format: "%.3f", latitude)),
            URLQueryItem(name: "lon", value: String(format: "%.3f", longitude))
        ]
        guard let url = components.url else {
            return
        }
        var request = URLRequest(url: url)
        // The service asks to name the application.
        request.setValue("ZalupaGram github.com/palenkof", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request, completionHandler: { [weak self] data, _, _ in
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let properties = json["properties"] as? [String: Any], let series = properties["timeseries"] as? [[String: Any]], let first = series.first?["data"] as? [String: Any] else {
                return
            }
            let summary = (first["next_1_hours"] as? [String: Any])?["summary"] as? [String: Any]
            let symbol = (summary?["symbol_code"] as? String) ?? ""
            let details = (first["instant"] as? [String: Any])?["details"] as? [String: Any]
            let wind = (details?["wind_speed"] as? Double) ?? 0.0
            let weather: Int32
            if symbol.contains("thunder") {
                weather = Int32(ZG_SKY_WEATHER_STORM)
            } else if symbol.contains("fog") {
                weather = Int32(ZG_SKY_WEATHER_FOG)
            } else if symbol.contains("heavysnow") || (symbol.contains("snow") && wind >= 11.0) {
                weather = Int32(ZG_SKY_WEATHER_BLIZZARD)
            } else if symbol.contains("snow") || symbol.contains("sleet") {
                weather = Int32(ZG_SKY_WEATHER_SNOW)
            } else if symbol.contains("rain") {
                weather = Int32(ZG_SKY_WEATHER_RAIN)
            } else if wind >= 11.0 {
                weather = Int32(ZG_SKY_WEATHER_WIND)
            } else {
                weather = Int32(ZG_SKY_WEATHER_CLEAR)
            }
            DispatchQueue.main.async {
                self?.weather = weather
            }
        }).resume()
    }
}

private final class Weak<T: AnyObject> {
    weak var value: T?

    init(_ value: T) {
        self.value = value
    }
}

// Shows the sky above the wallpaper, without smoothing.
public final class ZalupaGramSkyView: UIView {
    private let label = UILabel()
    private weak var tapWindow: UIWindow?
    private var tap: UITapGestureRecognizer?
    private let catchesTaps: Bool

    public init(frame: CGRect, catchesTaps: Bool) {
        self.catchesTaps = catchesTaps
        super.init(frame: frame)
        self.isUserInteractionEnabled = false
        self.layer.magnificationFilter = .nearest
        self.layer.contentsGravity = .resize
        self.backgroundColor = UIColor(red: 0.04, green: 0.06, blue: 0.31, alpha: 1.0)
        self.label.font = UIFont.systemFont(ofSize: 13.0, weight: .medium)
        self.label.textColor = .white
        self.label.textAlignment = .center
        self.label.backgroundColor = UIColor(red: 0.08, green: 0.08, blue: 0.24, alpha: 0.95)
        self.label.layer.cornerRadius = 8.0
        self.label.clipsToBounds = true
        self.label.alpha = 0.0
        self.addSubview(self.label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if let tap = self.tap {
            self.tapWindow?.removeGestureRecognizer(tap)
            self.tap = nil
        }
        if let window = self.window {
            if self.catchesTaps {
                let tap = UITapGestureRecognizer(target: self, action: #selector(self.tapped(_:)))
                tap.cancelsTouchesInView = false
                tap.delaysTouchesEnded = false
                window.addGestureRecognizer(tap)
                self.tap = tap
                self.tapWindow = window
            }
            ZalupaGramSky.shared.add(self)
        } else {
            ZalupaGramSky.shared.remove(self)
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        ZalupaGramSky.shared.update()
    }

    fileprivate func show(_ image: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.layer.contents = image
        CATransaction.commit()
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        guard self.window != nil else {
            return
        }
        let point = recognizer.location(in: self)
        guard self.bounds.contains(point), let title = ZalupaGramSky.shared.tryCatch(view: self, point: point) else {
            return
        }
        let ru = Locale.preferredLanguages.first?.hasPrefix("ru") ?? false
        self.label.text = "  " + (ru ? "Поймано: " : "Caught: ") + title + "  "
        self.label.sizeToFit()
        self.label.frame = CGRect(x: (self.bounds.width - self.label.bounds.width) / 2.0, y: self.bounds.height * 0.2, width: self.label.bounds.width, height: self.label.bounds.height + 10.0)
        self.label.alpha = 1.0
        UIView.animate(withDuration: 0.4, delay: 2.5, options: [], animations: {
            self.label.alpha = 0.0
        })
    }
}

// Colors come back through UIColor components, so they may differ by a unit.
public func zalupaGramSkyIsMarked(outgoingFill: [UInt32]) -> Bool {
    let marker: [UInt32] = [0x6d3fe6, 0xd35de6]
    guard outgoingFill.count == marker.count else {
        return false
    }
    for (value, expected) in zip(outgoingFill, marker) {
        for shift: UInt32 in [0, 8, 16] {
            let a = Int((value >> shift) & 0xff)
            let b = Int((expected >> shift) & 0xff)
            if abs(a - b) > 2 {
                return false
            }
        }
    }
    return true
}
