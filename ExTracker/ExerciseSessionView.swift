import SwiftUI
import SwiftData
import Charts
import UserNotifications

#if canImport(UIKit)
import UIKit
#endif


struct ExerciseSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var alarmManager = ExAlarmManager.shared
    @StateObject private var restManager = RestTimerManager.shared

    var onPopped: ((Exercise) -> Void)
    var onCompleted: (() -> Void)?

    let exercise: Exercise
    @Query private var records: [ExerciseSessionRecord]

    @State private var existingRecord: ExerciseSessionRecord? = nil
    @State private var isEditingExisting = false

    @State private var sessionSets: [SessionSet] = []
    @State private var showingStartSet = false
    @State private var selectedTrendRecordID: UUID? = nil

    struct SessionSet: Identifiable {
        let id = UUID()
        let weight: String
        let reps: String
        let timestamp: Date
        let restMinutes: Int
        let restSeconds: Int
    }

    struct TrendPoint: Identifiable {
        let id: UUID
        let index: Int
        let record: ExerciseSessionRecord
        let volume: Double
    }

    init(exercise: Exercise, latestRecord: ExerciseSessionRecord? = nil, onPopped: @escaping ((Exercise) -> Void), onCompleted: (() -> Void)? = nil) {
        self.exercise = exercise
        self.onPopped = onPopped
        self.onCompleted = onCompleted
        let exerciseID = exercise.id
        self._records = Query(
            filter: #Predicate<ExerciseSessionRecord> { $0.exerciseID == exerciseID },
            sort: [SortDescriptor(\.date, order: .reverse)]
        )
    }

    var body: some View {
        SwiftUI.Form {
            if alarmManager.isAlerting {
                SwiftUI.Section {
                    Button(role: .destructive) {
                        alarmManager.cancelActiveCountdown()
                        // Also make sure local rest state is cleared
                        restManager.cancel()
                    } label: {
                        Label("Stop Alarm", systemImage: "stop.circle.fill")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .accessibilityLabel("Stop Alarm")
                }
            }

            if restManager.isResting {
                SwiftUI.Section("Rest timer") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            ProgressView(value: Double(max(0, restManager.remainingSeconds)), total: Double(max(1, restManager.totalSeconds)))
                            Text(timeString(from: restManager.remainingSeconds))
                                .monospacedDigit()
                                .frame(minWidth: 60, alignment: .trailing)
                        }
                        HStack(spacing: 16) {
                            Button(restManager.isPaused ? "Resume" : "Pause", systemImage: restManager.isPaused ? "play.fill" : "pause.fill", action:{})
                                .onTapGesture { restManager.isPaused ? restManager.resume() : restManager.pause() }
                            Button("Cancel", systemImage: "stop.fill", role: .destructive) {
                                restManager.cancel()
                            }
                        }
                    }
                }
            }

            SwiftUI.Section(header: HStack {
                Image(systemName: exercise.category.systemImage)
                    .foregroundStyle(exercise.category.displayColor)
                Text("Sets this session")
                Spacer()
            }) {
                if sessionSets.isEmpty {
                    Text("No sets yet").foregroundStyle(.secondary)
                } else {
                    ForEach(sessionSets) { set in
                        HStack(spacing: 12) {
                            let w = set.weight
                            Label { Text("\(w) lbs") } icon: { Image(systemName: "scalemass") }
                            Spacer()
                            Text("x \(set.reps)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("\(set.weight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No weight" : "Weight \(set.weight) pounds"), x \(set.reps)")
                    }
                    .onDelete { indexSet in
                        sessionSets.remove(atOffsets: indexSet)
                        // Persist changes after deletion
                        if sessionSets.isEmpty {
                            // If no sets remain, delete today's record if it exists
                            if let rec = todayRecord() {
                                modelContext.delete(rec)
                                existingRecord = nil
                                isEditingExisting = false
                            }
                        } else {
                            saveSessionIfNeeded()
                        }
                    }
                }
            }

            let points = trendPoints()
            if !points.isEmpty {
                SwiftUI.Section("Workout trend") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Last \(points.count) \(points.count == 1 ? "session" : "sessions") • Total Volume (lbs)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Tap a dot for details")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        trendChartView(points: points)
                            .frame(height: 200)
                            .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
        .toolbar(content: {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    SessionsHistoryView(exercise: exercise, records: records)
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("Previous Session")

                EditButton()

                Button(action: {
                    showingStartSet = true
                }) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Start Set")
            }
        })
        .safeAreaInset(edge: .bottom) {
            Button(action: completeSession) {
                Text("Complete")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding([.horizontal, .bottom])
        }
        .sheet(isPresented: $showingStartSet) {
            // Determine the last set in the current session, if any
            let currentLast: StartSetView.PreviousSet? = {
                guard let last = sessionSets.last else { return nil }
                return StartSetView.PreviousSet(
                    weight: last.weight,
                    reps: last.reps,
                    restMinutes: last.restMinutes, // default or last used; no per-set rest stored in sessionSets
                    restSeconds: last.restSeconds
                )
            }()

            // Determine the final set from the previous session, if any
            let previousFinal: StartSetView.PreviousSet? = {
                var latestSessionWeights:[String] = []
                var latestSessionReps:[String] = []
                if let latestRecord = getLatestRecord(){
                    latestSessionWeights = latestRecord.weights
                    latestSessionReps = latestRecord.reps
                }
                let weights = latestSessionWeights
                let reps = latestSessionReps
            
                let lastWeight = (weights.last != nil) ? weights.last! : "";
                let lastRep = (reps.last != nil) ? reps.last! : "";
                // If you later store rest per set, use it here. For now, fall back to a sensible default.
                return StartSetView.PreviousSet(
                    weight: lastWeight,
                    reps: lastRep,
                    restMinutes: DefaultRestMinutes,
                    restSeconds: DefaultRestSeconds,
                )
            }()

            StartSetView(
                exerciseName: exercise.name,
                onFinish: { weight, reps, min, sec in
                    // Append the set to the session list
                    let set = SessionSet(weight: weight, reps: reps, timestamp: Date(), restMinutes: min, restSeconds: sec)
                    sessionSets.append(set)
                    // Persist immediately after adding a set
                    saveSessionIfNeeded()
                    // Dismiss the sheet back to Exercise page
                    showingStartSet = false
                    let total = max(0, min * 60 + sec)
                    restManager.startRest(totalSeconds: total)
                },
                currentSessionLastSet: currentLast,
                previousSessionFinalSet: previousFinal
            )
        }
        .onAppear {
            preloadTodaySessionIfAny()
        }
        .onDisappear() {
            onPopped(exercise)
        }
    }

    private func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func isSameDay(_ a: Date, _ b: Date) -> Bool {
        Calendar.current.isDate(a, inSameDayAs: b)
    }

    private func todayRecord() -> ExerciseSessionRecord? {
        let today = startOfDay(Date())
        return records.first { isSameDay($0.date, today) }
    }

    private func trendPoints() -> [TrendPoint] {
        let today = startOfDay(Date())
        let recentRecords = records
            .filter { !isSameDay($0.date, today) }
            .sorted { $0.date > $1.date }
            .prefix(10)
            .sorted { $0.date < $1.date }

        return recentRecords.enumerated().map { idx, record in
            TrendPoint(
                id: record.id,
                index: idx,
                record: record,
                volume: totalVolume(for: record)
            )
        }
    }

    private func parseNumericValue(_ text: String) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = Double(trimmed) {
            return exact
        }
        let numericPrefix = trimmed.prefix { $0.isNumber || $0 == "." }
        return Double(numericPrefix) ?? 0
    }

    private func totalVolume(for record: ExerciseSessionRecord) -> Double {
        let count = max(record.weights.count, record.reps.count)
        guard count > 0 else { return 0 }
        var total: Double = 0
        for idx in 0..<count {
            let weight = idx < record.weights.count ? parseNumericValue(record.weights[idx]) : 0
            let reps = idx < record.reps.count ? parseNumericValue(record.reps[idx]) : 0
            total += weight * reps
        }
        return total
    }

    @ViewBuilder
    private func trendChartView(points: [TrendPoint]) -> some View {
        let maxVolume = points.map(\.volume).max() ?? 0
        let yUpperBound = maxVolume > 0 ? maxVolume * 1.15 : 100
        let xUpperBound = Double(max(0, points.count - 1))
        let xDomain: ClosedRange<Double> = points.count <= 1 ? -0.5...0.5 : -0.35...(xUpperBound + 0.35)
        let accentColor = exercise.category.displayColor

        Chart(points) { point in
            if points.count > 1 {
                AreaMark(
                    x: .value("Session", Double(point.index)),
                    y: .value("Volume", point.volume)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [accentColor.opacity(0.25), accentColor.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Session", Double(point.index)),
                    y: .value("Volume", point.volume)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }

            PointMark(
                x: .value("Session", Double(point.index)),
                y: .value("Volume", point.volume)
            )
            .symbolSize(selectedTrendRecordID == point.id ? 110 : 70)
            .foregroundStyle(accentColor)
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0...yUpperBound)
        .chartXAxis {
            AxisMarks(values: points.map { Double($0.index) }) { value in
                AxisGridLine()
                AxisTick()
                if let doubleIdx = value.as(Double.self) {
                    let idx = Int(doubleIdx.rounded())
                    if idx >= 0 && idx < points.count {
                        AxisValueLabel(centered: true) {
                            Text(points[idx].record.date, format: .dateTime.month(.defaultDigits).day())
                                .font(.caption2)
                        }
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let plotOrigin = geometry[plotFrame].origin
                    ForEach(points) { point in
                        if let pos = proxy.position(for: (x: Double(point.index), y: point.volume)) {
                            let isSelected = Binding<Bool>(
                                get: { selectedTrendRecordID == point.id },
                                set: { newValue in
                                    if newValue {
                                        selectedTrendRecordID = point.id
                                    } else if selectedTrendRecordID == point.id {
                                        selectedTrendRecordID = nil
                                    }
                                }
                            )

                            Button {
                                selectedTrendRecordID = point.id
                            } label: {
                                Circle()
                                    .fill(Color.clear)
                                    .frame(width: 36, height: 36)
                                    .contentShape(Circle())
                                    .overlay {
                                        Circle()
                                            .strokeBorder(
                                                selectedTrendRecordID == point.id ? accentColor : Color.clear,
                                                lineWidth: 2
                                            )
                                            .frame(width: 18, height: 18)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Session on \(point.record.date.formatted(date: .abbreviated, time: .omitted)), total volume \(Int(point.volume.rounded())) pounds")
                            .popover(isPresented: isSelected, arrowEdge: .bottom) {
                                sessionDetailPopup(for: point)
                                    .presentationCompactAdaptation(.popover)
                            }
                            .position(x: plotOrigin.x + pos.x, y: plotOrigin.y + pos.y)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sessionDetailPopup(for point: TrendPoint) -> some View {
        let record = point.record
        let setCount = max(record.reps.count, record.weights.count)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Label {
                    Text(record.date, style: .date)
                        .font(.subheadline.weight(.semibold))
                } icon: {
                    Image(systemName: "calendar")
                        .foregroundStyle(exercise.category.displayColor)
                }
                Spacer(minLength: 8)
                Text("\(daysAgo(from: record.date))d ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Total Volume")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(point.volume.rounded())) lbs")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }

            Divider()

            if setCount == 0 {
                Text("No sets recorded")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<setCount, id: \.self) { idx in
                        let wRaw = idx < record.weights.count ? record.weights[idx].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                        let w = wRaw.isEmpty ? "0" : wRaw
                        let r = idx < record.reps.count ? record.reps[idx] : "-"

                        HStack(spacing: 12) {
                            Text("Set \(idx + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .leading)
                            Label {
                                Text("\(w) lbs")
                                    .font(.subheadline)
                            } icon: {
                                Image(systemName: "scalemass")
                                    .font(.caption)
                            }
                            Spacer(minLength: 12)
                            Text("x \(r)")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(minWidth: 230)
    }

    private func preloadTodaySessionIfAny() {
        guard sessionSets.isEmpty else { return }
        if let record = todayRecord() {
            existingRecord = record
            isEditingExisting = true
            self.sessionSets = zip(record.weights, record.reps).map { (w, r) in
                SessionSet(weight: w, reps: r, timestamp: Date(), restMinutes: 0, restSeconds: 0)
            }
        }
    }

    private func saveSessionIfNeeded() {
        // If there are no sets, remove today's record if it exists
        if sessionSets.isEmpty {
            if let rec = todayRecord() {
                modelContext.delete(rec)
            }
            existingRecord = nil
            isEditingExisting = false
            return
        }

        var record = todayRecord()
        if record == nil {
            record = ExerciseSessionRecord(
                exerciseID: exercise.id,
                date: Date(),
                weights: sessionSets.map { $0.weight },
                reps: sessionSets.map { $0.reps }
            )
            if let newRecord = record { modelContext.insert(newRecord) }
        } else {
            record?.weights = sessionSets.map { $0.weight }
            record?.reps = sessionSets.map { $0.reps }
        }
        existingRecord = record
        isEditingExisting = true
    }

    private func completeSession() {
        if !sessionSets.isEmpty {
            onCompleted?()
        }
        dismiss()
    }

    private func daysAgo(from date: Date) -> Int {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let startOfThatDay = Calendar.current.startOfDay(for: date)
        let comps = Calendar.current.dateComponents([.day], from: startOfThatDay, to: startOfToday)
        return max(0, comps.day ?? 0)
    }
    
    private func getLatestRecord() -> ExerciseSessionRecord? {
        if records.isEmpty { return nil }
        return records.max { a, b in
            a.date < b.date
        }
    }
    
    private func timeString(from remainingSeconds: Int) -> String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
#Preview {
    let container = try! ModelContainer(for: Exercise.self, configurations: .init(isStoredInMemoryOnly: true))
    let ex = Exercise(name: "Bench Press", category: .chest)
    return ExerciseSessionView(exercise: ex, onPopped: { ex in return })
}
