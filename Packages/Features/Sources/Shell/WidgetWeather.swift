import CoreLocation
import CoreUI
import Foundation
import SwiftUI

extension EnvironmentValues {
    /// True in the gallery: the widget shows made-up values and asks for nothing (no location prompt before it is added).
    @Entry var widgetPreview = false
}

/// The weather where you are. Open-Meteo, not WeatherKit: it needs no entitlement, no key and no paid-programme setup, and
/// only a rounded position (about 10 km) leaves the Mac. The location prompt appears when the widget first shows on Home.
public struct WeatherReport: Equatable, Sendable {
    public struct Hour: Equatable, Sendable {
        public let at: Date
        public let temp: Int
        public let code: Int
    }
    public struct Day: Equatable, Sendable {
        public let at: Date
        public let high: Int
        public let low: Int
        public let code: Int
    }
    public var temp: Int
    public var code: Int
    public var wind: Int
    public var hours: [Hour]
    public var days: [Day]

    /// WMO weather code: an SF Symbol and two words.
    public static func look(_ code: Int) -> (symbol: String, words: String) {
        switch code {
        case 0: ("sun.max", "Sunny")
        case 1, 2: ("cloud.sun", "Partly cloudy")
        case 3: ("cloud", "Cloudy")
        case 45, 48: ("cloud.fog", "Fog")
        case 51...57: ("cloud.drizzle", "Drizzle")
        case 61...67, 80...82: ("cloud.rain", "Rain")
        case 71...77, 85, 86: ("cloud.snow", "Snow")
        case 95...99: ("cloud.bolt.rain", "Thunderstorm")
        default: ("cloud", "Cloudy")
        }
    }

    private struct Wire: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let wind_speed_10m: Double
        }
        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double]
            let weather_code: [Int]
        }
        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int]
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
        }
        let current: Current
        let hourly: Hourly
        let daily: Daily
    }

    /// The Open-Meteo answer, in the position's own time zone (`timezone=auto`; times are local wall-clock strings).
    static func parse(_ data: Data, now: Date = Date(), zone: TimeZone = .current) throws -> WeatherReport {
        let w = try JSONDecoder().decode(Wire.self, from: data)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let g = DateFormatter()
        g.locale = f.locale
        g.timeZone = zone
        g.dateFormat = "yyyy-MM-dd"
        let hours = zip(w.hourly.time, zip(w.hourly.temperature_2m, w.hourly.weather_code)).compactMap {
            t, v -> Hour? in
            guard let d = f.date(from: t), d >= now.addingTimeInterval(-3600) else { return nil }
            return Hour(at: d, temp: Int(v.0.rounded()), code: v.1)
        }
        let days = (0..<w.daily.time.count).compactMap { i -> Day? in
            guard let d = g.date(from: w.daily.time[i]) else { return nil }
            return Day(
                at: d, high: Int(w.daily.temperature_2m_max[i].rounded()),
                low: Int(w.daily.temperature_2m_min[i].rounded()), code: w.daily.weather_code[i])
        }
        return WeatherReport(
            temp: Int(w.current.temperature_2m.rounded()), code: w.current.weather_code,
            wind: Int(w.current.wind_speed_10m.rounded()), hours: Array(hours.prefix(8)), days: days)
    }
}

@MainActor @Observable
public final class WeatherProvider: NSObject, CLLocationManagerDelegate {
    public static let shared = WeatherProvider()
    public enum State: Equatable {
        case idle, asking, denied, loading, failed
        case ready(WeatherReport)
    }
    public private(set) var state: State = .idle
    private let manager = CLLocationManager()
    private var fetched: Date?

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    /// Called when the widget shows on Home: asks for the location once, then reads the forecast (at most every 20 min).
    public func start() {
        if let fetched, Date().timeIntervalSince(fetched) < 1200, case .ready = state { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            state = .asking
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted: state = .denied
        default:
            if state != .loading {
                if case .ready = state {} else { state = .loading }
                manager.requestLocation()
            }
        }
    }

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch self.manager.authorizationStatus {
            case .denied, .restricted: state = .denied
            case .notDetermined: break
            default:
                state = .loading
                self.manager.requestLocation()
            }
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let p = locations.last?.coordinate else { return }
        // About 10 km: a forecast does not need more, and no more leaves the Mac.
        let lat = (p.latitude * 10).rounded() / 10
        let lon = (p.longitude * 10).rounded() / 10
        Task { await load(lat, lon) }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in state = .failed }
    }

    private func load(_ lat: Double, _ lon: Double) async {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        c?.queryItems = [
            .init(name: "latitude", value: "\(lat)"), .init(name: "longitude", value: "\(lon)"),
            .init(name: "current", value: "temperature_2m,weather_code,wind_speed_10m"),
            .init(name: "hourly", value: "temperature_2m,weather_code"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "7"),
        ]
        guard let url = c?.url else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // The times come in the position's zone, which the device zone matches for a forecast of where you are.
            state = .ready(try WeatherReport.parse(data))
            fetched = Date()
        } catch {
            state = .failed
        }
    }
}

/// Made-up values for the gallery preview.
private let sampleWeather = WeatherReport(
    temp: 21, code: 0, wind: 8,
    hours: (0..<4).map { .init(at: Date().addingTimeInterval(Double($0) * 7200), temp: 22 + $0, code: $0 > 1 ? 3 : 0) },
    days: (0..<4).map {
        .init(at: Date().addingTimeInterval(Double($0) * 86_400), high: 24 - $0, low: 14, code: $0 > 1 ? 61 : 3)
    })

struct WeatherBody: View {
    @Environment(\.coreAccent) private var paneAccent
    let size: WidgetSize
    @Environment(\.widgetPreview) private var preview
    private let provider = WeatherProvider.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            if preview {
                report(sampleWeather)
            } else {
                switch provider.state {
                case .ready(let r): report(r)
                case .denied:
                    WHead("sun.max", "Weather")
                    WEmpty(symbol: "location.slash", text: "Allow location for Ainkrad in System Settings, Privacy")
                case .failed:
                    WHead("sun.max", "Weather")
                    WEmpty(symbol: "wifi.slash", text: "The forecast is not reachable")
                default:
                    WHead("sun.max", "Weather")
                    WEmpty(symbol: "sun.max", text: "Finding the weather")
                }
            }
        }
        .task { if !preview { provider.start() } }
    }

    private func hour(_ h: WeatherReport.Hour) -> some View {
        cell(h.at.formatted(.dateTime.hour()), h.code, "\(h.temp)°")
    }
    private func day(_ d: WeatherReport.Day) -> some View {
        cell(d.at.formatted(.dateTime.weekday(.abbreviated)), d.code, "\(d.high)°")
    }

    private func cell(_ top: String, _ code: Int, _ t: String) -> some View {
        VStack(spacing: 2) {
            WCaption(top)
            Image(systemName: WeatherReport.look(code).symbol).foregroundStyle(GlassInk.accent(paneAccent))
                .accessibilityHidden(true)
            Text(t).coreFont(size: MacTextSize.body, weight: .semibold).foregroundStyle(GlassInk.primary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func now(_ r: WeatherReport, big: CGFloat) -> some View {
        let l = WeatherReport.look(r.code)
        return VStack(alignment: .leading, spacing: 0) {
            Text("\(r.temp)°").font(.system(size: big, weight: .semibold)).foregroundStyle(GlassInk.primary)
            WCaption("\(l.words), wind \(r.wind) km/h")
        }
    }

    @ViewBuilder private func report(_ r: WeatherReport) -> some View {
        switch size {
        case .s:
            Image(systemName: WeatherReport.look(r.code).symbol).coreFont(size: 22).foregroundStyle(
                GlassInk.accent(paneAccent)
            )
            .accessibilityHidden(true)
            Spacer(minLength: 0)
            now(r, big: 38)
        case .m:
            HStack(alignment: .center, spacing: Space.s4) {
                now(r, big: 38)
                HStack { ForEach(Array(r.hours.prefix(4).enumerated()), id: \.offset) { _, h in hour(h) } }
            }
        case .w:
            HStack(alignment: .center, spacing: Space.s4) {
                now(r, big: 44)
                HStack { ForEach(Array(r.days.prefix(7).enumerated()), id: \.offset) { _, d in day(d) } }
            }
        case .l:
            WHead("sun.max", "Weather")
            now(r, big: 44)
            HStack { ForEach(Array(r.hours.prefix(4).enumerated()), id: \.offset) { _, h in hour(h) } }
            VStack(spacing: Space.s2) {
                ForEach(Array(r.days.dropFirst().prefix(3).enumerated()), id: \.offset) { _, d in
                    HStack {
                        Text(d.at.formatted(.dateTime.weekday(.wide))).coreFont(
                            size: MacTextSize.body, weight: .semibold)
                        Image(systemName: WeatherReport.look(d.code).symbol).foregroundStyle(
                            GlassInk.accent(paneAccent)
                        )
                        .accessibilityHidden(true)
                        Spacer(minLength: 0)
                        WCaption("\(d.high)° / \(d.low)°")
                    }
                    .foregroundStyle(GlassInk.primary).accessibilityElement(children: .combine)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
