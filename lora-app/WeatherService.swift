import Foundation
import Combine
import CoreLocation

// Backup weather and heat map data come from Open-Meteo (https://open-meteo.com),
// which needs no API key. The free tier is for non-commercial use.

struct AreaWeather: Codable, Equatable {
    let tempF: Double
    let humidity: Double
    let uvIndex: Double
    let fetched: Date
    let lat: Double
    let lon: Double

    var feelsLikeF: Double { heatIndexF(tempF: tempF, humidity: humidity) }
}

struct HeatPoint: Codable, Identifiable, Equatable {
    var id = UUID()
    let lat: Double
    let lon: Double
    let feelsLikeF: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

struct HeatGrid: Codable, Equatable {
    let points: [HeatPoint]
    let fetched: Date
    let centerLat: Double
    let centerLon: Double
}

private struct OMCurrent: Decodable {
    let temperature_2m: Double?
    let relative_humidity_2m: Double?
    let uv_index: Double?
}

private struct OMResponse: Decodable {
    let current: OMCurrent?
}

final class WeatherService: ObservableObject {
    @Published var area: AreaWeather?
    @Published var grid: HeatGrid?
    @Published var areaError: String?
    @Published var gridError: String?
    @Published var loadingGrid = false

    private var lastAreaAttempt = Date.distantPast

    init() {
        // Show the last saved data immediately, even with no internet.
        area = Self.load(AreaWeather.self, key: "cachedArea")
        grid = Self.load(HeatGrid.self, key: "cachedGrid")
    }

    // MARK: Area weather (backup when the sensor is down)

    func refreshArea(lat: Double, lon: Double, force: Bool = false) async {
        if !force && Date().timeIntervalSince(lastAreaAttempt) < 600 { return }
        lastAreaAttempt = Date()
        guard let url = makeURL(lats: [lat], lons: [lon]) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(OMResponse.self, from: data)
            guard let t = response.current?.temperature_2m,
                  let h = response.current?.relative_humidity_2m else {
                throw URLError(.cannotParseResponse)
            }
            let value = AreaWeather(tempF: t, humidity: h,
                                    uvIndex: response.current?.uv_index ?? 0,
                                    fetched: Date(), lat: lat, lon: lon)
            Self.save(value, key: "cachedArea")
            await MainActor.run {
                self.area = value
                self.areaError = nil
            }
        } catch {
            await MainActor.run {
                self.areaError = "Couldn't reach the weather service."
            }
        }
    }

    // MARK: Heat map grid

    /// Fetches a 5x5 grid of points (about 9 km each way) around the center.
    func refreshGrid(lat: Double, lon: Double) async {
        await MainActor.run { self.loadingGrid = true }

        let step = 0.04   // degrees latitude, about 4.4 km
        let lonStep = step / max(cos(lat * .pi / 180), 0.2)
        var lats: [Double] = []
        var lons: [Double] = []
        for i in -2...2 {
            for j in -2...2 {
                lats.append(lat + Double(i) * step)
                lons.append(lon + Double(j) * lonStep)
            }
        }

        guard let url = makeURL(lats: lats, lons: lons) else {
            await MainActor.run { self.loadingGrid = false }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let responses = try JSONDecoder().decode([OMResponse].self, from: data)
            var points: [HeatPoint] = []
            for (index, r) in responses.enumerated() where index < lats.count {
                guard let t = r.current?.temperature_2m,
                      let h = r.current?.relative_humidity_2m else { continue }
                points.append(HeatPoint(lat: lats[index], lon: lons[index],
                                        feelsLikeF: heatIndexF(tempF: t, humidity: h)))
            }
            guard !points.isEmpty else { throw URLError(.cannotParseResponse) }

            let newGrid = HeatGrid(points: points, fetched: Date(), centerLat: lat, centerLon: lon)
            Self.save(newGrid, key: "cachedGrid")
            await MainActor.run {
                self.grid = newGrid
                self.gridError = nil
                self.loadingGrid = false
            }
        } catch {
            await MainActor.run {
                self.gridError = "Couldn't load the heat map. Showing the last saved one, if any."
                self.loadingGrid = false
            }
        }
    }

    // MARK: Helpers

    private func makeURL(lats: [Double], lons: [Double]) -> URL? {
        let latString = lats.map { String(format: "%.4f", $0) }.joined(separator: ",")
        let lonString = lons.map { String(format: "%.4f", $0) }.joined(separator: ",")
        let text = "https://api.open-meteo.com/v1/forecast"
            + "?latitude=\(latString)&longitude=\(lonString)"
            + "&current=temperature_2m,relative_humidity_2m,uv_index"
            + "&temperature_unit=fahrenheit"
        return URL(string: text)
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
