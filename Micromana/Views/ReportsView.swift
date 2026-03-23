import Charts
import SwiftUI

/// Holds the selected calendar day for the reports window so SwiftUI and the export handler share one source of truth.
final class ReportsDaySelection: ObservableObject {
    @Published var selectedDay: Date = Calendar.current.startOfDay(for: Date())
}

struct ReportsView: View {
    @ObservedObject var dataStore: DataStore
    @ObservedObject var selection: ReportsDaySelection
    var onExportCSV: () -> Void

    init(dataStore: DataStore, selection: ReportsDaySelection, onExportCSV: @escaping () -> Void) {
        self.dataStore = dataStore
        self.selection = selection
        self.onExportCSV = onExportCSV
    }

    private var selectedDay: Date { selection.selectedDay }

    private var calendar: Calendar { .current }

    private var todayStart: Date {
        calendar.startOfDay(for: Date())
    }

    private var canGoToNextDay: Bool {
        selectedDay < todayStart
    }

    private var points: [DailyManaPoint] {
        dataStore.dailyManaChartPoints(maxDays: 30)
    }

    /// Task entries for the selected calendar day.
    private var reportRecords: [TaskEntry] {
        dataStore.tasks(on: selectedDay, calendar: calendar)
    }

    private func shiftSelectedDay(by days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: selection.selectedDay) else { return }
        let start = calendar.startOfDay(for: next)
        selection.selectedDay = min(start, todayStart)
    }

    private var timeShortFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }

    private func recordSubtitle(_ task: TaskEntry) -> String {
        let start = timeShortFormatter.string(from: task.startTime)
        let end = timeShortFormatter.string(from: task.endTime)
        let dur = ReportGenerator.formatDuration(task.duration)
        return "\(start) – \(end) · \(dur)"
    }

    private var budgetHours: Double {
        Double(dataStore.settings.dailyManaMinutes) / 60
    }

    private var budgetMinutes: Double {
        Double(dataStore.settings.dailyManaMinutes)
    }

    /// Largest single-day tracked time in the chart (seconds).
    private var maxConsumedSeconds: TimeInterval {
        points.map(\.consumed).max() ?? 0
    }

    /// Zoom to minutes when no day reaches an hour — independent of daily budget, so small totals stay visible.
    private var zoomToMinutes: Bool {
        maxConsumedSeconds < 3600
    }

    private func yValue(consumed: TimeInterval) -> Double {
        zoomToMinutes ? consumed / 60 : consumed / 3600
    }

    /// Upper bound for the Y domain in minute zoom (headroom above the tallest bar, not tied to budget).
    private var minuteChartYMax: Double {
        let consumedMin = maxConsumedSeconds / 60
        return max(5, consumedMin * 1.2)
    }

    /// Show the budget rule only when it fits inside the zoomed minute scale (otherwise it would force a useless 0–8h scale).
    private var showBudgetRuleInMinuteZoom: Bool {
        budgetMinutes <= minuteChartYMax
    }

    private var budgetYValueHours: Double {
        budgetHours
    }

    private var budgetYValueMinutes: Double {
        budgetMinutes
    }

    private var yAxisTitle: String {
        zoomToMinutes ? "Minutes" : "Hours"
    }

    private var hourChartYMax: Double {
        max(budgetHours, maxConsumedSeconds / 3600 * 1.08)
    }

    private func isSelectedChartDay(_ day: Date) -> Bool {
        calendar.isDate(day, inSameDayAs: selectedDay)
    }

    /// Dim non-selected bars only when the selected day appears in this chart; otherwise the range may not include that day.
    private var shouldDimNonSelectedBars: Bool {
        points.contains { calendar.isDate($0.day, inSameDayAs: selectedDay) }
    }

    private var manaChart: some View {
        Chart {
            ForEach(points) { p in
                BarMark(
                    x: .value("Day", p.shortLabel),
                    y: .value(yAxisTitle, yValue(consumed: p.consumed))
                )
                .foregroundStyle(
                    p.consumed > p.budget
                        ? Color.orange.gradient
                        : ManaColors.bar.gradient
                )
                .opacity(shouldDimNonSelectedBars ? (isSelectedChartDay(p.day) ? 1 : 0.35) : 1)
            }
            if !zoomToMinutes || showBudgetRuleInMinuteZoom {
                RuleMark(
                    y: .value(
                        "Daily budget",
                        zoomToMinutes ? budgetYValueMinutes : budgetYValueHours
                    )
                )
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .annotation(position: .top, alignment: .trailing) {
                    Text("Budget")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .chartYScale(domain: zoomToMinutes ? 0...minuteChartYMax : 0...hourChartYMax)
        .chartYAxisLabel(yAxisTitle, alignment: .leading)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel()
                    .font(.caption2)
            }
        }
        .chartXAxis {
            AxisMarks(preset: .aligned) { _ in
                AxisValueLabel()
                    .font(.caption2)
            }
        }
        .frame(minHeight: 280)
    }

    private var sessionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Tasks")
                .font(.headline)
                .padding(.bottom, 8)

            if reportRecords.isEmpty {
                Text("No sessions on this day")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                List(reportRecords) { task in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "—" : task.description)
                            .font(.body)
                            .lineLimit(3)
                        Text(recordSubtitle(task))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.leading, 12)
        .frame(minWidth: 220, idealWidth: 280, maxWidth: 400, maxHeight: .infinity, alignment: .topLeading)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("mana consumed")
                        .font(.title2.weight(.semibold))
                    HStack(spacing: 10) {
                        Button {
                            shiftSelectedDay(by: -1)
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.borderless)
                        .help("Previous day")

                        Text(selectedDay, format: Date.FormatStyle(date: .numeric, time: .omitted))
                            .font(.body)
                            .foregroundStyle(.primary)
                            .frame(minWidth: 100)

                        Button {
                            shiftSelectedDay(by: 1)
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(.borderless)
                        .disabled(!canGoToNextDay)
                        .help("Next day")
                    }
                }
                Spacer()
                Button("Export report") {
                    onExportCSV()
                }
                .disabled(dataStore.totalDuration(on: selectedDay, calendar: calendar) <= 0)
            }

            if points.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No data yet")
                        .font(.headline)
                    Text("Track time from the menu bar icon to see daily mana usage here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                HSplitView {
                    manaChart
                        .frame(minWidth: 280)
                    sessionsList
                }
                .frame(minHeight: 300, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .frame(minWidth: 720, minHeight: 420)
        .onAppear {
            dataStore.load()
        }
    }
}
