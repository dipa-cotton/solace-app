import SwiftUI
import Charts

/// Two tabs: the live dashboard and the water/sunscreen tracker.
struct RootView: View {
    @EnvironmentObject var store: SafetyStore

    var body: some View {
        TabView(selection: $store.selectedTab) {
            ContentView()
                .tabItem { Label("Dashboard", systemImage: "thermometer.sun.fill") }
                .tag(AppTab.dashboard)
            SafetyHubView()
                .tabItem { Label("Safety Hub", systemImage: "cross.case.fill") }
                .tag(AppTab.safety)
            TrackerView()
                .tabItem { Label("Tracker", systemImage: "drop.fill") }
                .tag(AppTab.tracker)
        }
    }
}

struct TrackerView: View {
    @EnvironmentObject var store: SafetyStore

    var body: some View {
        TrackerContent(log: store.log)
    }
}

private struct TrackerContent: View {
    @ObservedObject var log: LogStore

    private let bg = Color(red: 0.04, green: 0.06, blue: 0.10)
    private let card = Color(red: 0.09, green: 0.12, blue: 0.17)

    private var today: Double { log.waterTotal(on: Date()) }
    private var progress: Double { min(today / max(log.dailyGoalOz, 1), 1) }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Text("Tracker").font(.title.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    waterCard
                    weekCard
                    sunscreenCard
                    remindersCard
                }
                .padding()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Water

    private var waterCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Water today").font(.headline)

            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.cyan, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(Int(today.rounded()))").font(.system(size: 34, weight: .heavy))
                        Text("of \(Int(log.dailyGoalOz)) oz").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 130, height: 130)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach([8.0, 12.0, 16.0, 24.0], id: \.self) { oz in
                        Button("+\(Int(oz)) oz") { log.addWater(oz: oz) }
                            .buttonStyle(.bordered)
                            .tint(.cyan)
                    }
                }
            }

            Stepper(value: $log.dailyGoalOz, in: 16...160, step: 8) {
                Text("Daily goal: \(Int(log.dailyGoalOz)) oz").font(.subheadline)
            }

            let todays = log.entries(on: Date(), kind: .water)
            if todays.isEmpty {
                Text("Nothing logged yet today.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(todays) { e in
                HStack {
                    Image(systemName: "drop.fill").foregroundStyle(.cyan)
                    Text("\(Int(e.ounces)) oz")
                    Spacer()
                    Text(e.date, style: .time).foregroundStyle(.secondary)
                    Button { log.delete(e) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .tint(.red)
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(card, in: RoundedRectangle(cornerRadius: 16))
    }

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 7 days").font(.headline)
            Chart {
                ForEach(log.last7Days(), id: \.day) { d in
                    BarMark(x: .value("Day", d.day, unit: .day),
                            y: .value("Ounces", d.oz))
                        .foregroundStyle(d.oz >= log.dailyGoalOz ? Color.cyan : Color.cyan.opacity(0.45))
                }
                RuleMark(y: .value("Goal", log.dailyGoalOz))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .frame(height: 150)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(card, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Sunscreen

    private var sunscreenCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sunscreen").font(.headline)

            Button { log.addSunscreen() } label: {
                Label("I applied sunscreen", systemImage: "sun.max.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text(sunscreenStatus).font(.subheadline).foregroundStyle(.secondary)
            }

            let todays = log.entries(on: Date(), kind: .sunscreen)
            ForEach(todays) { e in
                HStack {
                    Image(systemName: "sun.max.fill").foregroundStyle(.orange)
                    Text("Applied")
                    Spacer()
                    Text(e.date, style: .time).foregroundStyle(.secondary)
                    Button { log.delete(e) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .tint(.red)
                }
                .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(card, in: RoundedRectangle(cornerRadius: 16))
    }

    private var sunscreenStatus: String {
        guard let last = log.lastSunscreen else { return "No sunscreen logged yet." }
        let minutes = Int(Date().timeIntervalSince(last) / 60)
        if minutes >= 120 { return "Applied \(minutes / 60) h ago. Time to reapply." }
        return "Applied \(minutes) min ago. Reapply in \(120 - minutes) min."
    }

    // MARK: Reminders

    private var remindersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily water reminders").font(.headline)

            Toggle("Remind me to drink water", isOn: Binding(
                get: { log.remindersOn },
                set: { log.setReminders($0) }))

            if log.remindersOn {
                Stepper(value: $log.reminderStartHour, in: 5...20) {
                    Text("From \(hourText(log.reminderStartHour))").font(.subheadline)
                }
                Stepper(value: $log.reminderEndHour, in: 6...23) {
                    Text("Until \(hourText(log.reminderEndHour))").font(.subheadline)
                }
                Stepper(value: $log.reminderEveryHours, in: 1...6) {
                    Text("Every \(log.reminderEveryHours) hour\(log.reminderEveryHours == 1 ? "" : "s")")
                        .font(.subheadline)
                }
                Text("Reminders repeat every day at these times. They're off until you turn this on.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if log.permissionDenied {
                Text("Notifications are blocked for this app.").font(.caption).foregroundStyle(.orange)
                if let url = URL(string: "app-settings:") {
                    Link("Open Settings", destination: url).font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func hourText(_ h: Int) -> String {
        let d = Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date()) ?? Date()
        return d.formatted(date: .omitted, time: .shortened)
    }
}
