import Charts
import SwiftUI

struct BatteryPane: View {
    @State private var deviceState = DeviceState.shared
    @State private var config = ConfigStore.shared

    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 20) {
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: CGFloat(deviceState.batteryLevel ?? 0) / 100)
                            .stroke(batteryColor.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: deviceState.batteryCharging ? "bolt.fill" : "computermouse.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(deviceState.batteryLevel == nil ? Color.secondary : batteryColor)
                    }
                    .frame(width: 76, height: 76)
                    .animation(.easeOut(duration: 0.6), value: deviceState.batteryLevel)

                    VStack(alignment: .leading, spacing: 4) {
                        if let level = deviceState.batteryLevel {
                            Text("\(level)%")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Label(
                                deviceState.batteryCharging
                                    ? String(localized: "Charging")
                                    : String(localized: "Discharging"),
                                systemImage: deviceState.batteryIconName
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        } else {
                            Text(String(localized: "No mouse connected"))
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        Task { await DeviceManager.shared.refreshBattery() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help(String(localized: "Refresh"))
                    .buttonStyle(.borderless)
                    .disabled(!deviceState.connected)
                }
                .padding(.vertical, 8)
            }

            Section {
                BatteryHistoryChart()
            } header: {
                Text(String(localized: "Battery History"))
            }

            Section {
                Toggle(isOn: $config.showBatteryInMenuBar) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Show battery percentage in menu bar"))
                        Text(String(localized: "Display the charge level next to the menu bar icon."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
    }

    private var batteryColor: Color {
        guard let level = deviceState.batteryLevel else { return .secondary }
        if deviceState.batteryCharging { return .green }
        switch level {
        case ...20: return .red
        case ...40: return .orange
        default: return .green
        }
    }
}

private enum BatteryHistoryRange: String, CaseIterable, Identifiable {
    case day, week, month

    var id: Self { self }

    var title: String {
        switch self {
        case .day: String(localized: "24 Hours")
        case .week: String(localized: "7 Days")
        case .month: String(localized: "30 Days")
        }
    }

    var duration: TimeInterval {
        switch self {
        case .day: 24 * 3600
        case .week: 7 * 24 * 3600
        case .month: 30 * 24 * 3600
        }
    }
}

private struct BatteryHistoryChart: View {
    @State private var history = BatteryHistory.shared
    @State private var range: BatteryHistoryRange = .week

    var body: some View {
        let now = Date()
        let start = now.addingTimeInterval(-range.duration)
        let samples = history.samples(since: start)

        VStack(alignment: .leading, spacing: 12) {
            Picker(String(localized: "Range"), selection: $range) {
                ForEach(BatteryHistoryRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if samples.count < 2 {
                VStack(spacing: 6) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text(String(localized: "No history yet"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "Battery levels are recorded while Mouser is running."))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart(samples) { sample in
                    AreaMark(
                        x: .value("Time", sample.date),
                        y: .value("Battery", sample.level)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.green.opacity(0.28), Color.green.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Time", sample.date),
                        y: .value("Battery", sample.level)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.green)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                .chartXScale(domain: start...now)
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let level = value.as(Int.self) {
                                Text("\(level)%")
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: range == .day ? 6 : 7)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: range == .day
                            ? .dateTime.hour()
                            : .dateTime.month(.defaultDigits).day())
                    }
                }
                .frame(height: 160)
            }
        }
        .padding(.vertical, 4)
    }
}
