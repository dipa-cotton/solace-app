import Foundation
import Combine
import UserNotifications
import CoreLocation
import UIKit

enum AppTab: Hashable { case dashboard, safety, tracker }

struct AlertItem: Identifiable {
    let id = UUID()
    let date: Date
    let title: String
    let message: String
}

/// Lets notifications show as banners while the app is open, and opens directions when tapped.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        // While the app is open, the in-app timer handles the offline alert itself.
        if notification.request.identifier == "sensor-offline-watchdog" {
            completionHandler([])
            return
        }
        completionHandler([.banner, .sound])
    }

    /// Tapping a "go inside" notification opens directions to the suggested place.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let lat = info["lat"] as? Double, let lon = info["lon"] as? Double,
           let url = URL(string: "http://maps.apple.com/?daddr=\(lat),\(lon)&dirflg=d") {
            DispatchQueue.main.async { UIApplication.shared.open(url) }
        }
        completionHandler()
    }
}

final class SafetyStore: ObservableObject {
    let ble = SensorBLE()

    @Published var alerts: [AlertItem] = []
    let log = LogStore()
    var lastDrink: Date? { log.lastWater }
    var lastSunscreen: Date? { log.lastSunscreen }

    let location = LocationStore()
    let weather = WeatherService()
    @Published var selectedTab: AppTab = .dashboard
    /// Incremented by the dashboard's "Cool place" button; the Safety Hub runs a search when it changes.
    @Published var coolSearchRequests = 0

    /// Feels-like temperature (°F) that triggers a notification. Saved between launches.
    @Published var thresholdF: Double = {
        let saved = UserDefaults.standard.double(forKey: "thresholdF")
        return saved == 0 ? 90 : saved
    }() {
        didSet { UserDefaults.standard.set(thresholdF, forKey: "thresholdF") }
    }

    private static let watchdogID = "sensor-offline-watchdog"

    private let notificationDelegate = NotificationDelegate()
    private var staleTimer: Timer?
    private var sawLive = false
    private var offlineAlertSent = false
    private var aboveThreshold = false
    private var lastThresholdAlert = Date.distantPast
    private var cancellables = Set<AnyCancellable>()
    private var lastHeatLevel: HeatLevel = .safe
    private var lastUVLevel: UVLevel = .low
    private var lastHydrationAlert = Date.distantPast
    private var lastSunscreenAlert = Date.distantPast

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Re-publish changes so views observing the store refresh too.
        ble.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        log.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        location.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        weather.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Remember the sensor's last GPS fix (never from demo data).
        ble.$lastKnown
            .compactMap { $0 }
            .sink { [weak self] reading in
                guard let self, !self.ble.isDemo else { return }
                self.location.noteSensorFix(reading)
            }
            .store(in: &cancellables)

        staleTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.tick()
        }

        ble.$latest
            .compactMap { $0 }
            .sink { [weak self] reading in self?.evaluate(reading) }
            .store(in: &cancellables)
    }

    func logDrink() { log.addWater(oz: 8) }
    func logSunscreen() { log.addSunscreen() }

    // MARK: Offline watchdog (works while the app is suspended)

    /// A "dead man's switch": every valid reading pushes this notification further into
    /// the future, so it only fires if readings stop.
    private func armOfflineWatchdog() {
        let content = UNMutableNotificationContent()
        content.title = "Sensor offline"
        content.body = "No sensor reading for a couple of minutes. Don't assume conditions are safe. Check the sensor."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: SensorBLE.offlineAlertAfter + 10, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: Self.watchdogID, content: content, trigger: trigger))
    }

    private func disarmOfflineWatchdog() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.watchdogID])
    }

    // MARK: Sensor health (runs every 10 seconds)

    private func tick() {
        let freshness = ble.freshness()

        if freshness == .live {
            sawLive = true
            offlineAlertSent = false
        } else if !ble.isDemo, sawLive, !offlineAlertSent,
                  let last = ble.lastKnown,
                  Date().timeIntervalSince(last.date) > SensorBLE.offlineAlertAfter {
            // The sensor was working this session and has now been silent for a while.
            offlineAlertSent = true
            disarmOfflineWatchdog()
            let time = last.date.formatted(date: .omitted, time: .shortened)
            raise("Sensor offline",
                  "No reading since \(time). Don't assume conditions are safe. Check the sensor, or open the app for area weather.")
        }

        // Keep area weather fresh (throttled to every ~2 min inside the service).
        if let c = location.coordinate {
            let service = weather
            Task { await service.refreshArea(lat: c.latitude, lon: c.longitude) }
        }
    }

    // MARK: Alert rules

    private func evaluate(_ r: Reading) {
        let now = Date()

        if ble.isDemo { disarmOfflineWatchdog() } else if r.isValid { armOfflineWatchdog() }

        if let f = r.feelsLikeF {
            // Your temperature limit: notify when crossed, then remind every 15 min while above.
            if f >= thresholdF {
                if !aboveThreshold || now.timeIntervalSince(lastThresholdAlert) >= 15 * 60 {
                    lastThresholdAlert = now
                    raiseGoInside("Temperature limit exceeded",
                                  "Feels like \(Int(f.rounded()))°F, above your \(Int(thresholdF.rounded()))°F limit. Head indoors if you can, and drink water.")
                }
                aboveThreshold = true
            } else if f < thresholdF - 2 {
                aboveThreshold = false   // re-arm once it drops a couple of degrees below
            }

            let level = HeatLevel(feelsLikeF: f)
            if level > lastHeatLevel, level >= .danger {
                raiseGoInside("\(level.title): feels like \(Int(f.rounded()))°F", level.advice)
            }
            lastHeatLevel = level

            // Hydration reminders: every 20 min at Danger+, every 45 min at Extreme Caution
            let interval: TimeInterval? = level >= .danger ? 20 * 60 : (level == .extremeCaution ? 45 * 60 : nil)
            if let interval,
               now.timeIntervalSince(lastHydrationAlert) >= interval,
               now.timeIntervalSince(lastDrink ?? .distantPast) >= interval {
                lastHydrationAlert = now
                raise("Hydration reminder", "Stay ahead of thirst: grab some water.")
            }
        }

        let uvLevel = UVLevel(index: r.uvIndex)
        if r.uvIndex >= 8, lastUVLevel != uvLevel, uvLevel == .veryHigh || uvLevel == .extreme {
            raise("UV index \(String(format: "%.1f", r.uvIndex))", "Very strong UV. Cover up, seek shade, and protect your skin.")
        }
        lastUVLevel = uvLevel

        if r.uvIndex >= 3,
           now.timeIntervalSince(lastSunscreenAlert) >= 120 * 60,
           now.timeIntervalSince(lastSunscreen ?? .distantPast) >= 120 * 60 {
            lastSunscreenAlert = now
            raise("Sunscreen reminder", "UV is \(String(format: "%.1f", r.uvIndex)). Apply or reapply sunscreen.")
        }
    }

    // MARK: Raising alerts

    /// Like raise(), but looks up the closest indoor place first and adds it to the message.
    private func raiseGoInside(_ title: String, _ message: String) {
        guard !ble.isDemo, let c = location.coordinate else { raise(title, message); return }
        let useKm = UserDefaults.standard.bool(forKey: "useCelsius")   // same switch the UI uses for km/mi
        Task { [weak self] in
            let place = await CoolingFinder.nearest(to: c)
            await MainActor.run {
                guard let self else { return }
                if let place {
                    self.raise(title, "\(message) \(place.sentence(useKm: useKm))", place: place)
                } else {
                    self.raise(title, message)
                }
            }
        }
    }

    private func raise(_ title: String, _ message: String, place: NearestPlace? = nil) {
        let demo = ble.isDemo
        let shownTitle = demo ? "Demo: \(title)" : title
        DispatchQueue.main.async {
            self.alerts.insert(AlertItem(date: Date(), title: shownTitle, message: message), at: 0)
            if self.alerts.count > 50 { self.alerts.removeLast() }
        }
        if demo { return }   // demo alerts stay inside the app

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default
        if let place {
            content.userInfo = ["lat": place.latitude, "lon": place.longitude, "name": place.name]
        }
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }
}
