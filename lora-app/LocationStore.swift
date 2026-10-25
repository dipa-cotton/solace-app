import Foundation
import CoreLocation
import Combine

enum LocationSource: String, CaseIterable, Identifiable {
    case sensor, phone

    var id: String { rawValue }
    var label: String { self == .sensor ? "Sensor GPS" : "Phone location" }
}

/// Decides which location the maps, area weather and cool-place search use.
/// The phone's location is opt-in: permission is only requested when the user picks it.
final class LocationStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var source: LocationSource {
        didSet {
            UserDefaults.standard.set(source.rawValue, forKey: "locationSource")
            if source == .phone { requestPhone() }
        }
    }
    @Published var phoneLocation: CLLocation?
    @Published var authorization: CLAuthorizationStatus = .notDetermined
    @Published var lastSensorFix: CLLocationCoordinate2D?
    /// Shown in the UI when phone location can't be used, so a failure is never silent.
    @Published var errorText: String?

    private let manager = CLLocationManager()

    override init() {
        let raw = UserDefaults.standard.string(forKey: "locationSource") ?? LocationSource.sensor.rawValue
        source = LocationSource(rawValue: raw) ?? .sensor
        super.init()

        let d = UserDefaults.standard
        if let lat = d.object(forKey: "sensorLat") as? Double,
           let lon = d.object(forKey: "sensorLon") as? Double {
            lastSensorFix = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorization = manager.authorizationStatus
        if source == .phone { requestPhone() }
    }

    /// The coordinate used for the heat map, backup weather and cool-place search.
    var coordinate: CLLocationCoordinate2D? {
        switch source {
        case .sensor: return lastSensorFix
        case .phone:  return phoneLocation?.coordinate
        }
    }

    /// iOS silently ignores location requests if this text is missing from the app's Info settings.
    var hasUsageKey: Bool {
        Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") != nil
    }

    /// True once phone location is both selected and allowed.
    var phoneLocationActive: Bool {
        source == .phone &&
        (authorization == .authorizedWhenInUse || authorization == .authorizedAlways)
    }

    /// Selects phone location (or retries if it's already selected).
    func usePhoneLocation() {
        if source == .phone {
            requestPhone()
        } else {
            source = .phone   // didSet requests permission
        }
    }

    var statusText: String {
        switch source {
        case .sensor:
            return lastSensorFix == nil
                ? "Waiting for a GPS fix from your sensor."
                : "Using the last GPS fix from your sensor."
        case .phone:
            switch authorization {
            case .denied, .restricted: return "Location access is off for this app."
            case .notDetermined:       return "Tap Allow to use your phone's location."
            default:                   return phoneLocation == nil
                ? "Getting your location..."
                : "Using your phone's location."
            }
        }
    }

    func noteSensorFix(_ r: Reading) {
        guard r.hasFix, abs(r.lat) > 0.0001 || abs(r.lon) > 0.0001 else { return }
        lastSensorFix = CLLocationCoordinate2D(latitude: r.lat, longitude: r.lon)
        UserDefaults.standard.set(r.lat, forKey: "sensorLat")
        UserDefaults.standard.set(r.lon, forKey: "sensorLon")
    }

    func requestPhone() {
        guard hasUsageKey else {
            errorText = "Location permission text is missing. In Xcode, add \"Privacy - Location When In Use Usage Description\" (NSLocationWhenInUseUsageDescription) in the target's Info tab, then rebuild."
            return
        }
        errorText = nil

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            if let cached = manager.location { phoneLocation = cached }   // instant, if available
            manager.requestLocation()
        default:
            break
        }
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        authorization = m.authorizationStatus
        if source == .phone { requestPhone() }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        phoneLocation = locations.last
        errorText = nil
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        // Keep any earlier location, but tell the user instead of failing silently.
        errorText = "Couldn't get your location (\(error.localizedDescription)). On the iOS Simulator, choose Features > Location > Custom Location."
    }
}
