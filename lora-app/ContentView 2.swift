import SwiftUI
import Charts

@main
struct LoRaSafetyApp: App {
    @StateObject private var store = SafetyStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: SafetyStore
    @AppStorage("useCelsius") private var useCelsius = false

    private let bg = Color(red: 0.04, green: 0.06, blue: 0.10)
    private let card = Color(red: 0.09, green: 0.12, blue: 0.17)

    private var ble: SensorBLE { store.ble }
    /// The last VALID reading. It may be old; always check freshness before trusting it.
    private var reading: Reading? { store.ble.lastKnown }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        VStack(spacing: 16) {
                            connectionCard(now: ctx.date)
                            statusCard(now: ctx.date)
                            fallbackCard(now: ctx.date)
                            tiles(now: ctx.date)
                        }
                    }
                    thresholdCard
                    chartCard
                    actionsCard
                    alertsCard
                }
                .padding()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Helpers

    private func tempText(_ c: Double) -> String {
        useCelsius ? "\(Int(c.rounded()))°C" : "\(Int(celsiusToF(c).rounded()))°F"
    }

    private func feelsText(_ f: Double) -> String {
        useCelsius ? "\(Int(((f - 32) * 5 / 9).rounded()))°C" : "\(Int(f.rounded()))°F"
    }

    private func ago(_ date: Date, now: Date = Date()) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 60 { return "\(s) s ago" }
        if s < 3600 { return "\(s / 60) min ago" }
        if s < 86400 { return "\(s / 3600) h ago" }
        return "\(s / 86400) d ago"
    }

    // MARK: Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Solace ☼").font(.title.bold())
                Text("Find safety where you are").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Button(useCelsius ? "Show °F" : "Show °C") { useCelsius.toggle() }
                .font(.subheadline)
        }
    }

    // MARK: Connection + last valid reading

    private var connectionTitle: String {
        if ble.isDemo { return "DEMO DATA (not your sensors)" }
        if ble.state == .connected {
            return ble.packetProblem
                ? "Connected, but the temperature sensor isn't reporting"
                : "Connected to \(ble.deviceName ?? "sensor")"
        }
        return ble.state.text
    }

    private func connectionCard(now: Date) -> some View {
        let fresh = ble.freshness(at: now)
        let dot: Color = ble.isDemo ? .blue : (fresh == .live ? .green : .orange)

        return HStack {
            Circle().fill(dot).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(connectionTitle).font(.subheadline.weight(.semibold))
                if let r = reading {
                    let stamp = r.date.formatted(date: .omitted, time: .standard)
                    Text("Last valid reading: \(stamp) (\(ago(r.date, now: now)))")
                        .font(.caption)
                        .foregroundStyle(fresh == .live ? Color.secondary : Color.orange)
                } else {
                    Text("No valid reading yet")
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                }
            }
            Spacer()
            if ble.isDemo {
                Button("Stop demo") { ble.stopDemo() }
                    .buttonStyle(.borderedProminent)
            } else {
                if ble.state != .connected {
                    Button("Rescan") { ble.rescan() }
                        .buttonStyle(.bordered)
                }
                Button("Demo") { ble.startDemo() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(card, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Status (live / stale / no data)

    @ViewBuilder
    private func statusCard(now: Date) -> some View {
        switch ble.freshness(at: now) {
        case .live:
            if let f = reading?.feelsLikeF {
                liveCard(f)
            } else {
                noDataCard
            }
        case .stale:
            staleCard(now: now)
        case .none:
            noDataCard
        }
    }

    private func liveCard(_ f: Double) -> some View {
        let level = HeatLevel(feelsLikeF: f)
        return VStack(spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: level.icon)
                    .font(.largeTitle)
                    .foregroundStyle(level.color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(level.title).font(.title2.bold())
                    Text(level.advice).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(feelsText(f)).font(.system(size: 38, weight: .heavy))
                    Text("feels like").font(.caption).foregroundStyle(.secondary)
                }
            }
            if level >= .danger { helpButtons }
            if level == .extremeDanger {
                Link(destination: URL(string: "tel://911")!) {
                    Text("Call 911")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.black)
                }
            }
        }
        .padding()
        .background(level.color.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(level.color.opacity(0.6), lineWidth: 1))
    }

    private var helpButtons: some View {
        HStack(spacing: 10) {
            Button {
                store.selectedTab = .safety
            } label: {
                Label("Heat stroke help", systemImage: "cross.case.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

            Button {
                store.coolSearchRequests += 1
                store.selectedTab = .safety
            } label: {
                Label("Cool place", systemImage: "snowflake")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
        }
    }

    /// Shown when readings are old or the sensor is disconnected. Never styled as "safe".
    private func staleCard(now: Date) -> some View {
        let lastLevel = reading?.feelsLikeF.map { HeatLevel(feelsLikeF: $0) }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sensor readings are out of date").font(.title3.bold())
                    Text("Conditions may have changed. Don't assume it's safe.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }

            if let r = reading {
                let stamp = r.date.formatted(date: .omitted, time: .standard)
                Text("Last valid reading: \(stamp) (\(ago(r.date, now: now)))")
                    .font(.subheadline)
                if let f = r.feelsLikeF, let level = lastLevel {
                    Text("At that time: \(level.title), feels like \(feelsText(f))")
                        .font(.subheadline.bold())
                        .foregroundStyle(level.color)
                }
            }

            if ble.packetProblem && ble.state == .connected {
                Text("The sensor is connected but isn't sending a temperature. Check the AHT20/BMP280 wiring.")
                    .font(.caption)
            }

            HStack {
                Button("Heat safety guide") { store.selectedTab = .safety }
                    .buttonStyle(.bordered)
                Button("Rescan") { ble.rescan() }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.6), lineWidth: 1))
    }

    private var noDataCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.title)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No sensor data").font(.title3.bold())
                    Text("Until your sensor reports, conditions are unknown. Don't assume they're safe.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Button("Heat safety guide") { store.selectedTab = .safety }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.6), lineWidth: 1))
    }

    // MARK: Backup: area weather from the internet

    @ViewBuilder
    private func fallbackCard(now: Date) -> some View {
        if ble.freshness(at: now) != .live {
            VStack(alignment: .leading, spacing: 8) {
                Text("Area weather (backup, not your sensor)").font(.headline)

                if let a = store.weather.area {
                    let level = HeatLevel(feelsLikeF: a.feelsLikeF)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feelsText(a.feelsLikeF)).font(.system(size: 30, weight: .heavy))
                            Text("feels like · \(level.title)")
                                .font(.subheadline)
                                .foregroundStyle(level.color)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Air \(tempText((a.tempF - 32) * 5 / 9))").font(.subheadline)
                            Text("Humidity \(Int(a.humidity.rounded()))%").font(.subheadline)
                            Text(String(format: "UV %.1f", a.uvIndex)).font(.subheadline)
                        }
                    }
                    Text("From Open-Meteo for your area, updated \(ago(a.fetched, now: now)). Your exact spot may be hotter, especially in direct sun.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(store.location.coordinate == nil
                         ? "Choose a location in the Safety Hub to get area weather while the sensor is offline."
                         : "Fetching area weather. This needs an internet connection.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if store.location.coordinate == nil {
                        Button("Set location") { store.selectedTab = .safety }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(card, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: Tiles

    private func tiles(now: Date) -> some View {
        let live = ble.freshness(at: now) == .live
        let note = live ? nil : "last reading, not live"

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            tile("Temperature",
                 reading?.tempC.map(tempText) ?? "--",
                 note ?? "air temperature")

            let uv = reading?.uvIndex
            tile("UV index",
                 uv.map { String(format: "%.1f", $0) } ?? "--",
                 note ?? (uv.map { UVLevel(index: $0).label } ?? "no data"),
                 tint: live ? uv.map { UVLevel(index: $0).color } : nil)

            tile("Humidity",
                 reading?.humidity.map { "\(Int($0.rounded()))%" } ?? "--",
                 note ?? "from sensor")

            tile("Light",
                 reading?.lux.map { "\(Int($0.rounded())) lx" } ?? "--",
                 note ?? (reading?.pressureHpa.map { String(format: "%.0f hPa", $0) } ?? "no pressure data"))

            tile("GPS",
                 reading.map { $0.hasFix ? "Fix" : "No fix" } ?? "--",
                 note ?? (reading.map { $0.hasFix
                    ? String(format: "%.4f, %.4f", $0.lat, $0.lon)
                    : "\($0.satellites) satellites" } ?? "no data"))
        }
        .opacity(live ? 1 : 0.5)
    }

    private func tile(_ title: String, _ value: String, _ sub: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 30, weight: .heavy))
            Text(sub).font(.caption).foregroundStyle(tint ?? .secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(card, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Temperature alert setting

    private var thresholdCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Temperature alert").font(.headline)
            Stepper(value: $store.thresholdF, in: 70...130, step: 1) {
                Text("Notify me at feels-like \(feelsText(store.thresholdF))")
                    .font(.subheadline)
            }
            Text("You'll get a notification when it feels this hot or hotter, then a reminder every 15 minutes while it stays above.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(card, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Feels-like trend").font(.headline)
            let points = ble.history.compactMap { r -> (Date, Double)? in
                guard let f = r.feelsLikeF else { return nil }
                return (r.date, useCelsius ? (f - 32) * 5 / 9 : f)
            }
            if points.count < 2 {
                Text("Collecting data...").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                        LineMark(x: .value("Time", p.0), y: .value("Feels like", p.1))
                            .foregroundStyle(.white)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 160)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(card, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Quick log buttons

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Log").font(.headline)
            HStack {
                Button("Log a drink") { store.logDrink() }.buttonStyle(.bordered)
                Button("I applied sunscreen") { store.logSunscreen() }.buttonStyle(.bordered)
            }
            if let d = store.lastDrink {
                Text("Last drink \(ago(d))").font(.caption).foregroundStyle(.secondary)
            }
            if let s = store.lastSunscreen {
                Text("Sunscreen applied \(ago(s))").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(card, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Alerts

    private var alertsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Alerts").font(.headline)
            if store.alerts.isEmpty {
                Text("No alerts yet.").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(store.alerts) { a in
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.title).font(.subheadline.bold())
                    Text(a.message).font(.subheadline)
                    Text(a.date, style: .time).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.purple.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(card, in: RoundedRectangle(cornerRadius: 16))
    }
}
