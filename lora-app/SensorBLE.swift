import Foundation
import Combine
import CoreBluetooth

// MARK: - Model

struct Reading: Equatable, Identifiable, Codable {
    var id = UUID()
    let date: Date
    let tempC: Double?
    let humidity: Double?
    let pressureHpa: Double?
    let lux: Double?
    let uvMv: Double
    let satellites: Int
    let hasFix: Bool
    let lat: Double
    let lon: Double

    var uvIndex: Double { max(0, (uvMv - uvOffsetMillivolts) / uvMillivoltsPerIndex) }

    /// A usable reading has a plausible air temperature. Packets without one
    /// (for example when the AHT20/BMP280 isn't working) are not counted as valid.
    var isValid: Bool {
        guard let c = tempC, c > -40, c < 85 else { return false }
        if let h = humidity, h < 0 || h > 100 { return false }
        return true
    }

    /// Feels-like temperature in °F (heat index), if we have what we need.
    var feelsLikeF: Double? {
        guard let c = tempC else { return nil }
        let f = celsiusToF(c)
        guard let rh = humidity else { return f }
        return heatIndexF(tempF: f, humidity: rh)
    }
}

enum ConnectionState {
    case idle, bluetoothOff, unauthorized, scanning, connecting, connected

    var text: String {
        switch self {
        case .idle: return "Not connected"
        case .bluetoothOff: return "Bluetooth is off"
        case .unauthorized: return "Bluetooth permission denied (Settings > LoRaSafety)"
        case .scanning: return "Searching for sensor station..."
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        }
    }
}

// MARK: - Manager

final class SensorBLE: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let serviceUUID = CBUUID(string: "7A1F0001-5B3C-4E6A-9C1D-3B2F8E6D4A10")
    static let charUUID    = CBUUID(string: "7A1F0002-5B3C-4E6A-9C1D-3B2F8E6D4A10")
    static let packetSize  = 22

    @Published var state: ConnectionState = .idle
    @Published var latest: Reading?
    /// The last VALID reading (also restored from disk at launch). May be old: check freshness().
    @Published var lastKnown: Reading?
    /// True when the sensor is sending packets but without a usable temperature.
    @Published var packetProblem = false
    @Published var history: [Reading] = []
    @Published var deviceName: String?
    @Published var isDemo = false

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var lastHistoryDate = Date.distantPast
    private var demoTimer: Timer?
    private var demoStart = Date()
    private var lastCacheDate = Date.distantPast

    override init() {
        super.init()
        lastKnown = Self.loadCachedReading()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func rescan() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        startScan()
    }

    private func startScan() {
        guard central.state == .poweredOn else { return }
        state = .scanning
        central.scanForPeripherals(withServices: [Self.serviceUUID], options: nil)
    }

    // MARK: Central delegate

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn:    startScan()
        case .poweredOff:   state = .bluetoothOff
        case .unauthorized: state = .unauthorized
        default:            state = .idle
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        c.stopScan()
        peripheral = p
        p.delegate = self
        deviceName = p.name ?? "Sensor station"
        state = .connecting
        c.connect(p, options: nil)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        state = .connected
        p.discoverServices([Self.serviceUUID])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        peripheral = nil
        startScan()
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        peripheral = nil
        state = .idle
        startScan()   // keep trying to reconnect
    }

    // MARK: Peripheral delegate

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] where s.uuid == Self.serviceUUID {
            p.discoverCharacteristics([Self.charUUID], for: s)
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] where ch.uuid == Self.charUUID {
            p.setNotifyValue(true, for: ch)
            p.readValue(for: ch)
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard error == nil, let raw = ch.value, let reading = Self.parse(Data(raw)) else { return }
        DispatchQueue.main.async {
            if self.isDemo { return }   // demo is running; ignore real packets
            self.publish(reading, historyEvery: 10)
        }
    }

    private func publish(_ reading: Reading, historyEvery interval: TimeInterval) {
        latest = reading
        packetProblem = !reading.isValid
        guard reading.isValid else { return }   // invalid packets never count as "fresh"

        lastKnown = reading
        if !isDemo, reading.date.timeIntervalSince(lastCacheDate) >= 5 {
            lastCacheDate = reading.date
            Self.saveCachedReading(reading)
        }
        if reading.date.timeIntervalSince(lastHistoryDate) >= interval {
            lastHistoryDate = reading.date
            history.append(reading)
            if history.count > 360 { history.removeFirst() }   // ~1 hour
        }
    }

    // MARK: Demo (a single built-in scenario, off by default)

    /// "Hot Florida afternoon": 84 to 98 °F, humidity 55 to 75%, UV 3 to 9, over 90 seconds.
    func startDemo() {
        stopDemo()
        isDemo = true
        latest = nil
        lastKnown = nil
        history.removeAll()
        lastHistoryDate = .distantPast
        demoStart = Date()

        demoTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let p = min(Date().timeIntervalSince(self.demoStart) / 90.0, 1.0)
            let tempF = 84 + 14 * p
            let reading = Reading(
                date: Date(),
                tempC: (tempF - 32) * 5 / 9,
                humidity: 55 + 20 * p,
                pressureHpa: 1013,
                lux: 20000 + 70000 * p,
                uvMv: (3 + 6 * p) * 100,
                satellites: 8,
                hasFix: true,
                lat: 27.3364,
                lon: -82.5307
            )
            self.publish(reading, historyEvery: 1)
        }
    }

    func stopDemo() {
        demoTimer?.invalidate()
        demoTimer = nil
        if isDemo {
            isDemo = false
            latest = nil
            lastKnown = Self.loadCachedReading()   // back to the last REAL reading
            history.removeAll()
            lastHistoryDate = .distantPast
        }
    }

    // MARK: Freshness (a silent or disconnected sensor is never "safe")

    /// A reading older than this many seconds is treated as stale.
    static let staleAfter: TimeInterval = 15

    enum Freshness { case live, stale, none }

    func freshness(at now: Date = Date()) -> Freshness {
        guard let r = lastKnown else { return .none }
        if now.timeIntervalSince(r.date) > Self.staleAfter { return .stale }
        if !isDemo && state != .connected { return .stale }
        return .live
    }

    // MARK: Cache of the last valid reading (survives app restarts)

    private static let cacheKey = "lastValidReading"

    private static func saveCachedReading(_ r: Reading) {
        if let data = try? JSONEncoder().encode(r) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private static func loadCachedReading() -> Reading? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(Reading.self, from: data)
    }

    // MARK: Packet parsing (matches the firmware's 22-byte struct, little-endian)

    private static func parse(_ d: Data) -> Reading? {
        guard d.count >= packetSize else { return nil }
        func i16(_ o: Int) -> Int16 { d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: Int16.self) } }
        func u16(_ o: Int) -> UInt16 { d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt16.self) } }
        func u32(_ o: Int) -> UInt32 { d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: UInt32.self) } }
        func i32(_ o: Int) -> Int32 { d.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: o, as: Int32.self) } }

        let flags = d[13]
        let hasAHT = flags & 0x01 != 0
        let hasBMP = flags & 0x02 != 0
        let hasVEML = flags & 0x04 != 0
        let hasFix = flags & 0x08 != 0

        return Reading(
            date: Date(),
            tempC: (hasAHT || hasBMP) ? Double(i16(0)) / 100.0 : nil,
            humidity: hasAHT ? Double(u16(2)) / 100.0 : nil,
            pressureHpa: hasBMP ? Double(u16(4)) / 10.0 : nil,
            lux: hasVEML ? Double(u32(6)) : nil,
            uvMv: Double(u16(10)),
            satellites: Int(d[12]),
            hasFix: hasFix,
            lat: Double(i32(14)) / 1e6,
            lon: Double(i32(18)) / 1e6
        )
    }
}
