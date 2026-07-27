import SwiftUI

struct ActiveWorkoutView: View {
    @StateObject var store: WorkoutStore
    @StateObject private var rest = RestTimer()
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var finishing = false
    @State private var finished = false
    @State private var postError: String?

    var body: some View {
        ZStack {
            FG.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if store.loading {
                    Spacer()
                    ProgressView().tint(FG.ember)
                    Spacer()
                } else if finished {
                    doneView
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(store.exercises.indices, id: \.self) { i in
                                exerciseCard(i)
                            }
                            Button {
                                showPicker = true
                            } label: {
                                HStack {
                                    Image(systemName: "plus")
                                    Text("Add exercise")
                                }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(FG.muted)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(FG.border, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                            }
                            .buttonStyle(.plain)
                            Color.clear.frame(height: 80)
                        }
                        .padding(16)
                    }
                }
            }
            if rest.active, !finished {
                restBar
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPicker) {
            ExercisePicker { store.addExercise($0) }
        }
        .onDisappear { rest.stop() }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                rest.stop()
                dismiss()
            } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(FG.muted).padding(8)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(store.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                HStack(spacing: 6) {
                    Text(store.startedAt, style: .timer)
                    Text("· \(store.doneSets) sets · \(trim(store.volume)) kg")
                }
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(FG.muted)
            }
            Spacer()
            if !finished {
                Button {
                    Task { await finish() }
                } label: {
                    Text(finishing ? "…" : "Finish")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(FG.ember))
                        .foregroundStyle(.black.opacity(0.8))
                }
                .disabled(finishing || store.doneSets == 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(FG.card)
        .overlay(Rectangle().fill(FG.border).frame(height: 1), alignment: .bottom)
    }

    // MARK: exercise card

    private func exerciseCard(_ i: Int) -> some View {
        let ex = store.exercises[i]
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(ex.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    if ex.supersetWithNext {
                        Text("superset").font(.system(size: 10, weight: .semibold)).foregroundStyle(FG.ember)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(FG.emberSoft))
                    }
                    Spacer()
                    if let mg = ex.muscleGroup {
                        Text(mg)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(FG.muted)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(FG.secondary))
                    }
                }
                if let prev = ex.previous {
                    Text(prev).font(.system(size: 11)).foregroundStyle(FG.muted)
                }
            }
            ForEach(ex.sets.indices, id: \.self) { s in
                setRow(exIdx: i, setIdx: s)
            }
            Button {
                store.addSet(to: i)
            } label: {
                Text("+ set").font(.system(size: 12, weight: .medium)).foregroundStyle(FG.ember)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }

    private func setRow(exIdx: Int, setIdx: Int) -> some View {
        let set = store.exercises[exIdx].sets[setIdx]
        let inc = store.exercises[exIdx].increment
        return HStack(spacing: 10) {
            Text("\(setIdx + 1)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(FG.muted)
                .frame(width: 18)

            stepper(value: trim(set.weight), unit: "kg",
                    minus: { adjust(exIdx, setIdx) { $0.weight = max(0, $0.weight - inc) } },
                    plus: { adjust(exIdx, setIdx) { $0.weight += inc } })

            stepper(value: "\(set.reps)", unit: "reps",
                    minus: { adjust(exIdx, setIdx) { $0.reps = max(1, $0.reps - 1) } },
                    plus: { adjust(exIdx, setIdx) { $0.reps += 1 } })

            Menu {
                Button("warm-up \(set.warmup ? "✓" : "")") { adjust(exIdx, setIdx) { $0.warmup.toggle() } }
                ForEach([7.0, 8, 8.5, 9, 9.5, 10], id: \.self) { r in
                    Button("RPE \(trim(r)) \(set.rpe == r ? "✓" : "")") { adjust(exIdx, setIdx) { $0.rpe = r } }
                }
                if set.rpe != nil {
                    Button("clear RPE") { adjust(exIdx, setIdx) { $0.rpe = nil } }
                }
            } label: {
                Text(set.warmup ? "W" : set.rpe.map { "@\(trim($0))" } ?? "…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(set.warmup || set.rpe != nil ? FG.ember : FG.muted)
                    .frame(width: 34, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(FG.secondary))
            }

            Button {
                let wasDone = set.done
                adjust(exIdx, setIdx) { $0.done.toggle() }
                if !wasDone {
                    rest.start(seconds: store.exercises[exIdx].restSeconds,
                               exercise: store.exercises[exIdx].name,
                               nextSet: setIdx + 2,
                               workoutName: store.name)
                }
            } label: {
                Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(set.done ? FG.ember : FG.muted.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
    }

    private func stepper(value: String, unit: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            Button(action: minus) {
                Image(systemName: "minus").font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 30).contentShape(Rectangle())
            }
            VStack(spacing: 0) {
                Text(value).font(.system(size: 14, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                Text(unit).font(.system(size: 8)).foregroundStyle(FG.muted)
            }
            .frame(minWidth: 40)
            Button(action: plus) {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 30).contentShape(Rectangle())
            }
        }
        .foregroundStyle(FG.muted)
        .background(RoundedRectangle(cornerRadius: 8).fill(FG.secondary))
    }

    private func adjust(_ exIdx: Int, _ setIdx: Int, _ change: (inout DraftSet) -> Void) {
        change(&store.exercises[exIdx].sets[setIdx])
    }

    // MARK: rest bar

    private var restBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 14) {
                Image(systemName: "timer").font(.system(size: 15)).foregroundStyle(FG.ember)
                VStack(alignment: .leading, spacing: 0) {
                    if let end = rest.endDate {
                        Text(timerInterval: Date()...end, countsDown: true)
                            .font(.system(size: 18, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    Text("rest · \(rest.exercise)").font(.system(size: 11)).foregroundStyle(FG.muted).lineLimit(1)
                }
                Spacer()
                Button("+30s") { rest.extend(by: 30) }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FG.ember)
                Button {
                    rest.stop()
                } label: {
                    Image(systemName: "forward.fill").font(.system(size: 14)).foregroundStyle(FG.muted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16).fill(FG.card))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(FG.border, lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        }
    }

    // MARK: finish

    private func finish() async {
        finishing = true
        postError = nil
        do {
            try await ForgeAPI.log(store.buildLog())
            rest.stop()
            finished = true
        } catch {
            postError = error.localizedDescription
        }
        finishing = false
    }

    private var doneView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(FG.ember)
            Text("Saved to Forge").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
            Text("\(store.doneSets) sets · \(trim(store.volume)) kg · \(Int(Date().timeIntervalSince(store.startedAt) / 60)) min")
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(FG.muted)
            if let postError {
                Text(postError).font(.system(size: 13)).foregroundStyle(.red)
            }
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(Capsule().fill(FG.ember))
                    .foregroundStyle(.black.opacity(0.8))
            }
            Spacer()
        }
    }
}

// MARK: exercise picker

struct ExercisePicker: View {
    let onPick: (LibraryExercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var all: [LibraryExercise] = []
    @State private var query = ""

    var filtered: [LibraryExercise] {
        query.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { ex in
                Button {
                    onPick(ex)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ex.name).foregroundStyle(.white)
                        Text([ex.muscle_group, ex.equipment].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 11)).foregroundStyle(FG.muted)
                    }
                }
                .listRowBackground(FG.card)
            }
            .searchable(text: $query)
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(FG.background)
        }
        .preferredColorScheme(.dark)
        .task { all = (try? await ForgeAPI.exercises()) ?? [] }
    }
}
