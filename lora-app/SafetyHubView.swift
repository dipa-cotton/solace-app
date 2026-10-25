import SwiftUI
import MapKit

private let hubBackground = Color(red: 0.04, green: 0.06, blue: 0.10)
private let hubCard = Color(red: 0.09, green: 0.12, blue: 0.17)

struct SafetyHubView: View {
    @EnvironmentObject var store: SafetyStore
    @StateObject private var finder = CoolingFinder()
    @AppStorage("useCelsius") private var useCelsius = false
    @State private var handledCoolRequests = 0

    var body: some View {
        ZStack {
            hubBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Text("Safety Hub")
                        .font(.title.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Compact prompt; hides itself once phone location is on.
                    LocationBanner(location: store.location)

                    emergencyCard                                   // always first
                    LocationCard(location: store.location)
                    coolPlacesCard
                    HeatMapCard(location: store.location, weather: store.weather)
                    otherGuidanceCard
                    footerCard
                }
                .padding()
            }
        }
        .preferredColorScheme(.dark)
        .task(id: store.coolSearchRequests) { await handleCoolRequest() }
    }

    // MARK: Heat stroke emergency (top of the screen)

    private var emergencyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "cross.case.fill").font(.title).foregroundStyle(.red)
                Text("Someone may have heat stroke?").font(.title2.bold())
            }
            Text("Heat stroke can be fatal. Act right away. Don't wait to see if they get better.")
                .font(.subheadline)

            Link(destination: URL(string: "tel://911")!) {
                Label("Call 911 now", systemImage: "phone.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            Text("Outside the US, call your local emergency number.")
                .font(.caption).foregroundStyle(.secondary)

            Text("Signs").font(.headline)
            ForEach(SafetyContent.heatStrokeSigns, id: \.self) { bullet($0) }
            Text("If you're unsure, treat it as heat stroke.").font(.subheadline.bold())

            Text("What to do, in order").font(.headline)
            ForEach(Array(SafetyContent.heatStrokeSteps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.headline)
                        .frame(width: 28, height: 28)
                        .background(Color.red, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title).font(.subheadline.bold())
                        Text(step.detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }

            Text("Don't").font(.headline)
            ForEach(SafetyContent.heatStrokeDonts, id: \.self) { bullet($0) }

            Label("This section is built into the app and works without internet.",
                  systemImage: "wifi.slash")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.red.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.6), lineWidth: 1))
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text).font(.subheadline)
        }
    }

    // MARK: Cool places

    private var coolPlacesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Find a cool, indoor place").font(.headline)
            Text("Searches near the location chosen above for cooling centers, libraries, malls, grocery stores and pharmacies. Hours and air conditioning aren't guaranteed, so call ahead if you can.")
                .font(.caption).foregroundStyle(.secondary)

            Button {
                Task { await searchCool() }
            } label: {
                Label(finder.isSearching ? "Searching..." : "Find cool places near me",
                      systemImage: "snowflake")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .disabled(finder.isSearching)

            if let message = finder.message {
                Text(message).font(.caption).foregroundStyle(.orange)
            }

            ForEach(finder.places) { place in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).font(.subheadline.bold())
                        Text("\(place.category) · \(distanceText(place.distanceMeters))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Directions") {
                        place.mapItem.openInMaps(launchOptions: [
                            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
                        ])
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(hubCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private func distanceText(_ meters: Double) -> String {
        useCelsius
            ? String(format: "%.1f km", meters / 1000)
            : String(format: "%.1f mi", meters / 1609.34)
    }

    private func searchCool() async {
        guard let c = store.location.coordinate else {
            finder.message = "Choose a location first (see the Location card above)."
            return
        }
        await finder.search(near: c)
    }

    /// Runs automatically when the dashboard's "Cool place" button is tapped.
    private func handleCoolRequest() async {
        guard store.coolSearchRequests > handledCoolRequests else { return }
        handledCoolRequests = store.coolSearchRequests
        await searchCool()
    }

    // MARK: Other guidance

    private var otherGuidanceCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            DisclosureGroup("Heat exhaustion: signs and what to do") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Signs").font(.subheadline.bold())
                    ForEach(SafetyContent.heatExhaustionSigns, id: \.self) { bullet($0) }
                    Text("What to do").font(.subheadline.bold()).padding(.top, 4)
                    ForEach(SafetyContent.heatExhaustionSteps, id: \.self) { bullet($0) }
                }
                .padding(.top, 6)
            }
            .padding(.vertical, 6)

            Divider()

            DisclosureGroup("Prevention tips") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(SafetyContent.preventionTips, id: \.self) { bullet($0) }
                }
                .padding(.top, 6)
            }
            .padding(.vertical, 6)
        }
        .padding()
        .background(hubCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private var footerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(SafetyContent.disclaimer).font(.caption).foregroundStyle(.secondary)
            Text("First-aid text works offline. The heat map, area weather and place search need internet. Weather data from Open-Meteo.com.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(hubCard, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Top banner: "Use your phone's location"

private struct LocationBanner: View {
    @ObservedObject var location: LocationStore

    private var isBlocked: Bool {
        location.authorization == .denied || location.authorization == .restricted
    }

    var body: some View {
        // Hidden once phone location is on, or when the sensor already has a GPS fix.
        if !location.phoneLocationActive &&
            !(location.source == .sensor && location.lastSensorFix != nil) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "location.fill").foregroundStyle(.blue)
                    Text("Use your phone's location for the heat map, backup weather and cool places.")
                        .font(.subheadline)
                }

                if isBlocked, location.source == .phone {
                    Text("Location is off for this app.").font(.caption).foregroundStyle(.orange)
                    if let url = URL(string: "app-settings:") {
                        Link("Open Settings to allow it", destination: url)
                            .font(.subheadline.bold())
                    }
                } else {
                    Button {
                        location.usePhoneLocation()
                    } label: {
                        Label("Use my phone's location", systemImage: "location")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let error = location.errorText {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.blue.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.blue.opacity(0.5), lineWidth: 1))
        }
    }
}

// MARK: - Location chooser

private struct LocationCard: View {
    @ObservedObject var location: LocationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Location for maps and backup weather").font(.headline)

            Picker("Source", selection: $location.source) {
                ForEach(LocationSource.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            Text(location.statusText).font(.caption).foregroundStyle(.secondary)

            if let error = location.errorText {
                Text(error).font(.caption).foregroundStyle(.orange)
                if location.source == .phone {
                    Button("Try again") { location.requestPhone() }
                        .buttonStyle(.bordered)
                }
            }

            if location.source == .sensor && location.lastSensorFix == nil {
                Text("Your sensor doesn't have a GPS fix yet. You can use your phone's location instead.")
                    .font(.caption).foregroundStyle(.orange)
                Button("Use my phone's location") { location.usePhoneLocation() }
                    .buttonStyle(.bordered)
            }

            if location.source == .phone {
                switch location.authorization {
                case .notDetermined:
                    Button("Allow location") { location.requestPhone() }
                        .buttonStyle(.borderedProminent)
                case .denied, .restricted:
                    if let url = URL(string: "app-settings:") {
                        Link("Open Settings to allow location", destination: url).font(.caption)
                    }
                default:
                    EmptyView()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(hubCard, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Heat map

private struct HeatMapCard: View {
    @ObservedObject var location: LocationStore
    @ObservedObject var weather: WeatherService

    private var coordinateKey: String {
        location.coordinate.map { String(format: "%.2f,%.2f", $0.latitude, $0.longitude) } ?? "none"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Heat map").font(.headline)

            if let grid = weather.grid {
                mapView(grid)
                legend
                summary(grid)
            } else {
                Text(location.coordinate == nil
                     ? "Choose a location above to see a heat map around you."
                     : "Loading the heat map...")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            if let error = weather.gridError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }

            HStack {
                Button("Refresh heat map") { Task { await load(force: true) } }
                    .buttonStyle(.bordered)
                    .disabled(weather.loadingGrid || location.coordinate == nil)
                if weather.loadingGrid { ProgressView() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(hubCard, in: RoundedRectangle(cornerRadius: 16))
        .task(id: coordinateKey) { await load(force: false) }
    }

    private func mapView(_ grid: HeatGrid) -> some View {
        let center = CLLocationCoordinate2D(latitude: grid.centerLat, longitude: grid.centerLon)
        return Map(initialPosition: .region(MKCoordinateRegion(
            center: center, latitudinalMeters: 16000, longitudinalMeters: 16000))) {
            ForEach(grid.points) { point in
                MapCircle(center: point.coordinate, radius: 2600)
                    .foregroundStyle(HeatLevel(feelsLikeF: point.feelsLikeF).color.opacity(0.45))
            }
            if let c = location.coordinate {
                Annotation("You", coordinate: c) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                }
            }
        }
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .id(grid.fetched)
    }

    private var legend: some View {
        let items: [(HeatLevel, String)] = [
            (.safe, "<80"), (.caution, "80-89"), (.extremeCaution, "90-102"),
            (.danger, "103-124"), (.extremeDanger, "125+")
        ]
        return HStack(spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 4) {
                    Circle().fill(item.0.color).frame(width: 10, height: 10)
                    Text(item.1).font(.caption2)
                }
            }
            Text("feels-like °F").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func summary(_ grid: HeatGrid) -> some View {
        let values = grid.points.map(\.feelsLikeF)
        let hottest = Int((values.max() ?? 0).rounded())
        let coolest = Int((values.min() ?? 0).rounded())
        return VStack(alignment: .leading, spacing: 2) {
            Text("Feels-like range nearby: \(coolest)°F to \(hottest)°F")
                .font(.subheadline)
            Text("Updated \(grid.fetched.formatted(date: .abbreviated, time: .shortened)). Based on weather-model data for roughly 4 km areas, so it shows regional differences, not individual streets or shade. Your exact spot can be hotter.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func load(force: Bool) async {
        guard let c = location.coordinate else { return }
        if !force, let g = weather.grid,
           Date().timeIntervalSince(g.fetched) < 600 {
            let moved = CLLocation(latitude: g.centerLat, longitude: g.centerLon)
                .distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            if moved < 3000 { return }
        }
        await weather.refreshGrid(lat: c.latitude, lon: c.longitude)
    }
}
