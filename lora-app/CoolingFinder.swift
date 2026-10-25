import Foundation
import MapKit
import Combine

struct CoolPlace: Identifiable {
    let id = UUID()
    let name: String
    let category: String
    let distanceMeters: Double
    let mapItem: MKMapItem
}

/// The closest place found, in a form that can go into a notification.
struct NearestPlace {
    let name: String
    let category: String
    let distanceMeters: Double
    let latitude: Double
    let longitude: Double
    let fromSavedList: Bool

    func sentence(useKm: Bool) -> String {
        let d = useKm
            ? String(format: "%.1f km", distanceMeters / 1000)
            : String(format: "%.1f mi", distanceMeters / 1609.34)
        var s = "Closest cool place: \(name) (\(category.lowercased()), \(d) away)."
        if fromSavedList { s += " From an earlier search, so call ahead if you can." }
        return s
    }
}

private struct SavedPlace: Codable {
    let name: String
    let category: String
    let lat: Double
    let lon: Double
}

final class CoolingFinder: ObservableObject {
    @Published var places: [CoolPlace] = []
    @Published var isSearching = false
    @Published var message: String?

    private static let queries: [(String, String)] = [
        ("cooling center", "Cooling center"),
        ("library", "Library"),
        ("shopping mall", "Mall"),
        ("supermarket", "Grocery store"),
        ("pharmacy", "Pharmacy"),
        ("community center", "Community center")
    ]
    private static let savedKey = "savedCoolPlaces"

    // MARK: Safety Hub search

    func search(near coordinate: CLLocationCoordinate2D) async {
        await MainActor.run {
            self.isSearching = true
            self.message = nil
        }

        let result = await Self.searchAll(near: coordinate)
        let top = Array(result.places.prefix(12))
        if !top.isEmpty { Self.savePlaces(top) }
        let failed = result.failures

        await MainActor.run {
            self.places = top
            self.isSearching = false
            if top.isEmpty {
                if failed == Self.queries.count {
                    self.message = "Couldn't search. This needs an internet connection. If you're offline, go to the nearest air-conditioned building you know."
                } else {
                    self.message = "No places found within 10 km. In the US you can call 211 to ask about cooling centers."
                }
            }
        }
    }

    // MARK: Used by notifications

    /// The closest indoor place. Falls back to the last saved list if the search fails (offline).
    static func nearest(to coordinate: CLLocationCoordinate2D) async -> NearestPlace? {
        let result = await searchAll(near: coordinate)
        if let p = result.places.first {
            savePlaces(Array(result.places.prefix(12)))
            let c = p.mapItem.placemark.coordinate
            return NearestPlace(name: p.name, category: p.category,
                                distanceMeters: p.distanceMeters,
                                latitude: c.latitude, longitude: c.longitude,
                                fromSavedList: false)
        }
        guard result.failures == queries.count else { return nil }
        return savedNearest(to: coordinate)
    }

    // MARK: Searching

    static func searchAll(near coordinate: CLLocationCoordinate2D) async
        -> (places: [CoolPlace], failures: Int) {

        let batches = await withTaskGroup(of: [CoolPlace]?.self) { group -> [[CoolPlace]?] in
            for (query, label) in queries {
                group.addTask { await searchOne(query: query, label: label, coordinate: coordinate) }
            }
            var all: [[CoolPlace]?] = []
            for await batch in group { all.append(batch) }
            return all
        }

        var found: [CoolPlace] = []
        var failures = 0
        for batch in batches {
            guard let items = batch else { failures += 1; continue }
            for place in items {
                let isDuplicate = found.contains {
                    $0.name == place.name && abs($0.distanceMeters - place.distanceMeters) < 50
                }
                if !isDuplicate { found.append(place) }
            }
        }
        found.sort { $0.distanceMeters < $1.distanceMeters }
        return (found, failures)
    }

    /// nil means the search failed; an empty array means it worked but found nothing.
    private static func searchOne(query: String, label: String,
                                  coordinate: CLLocationCoordinate2D) async -> [CoolPlace]? {
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(center: coordinate,
                                            latitudinalMeters: 10000,
                                            longitudinalMeters: 10000)
        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.compactMap { item in
                let c = item.placemark.coordinate
                let d = origin.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
                guard d <= 10000 else { return nil }
                return CoolPlace(name: item.name ?? label, category: label,
                                 distanceMeters: d, mapItem: item)
            }
        } catch {
            return nil
        }
    }

    // MARK: Saved list (so an offline alert can still name a place)

    private static func savePlaces(_ places: [CoolPlace]) {
        let saved = places.map {
            let c = $0.mapItem.placemark.coordinate
            return SavedPlace(name: $0.name, category: $0.category, lat: c.latitude, lon: c.longitude)
        }
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: savedKey)
        }
    }

    private static func savedNearest(to coordinate: CLLocationCoordinate2D) -> NearestPlace? {
        guard let data = UserDefaults.standard.data(forKey: savedKey),
              let saved = try? JSONDecoder().decode([SavedPlace].self, from: data) else { return nil }
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return saved
            .map { ($0, origin.distance(from: CLLocation(latitude: $0.lat, longitude: $0.lon))) }
            .filter { $0.1 <= 10000 }
            .min { $0.1 < $1.1 }
            .map { NearestPlace(name: $0.0.name, category: $0.0.category,
                                distanceMeters: $0.1,
                                latitude: $0.0.lat, longitude: $0.0.lon,
                                fromSavedList: true) }
    }
}
