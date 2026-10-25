import Foundation
import Combine
import UserNotifications

enum LogKind: String, Codable {
    case water, sunscreen
}

struct LogEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date
    var kind: LogKind
    var ounces: Double   // only used for water
}

/// Stores water and sunscreen logs in a JSON file on the device (Documents/log.json)
/// and manages the opt-in daily water reminders.
final class LogStore: ObservableObject {
    @Published private(set) var entries: [LogEntry] = []
    @Published var permissionDenied = false

    @Published var dailyGoalOz: Double {
        didSet { UserDefaults.standard.set(dailyGoalOz, forKey: "waterGoalOz") }
    }
    @Published var remindersOn: Bool {
        didSet { UserDefaults.standard.set(remindersOn, forKey: "waterRemindersOn") }
    }
    @Published var reminderStartHour: Int {
        didSet { UserDefaults.standard.set(reminderStartHour, forKey: "reminderStart"); scheduleReminders() }
    }
    @Published var reminderEndHour: Int {
        didSet { UserDefaults.standard.set(reminderEndHour, forKey: "reminderEnd"); scheduleReminders() }
    }
    @Published var reminderEveryHours: Int {
        didSet { UserDefaults.standard.set(reminderEveryHours, forKey: "reminderEvery"); scheduleReminders() }
    }

    private let fileURL: URL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("log.json")

    init() {
        let d = UserDefaults.standard
        let goal = d.double(forKey: "waterGoalOz")
        dailyGoalOz = goal == 0 ? 64 : goal
        remindersOn = d.bool(forKey: "waterRemindersOn")
        reminderStartHour = d.object(forKey: "reminderStart") as? Int ?? 9
        reminderEndHour = d.object(forKey: "reminderEnd") as? Int ?? 19
        reminderEveryHours = d.object(forKey: "reminderEvery") as? Int ?? 2
        load()
        if remindersOn { scheduleReminders() }
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loaded = try? decoder.decode([LogEntry].self, from: data) {
            entries = loaded
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: Logging

    func addWater(oz: Double) {
        entries.append(LogEntry(date: Date(), kind: .water, ounces: oz))
        save()
    }

    func addSunscreen() {
        entries.append(LogEntry(date: Date(), kind: .sunscreen, ounces: 0))
        save()
    }

    func delete(_ entry: LogEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    // MARK: Queries

    var lastWater: Date? { entries.filter { $0.kind == .water }.map(\.date).max() }
    var lastSunscreen: Date? { entries.filter { $0.kind == .sunscreen }.map(\.date).max() }

    func entries(on day: Date, kind: LogKind) -> [LogEntry] {
        entries
            .filter { $0.kind == kind && Calendar.current.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date > $1.date }
    }

    func waterTotal(on day: Date) -> Double {
        entries(on: day, kind: .water).reduce(0) { $0 + $1.ounces }
    }

    /// Water totals for the last 7 days, oldest first.
    func last7Days() -> [(day: Date, oz: Double)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().map { offset in
            let day = cal.date(byAdding: .day, value: -offset, to: today)!
            return (day: day, oz: waterTotal(on: day))
        }
    }

    // MARK: Daily water reminders (opt-in)

    /// Turning on asks for notification permission first.
    func setReminders(_ on: Bool) {
        guard on else {
            remindersOn = false
            scheduleReminders()
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                self.permissionDenied = !granted
                self.remindersOn = granted
                self.scheduleReminders()
            }
        }
    }

    func scheduleReminders() {
        let on = remindersOn
        let start = reminderStartHour
        let end = reminderEndHour
        let every = max(1, reminderEveryHours)

        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let old = pending.map(\.identifier).filter { $0.hasPrefix("water-") }
            center.removePendingNotificationRequests(withIdentifiers: old)
            guard on, start <= end else { return }

            let messages = [
                "Time for some water.",
                "Quick water break?",
                "Stay ahead of thirst: grab a glass of water.",
                "Hydration check: have you had water recently?"
            ]
            for (i, hour) in stride(from: start, through: end, by: every).enumerated() {
                let content = UNMutableNotificationContent()
                content.title = "Drink water"
                content.body = messages[i % messages.count]
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: DateComponents(hour: hour, minute: 0), repeats: true)
                center.add(UNNotificationRequest(
                    identifier: "water-\(hour)", content: content, trigger: trigger))
            }
        }
    }
}
