import SwiftUI

struct ActiveWorkoutView: View {
    @ObservedObject var store: WorkoutStore
    @ObservedObject var rest: RestTimer
    let onMinimize: () -> Void
    let onEnd: () -> Void

    @State private var showPicker = false
    @State private var confirmDiscard = false
    @State private var finishing = false
    @State private var finished = false
    @State private var postError: String?
    @FocusState private var focusedField: String?

    init(store: WorkoutStore, onMinimize: @escaping () -> Void, onEnd: @escaping () -> Void) {
        self.store = store
        self.rest = store.rest
        self.onMinimize = onMinimize
        self.onEnd = onEnd
    }

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
            if confirmDiscard {
                discardModal
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showPicker) {
            ExercisePicker { store.addExercise($0) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
                    .font(.system(size: 15, weight: .semibold))
            }
        }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                onMinimize()
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 15, weight: .semibold)).foregroundStyle(FG.muted).padding(8)
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
                Menu {
                    Button(role: .destructive) {
                        confirmDiscard = true
                    } label: {
                        Label("Discard workout", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(FG.muted).padding(10)
                }
                Button {
                    Task { await finish() }
                } label: {
                    Text(finishing ? "…" : "Finish")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(FG.ember))
                        .foregroundStyle(.black.opacity(0.8))
                        .opacity(store.doneSets == 0 ? 0.35 : 1)
                }
                .disabled(finishing || store.doneSets == 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(FG.card)
        .overlay(Rectangle().fill(FG.border).frame(height: 1), alignment: .bottom)
    }

    // MARK: exercise card — the PWA table, ported

    private func exerciseCard(_ i: Int) -> some View {
        let ex = store.exercises[i]
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(ex.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(FG.ember)
                    .lineLimit(1)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "timer").font(.system(size: 10))
                    Text("\(ex.restSeconds / 60):\(String(format: "%02d", ex.restSeconds % 60))")
                }
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(FG.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(FG.secondary))
                Menu {
                    Button(role: .destructive) {
                        store.removeExercise(at: i)
                    } label: {
                        Label("Remove exercise", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13)).foregroundStyle(FG.muted).padding(6)
                }
            }
            .padding(.bottom, 10)

            HStack(spacing: 8) {
                Text("SET").frame(width: 26, alignment: .leading)
                Text("PREVIOUS").frame(maxWidth: .infinity, alignment: .leading)
                Text("KG").frame(width: 58)
                Text("REPS").frame(width: 48)
                Text("RPE").frame(width: 44)
                Color.clear.frame(width: 38)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(FG.muted)
            .padding(.bottom, 4)

            ForEach(ex.sets.indices, id: \.self) { s in
                setRow(exIdx: i, setIdx: s)
                if s < ex.sets.count - 1 {
                    Rectangle().fill(FG.border.opacity(0.6)).frame(height: 1)
                }
            }

            Button {
                store.addSet(to: i)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                    Text("Add set").font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(FG.secondary.opacity(0.7)))
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }

    private func setRow(exIdx: Int, setIdx: Int) -> some View {
        let set = store.exercises[exIdx].sets[setIdx]
        return HStack(spacing: 8) {
            Text("\(setIdx + 1)")
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(set.warmup ? FG.ember : FG.muted)
                .frame(width: 26, alignment: .leading)

            Text(set.previous ?? "–")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(FG.muted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            valueField(
                id: "\(exIdx)-\(setIdx)-w", width: 58, placeholder: "kg", keyboard: .decimalPad,
                get: { store.exercises[exIdx].sets[setIdx].weight.map(trim) ?? "" },
                set: { txt in
                    store.exercises[exIdx].sets[setIdx].weight =
                        Double(txt.replacingOccurrences(of: ",", with: "."))
                }
            )

            valueField(
                id: "\(exIdx)-\(setIdx)-r", width: 48,
                placeholder: set.amrap ? "\(set.reps ?? 0)+" : "reps", keyboard: .numberPad,
                get: { store.exercises[exIdx].sets[setIdx].reps.map(String.init) ?? "" },
                set: { txt in store.exercises[exIdx].sets[setIdx].reps = Int(txt) }
            )

            Menu {
                Button("warm-up \(set.warmup ? "✓" : "")") { store.exercises[exIdx].sets[setIdx].warmup.toggle() }
                ForEach([7.0, 8, 8.5, 9, 9.5, 10], id: \.self) { r in
                    Button("RPE \(trim(r)) \(set.rpe == r ? "✓" : "")") { store.exercises[exIdx].sets[setIdx].rpe = r }
                }
                if set.rpe != nil {
                    Button("clear") { store.exercises[exIdx].sets[setIdx].rpe = nil }
                }
            } label: {
                Text(set.rpe.map { "@\(trim($0))" } ?? "RPE")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(set.rpe != nil ? FG.ember : FG.muted)
                    .frame(width: 44, height: 38)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(FG.border, lineWidth: 1))
            }

            Button {
                let wasDone = set.done
                guard store.exercises[exIdx].sets[setIdx].reps != nil else { return }
                store.exercises[exIdx].sets[setIdx].done.toggle()
                if !wasDone {
                    focusedField = nil
                    rest.start(seconds: store.exercises[exIdx].restSeconds,
                               exercise: store.exercises[exIdx].name,
                               nextSet: setIdx + 2,
                               workoutName: store.name)
                }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(set.done ? .black.opacity(0.8) : FG.muted.opacity(0.6))
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 9).fill(set.done ? FG.ember : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(set.done ? FG.ember : FG.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 7)
    }

    private func valueField(id: String, width: CGFloat, placeholder: String, keyboard: UIKeyboardType,
                            get: @escaping () -> String, set: @escaping (String) -> Void) -> some View {
        TextField(placeholder, text: Binding(get: get, set: set))
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .font(.system(size: 15, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .focused($focusedField, equals: id)
            .frame(width: width, height: 38)
            .background(RoundedRectangle(cornerRadius: 9).fill(FG.background))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(focusedField == id ? FG.ember : FG.border, lineWidth: focusedField == id ? 1.5 : 1)
            )
    }

    // MARK: discard modal — family style, not the system sheet

    private var discardModal: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
                .onTapGesture { confirmDiscard = false }
            VStack(spacing: 6) {
                Text("Discard workout?")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Everything logged in this session will be lost.")
                    .font(.system(size: 13))
                    .foregroundStyle(FG.muted)
                    .multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button {
                        confirmDiscard = false
                    } label: {
                        Text("Keep going")
                            .font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 12).fill(FG.secondary))
                            .foregroundStyle(.white)
                    }
                    Button {
                        Task {
                            await store.discard()
                            onEnd()
                        }
                    } label: {
                        Text("Discard")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 12).fill(FG.destructive))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.top, 14)
            }
            .padding(20)
            .frame(maxWidth: 340)
            .background(RoundedRectangle(cornerRadius: 16).fill(FG.card))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(FG.border, lineWidth: 1))
            .padding(24)
        }
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
            try await ForgeAPI.sync(store.buildSync(finished: true))
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
                onEnd()
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(FG.muted)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(FG.background)
        }
        .preferredColorScheme(.dark)
        .task { all = (try? await ForgeAPI.exercises()) ?? [] }
    }
}
