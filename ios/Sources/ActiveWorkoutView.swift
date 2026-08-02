import SwiftUI

struct ActiveWorkoutView: View {
    @ObservedObject var store: WorkoutStore
    @ObservedObject var rest: RestTimer
    let onMinimize: () -> Void
    let onEnd: () -> Void

    private struct PlateTarget: Identifiable {
        let idx: Int
        var id: Int { idx }
    }

    @State private var showPicker = false
    @State private var plateExerciseIdx: PlateTarget?
    @State private var swapTargetIdx: PlateTarget?
    @State private var peekTargetIdx: PlateTarget?
    @State private var noteTargetIdx: Int?
    @State private var noteDraft = ""
    @State private var flashedSetId: UUID?
    @State private var donePopped = false
    @State private var queuedOffline = false
    @State private var finishSummary: FinishSummary?
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
                    FinishSummaryView(store: store, summary: finishSummary,
                                      queuedOffline: queuedOffline, onDone: onEnd)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            if let postError {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 13)).foregroundStyle(FG.destructive)
                                    Text("Couldn't save: \(postError)")
                                        .font(.system(size: 13)).foregroundStyle(.white)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 12)
                                    .fill(FG.destructive.opacity(0.15)))
                            }
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

                            // Session notes — what happened TODAY. The pinned
                            // exercise note (⋯ on a card) is the other thing.
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "square.and.pencil")
                                    .font(.system(size: 12)).foregroundStyle(FG.muted)
                                    .padding(.top, 3)
                                TextField("Session notes — how today felt, aches, anything off",
                                          text: $store.notes, axis: .vertical)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white)
                                    .lineLimit(1...4)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(FG.card))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(FG.border, lineWidth: 1))
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
        .sheet(item: $plateExerciseIdx) { target in
            PlateCalculatorView(initialWeight: plateWeight(for: target.idx))
        }
        .fullScreenCover(item: $swapTargetIdx) { target in
            ExercisePicker { store.swapExercise(at: target.idx, with: $0) }
        }
        .sheet(item: $peekTargetIdx) { target in
            if store.exercises.indices.contains(target.idx) {
                RecentSessionsSheet(
                    exerciseId: store.exercises[target.idx].exerciseId,
                    name: store.exercises[target.idx].name
                )
            }
        }
        .alert("Exercise note", isPresented: Binding(
            get: { noteTargetIdx != nil },
            set: { if !$0 { noteTargetIdx = nil } }
        )) {
            TextField("Seat height, cues, grip width", text: $noteDraft)
            Button("Save") {
                if let idx = noteTargetIdx { store.setNote(at: idx, text: noteDraft) }
                noteTargetIdx = nil
            }
            Button("Cancel", role: .cancel) { noteTargetIdx = nil }
        } message: {
            Text("Pinned to this exercise everywhere.")
        }
        .onAppear {
            // debug hook: `-plates` opens the calculator on the first exercise
            if CommandLine.arguments.contains("-plates") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    plateExerciseIdx = PlateTarget(idx: 0)
                }
            }
            // debug hook: `-preview-finish` shows the summary with mock data
            if CommandLine.arguments.contains("-preview-finish") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    for i in store.exercises.indices {
                        for j in store.exercises[i].sets.indices {
                            store.exercises[i].sets[j].done = true
                        }
                    }
                    finishSummary = FinishSummary(
                        id: 99, name: store.name, duration_seconds: 4244,
                        total_volume: 7505, total_sets: 16,
                        prs: [FinishPR(exercise_name: "Plate-Loaded Shoulder Press", kind: "weight",
                                       value: 65, reps: 7),
                              FinishPR(exercise_name: "Plate-Loaded Lat Pulldown (Neutral)", kind: "weight",
                                       value: 75, reps: 8)],
                        workout_number: 8, week_workouts: 1,
                        comparison: FinishComparison(prev_volume: 6900, prev_sets: 14,
                                                     prev_date: "2026-07-25T20:28:00"),
                        music: FinishMusic(songs: 12, top_artist: "Gojira")
                    )
                    finished = true
                }
            }
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
                    Text("· \(store.doneSets) \(store.doneSets == 1 ? "set" : "sets") · \(trim(store.volume)) kg")
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
                // per-exercise rest picker (PWA's REST_OPTIONS)
                Menu {
                    ForEach([0, 30, 45, 60, 90, 120, 150, 180, 240, 300], id: \.self) { s in
                        Button {
                            store.exercises[i].restSeconds = s
                        } label: {
                            if s == ex.restSeconds {
                                Label(restLabel(s), systemImage: "checkmark")
                            } else {
                                Text(restLabel(s))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "timer").font(.system(size: 10))
                        Text(restLabel(ex.restSeconds))
                    }
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(FG.muted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(FG.secondary))
                }
                Menu {
                    if i > 0 {
                        Button {
                            withAnimation(.spring(duration: 0.3)) { store.moveExercise(at: i, offset: -1) }
                        } label: {
                            Label("Move up", systemImage: "arrow.up")
                        }
                    }
                    if i < store.exercises.count - 1 {
                        Button {
                            withAnimation(.spring(duration: 0.3)) { store.moveExercise(at: i, offset: 1) }
                        } label: {
                            Label("Move down", systemImage: "arrow.down")
                        }
                        Button {
                            store.toggleSuperset(at: i)
                        } label: {
                            Label(ex.supersetWithNext ? "Remove superset with next" : "Superset with next exercise",
                                  systemImage: ex.supersetWithNext ? "personalhotspot.slash" : "link")
                        }
                    }
                    Button {
                        swapTargetIdx = PlateTarget(idx: i)
                    } label: {
                        Label("Swap exercise", systemImage: "arrow.left.arrow.right")
                    }
                    if !store.warmupRamp(at: i).isEmpty {
                        Button {
                            withAnimation(.spring(duration: 0.3)) { store.addWarmupSets(at: i) }
                        } label: {
                            Label("Add warm-up sets", systemImage: "flame")
                        }
                    }
                    Button {
                        noteDraft = ex.note ?? ""
                        noteTargetIdx = i
                    } label: {
                        Label(ex.note == nil ? "Add exercise note" : "Edit exercise note",
                              systemImage: "note.text")
                    }
                    Button {
                        peekTargetIdx = PlateTarget(idx: i)
                    } label: {
                        Label("Recent sessions", systemImage: "clock.arrow.circlepath")
                    }
                    Button {
                        plateExerciseIdx = PlateTarget(idx: i)
                    } label: {
                        Label("Plate calculator", systemImage: "plus.forwardslash.minus")
                    }
                    Divider()
                    Button(role: .destructive) {
                        withAnimation(.spring(duration: 0.3)) { store.removeExercise(at: i) }
                    } label: {
                        Label("Remove exercise", systemImage: "trash")
                    }
                } label: {
                    // padded for the tap target, pulled back out so the glyph
                    // sits on the card's content edge like everything below it
                    Image(systemName: "ellipsis").font(.system(size: 13)).foregroundStyle(FG.muted)
                        .padding(6)
                        .padding(.trailing, -10)
                }
            }
            if ex.supersetWithNext {
                HStack(spacing: 5) {
                    Image(systemName: "link").font(.system(size: 10, weight: .semibold))
                    Text("Superset with next — rest starts after the pair")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FG.ember)
                .padding(.bottom, 6)
            }
            // rep-range overshoot: a done set far past rep_max means the
            // weight is too light — say so mid-session, not post-hoc
            if let repMax = ex.repMax,
               ex.sets.contains(where: { $0.done && !$0.warmup && ($0.reps ?? 0) >= repMax + 3 }) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.circle").font(.system(size: 11, weight: .semibold))
                    Text("Well past the \(ex.repMin.map { "\($0)–" } ?? "")\(repMax) rep range — add weight next set")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FG.gold)
                .padding(.bottom, 6)
            }
            if let sw = ex.suggestedWeight {
                if ex.suggestionKind == "deload" {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.right").font(.system(size: 11, weight: .semibold))
                        Text("Deload: \(trim(sw)) kg suggested after 3 stalled sessions")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FG.gold)
                    .padding(.bottom, 6)
                } else if ex.suggestionKind == "target" {
                    HStack(spacing: 5) {
                        Image(systemName: "scope").font(.system(size: 11, weight: .semibold))
                        Text("Target: ~\(trim(sw)) kg to start — seeded from your TM, adjust to the rep range")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FG.ember)
                    .padding(.bottom, 6)
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                        Text("Progression: \(trim(sw)) kg suggested\(ex.repMin != nil && ex.repMax != nil ? " · target \(ex.repMin!)–\(ex.repMax!) reps" : "")")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FG.ember)
                    .padding(.bottom, 6)
                }
            }
            // An AMRAP set is the point of the session — say so as an
            // instruction, not as a trophy notification.
            if ex.sets.contains(where: \.amrap) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "flame.fill").font(.system(size: 11)).foregroundStyle(FG.gold)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Last set is AMRAP — as many reps as possible")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(FG.gold)
                        if let amrap = ex.amrapHint {
                            Text("beat \(amrap.beatReps) reps at \(trim(amrap.weight)) kg to top your best")
                                .font(.system(size: 12))
                                .foregroundStyle(FG.muted)
                        }
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(FG.gold.opacity(0.10)))
                // a filled block needs air under the header — it was sitting
                // flush against the rest-timer pill
                .padding(.top, 10)
                .padding(.bottom, 8)
            }

            if let note = ex.note {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "note.text").font(.system(size: 11))
                    Text(note)
                }
                .font(.system(size: 12))
                .foregroundStyle(FG.muted)
                .padding(.bottom, 6)
            }

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
                withAnimation(.spring(duration: 0.3)) { store.addSet(to: i) }
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
        SwipeToDelete {
            withAnimation(.spring(duration: 0.3)) { store.removeSet(exIdx: exIdx, setIdx: setIdx) }
        } content: {
            setRowContent(exIdx: exIdx, setIdx: setIdx)
        }
    }

    private func setRowContent(exIdx: Int, setIdx: Int) -> some View {
        let set = store.exercises[exIdx].sets[setIdx]
        return HStack(spacing: 8) {
            // Front marker — the row declares what kind of set it is before
            // the numbers, and tapping it is how you change that (PWA model).
            Menu {
                Button("working set \(set.plain ? "✓" : "")") {
                    store.exercises[exIdx].sets[setIdx].warmup = false
                    store.exercises[exIdx].sets[setIdx].setType = nil
                }
                Button("warm-up \(set.warmup ? "✓" : "")") {
                    store.exercises[exIdx].sets[setIdx].warmup.toggle()
                    store.exercises[exIdx].sets[setIdx].setType = nil
                }
                Button("drop set \(set.setType == "drop" ? "✓" : "")") {
                    store.exercises[exIdx].sets[setIdx].setType = set.setType == "drop" ? nil : "drop"
                    store.exercises[exIdx].sets[setIdx].warmup = false
                }
                Button("to failure \(set.setType == "failure" ? "✓" : "")") {
                    store.exercises[exIdx].sets[setIdx].setType = set.setType == "failure" ? nil : "failure"
                    store.exercises[exIdx].sets[setIdx].warmup = false
                }
                Button("AMRAP — max reps \(set.amrap ? "✓" : "")") {
                    let becomingAmrap = set.setType != "amrap"
                    store.exercises[exIdx].sets[setIdx].setType = becomingAmrap ? "amrap" : nil
                    store.exercises[exIdx].sets[setIdx].warmup = false
                    // an AMRAP set is answered by doing it, not by a prefill
                    if becomingAmrap {
                        store.exercises[exIdx].sets[setIdx].plannedReps =
                            store.exercises[exIdx].sets[setIdx].reps
                        store.exercises[exIdx].sets[setIdx].reps = nil
                    }
                }
                Divider()
                Button("Remove set", role: .destructive) {
                    withAnimation(.spring(duration: 0.3)) { store.removeSet(exIdx: exIdx, setIdx: setIdx) }
                }
            } label: {
                Text(setMarker(set, number: setIdx + 1))
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(markerColor(set))
                    .frame(width: 26, height: 38, alignment: .leading)
                    .contentShape(Rectangle())
            }

            // No AMRAP badge here — it truncated the previous value, which is
            // exactly the number being chased. The gold set number, the gold
            // empty reps field and the banner carry it without breaking the grid.
            Text(set.previous ?? "–")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(set.amrap ? FG.gold.opacity(0.85) : FG.muted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            valueField(
                id: "\(exIdx)-\(setIdx)-w", width: 58,
                placeholder: store.exercises[exIdx].suggestedWeight.map(trim) ?? "kg",
                keyboard: .decimalPad,
                get: { store.exercises[exIdx].sets[setIdx].weight.map(trim) ?? "" },
                set: { txt in
                    store.exercises[exIdx].sets[setIdx].weight =
                        Double(txt.replacingOccurrences(of: ",", with: "."))
                }
            )

            valueField(
                id: "\(exIdx)-\(setIdx)-r", width: 48,
                placeholder: {
                    let ex = store.exercises[exIdx]
                    if set.amrap { return set.plannedReps.map { "\($0)+" } ?? "max" }
                    if let lo = ex.repMin, let hi = ex.repMax { return "\(lo)–\(hi)" }
                    return ex.repMin.map(String.init) ?? "reps"
                }(),
                keyboard: .numberPad,
                accent: set.amrap,
                get: { store.exercises[exIdx].sets[setIdx].reps.map(String.init) ?? "" },
                set: { txt in store.exercises[exIdx].sets[setIdx].reps = Int(txt) }
            )

            // Effort column — RPE only now, so it matches its header
            Menu {
                ForEach([7.0, 8, 8.5, 9, 9.5, 10], id: \.self) { r in
                    Button("RPE \(trim(r)) \(set.rpe == r ? "✓" : "")") { store.exercises[exIdx].sets[setIdx].rpe = r }
                }
                if set.rpe != nil {
                    Button("clear RPE") { store.exercises[exIdx].sets[setIdx].rpe = nil }
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
                withAnimation(.easeOut(duration: 0.2)) {
                    store.exercises[exIdx].sets[setIdx].done.toggle()
                }
                store.exercises[exIdx].sets[setIdx].doneAt = wasDone ? nil : Date()
                if !wasDone {
                    // still training — a stale finish attempt no longer marks the end
                    store.finishIntent = nil
                    store.music.snapshot()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    focusedField = nil
                    // PWA set flash: brighter ember that settles into the done tint
                    let id = store.exercises[exIdx].sets[setIdx].id
                    flashedSetId = id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.easeOut(duration: 0.4)) {
                            if flashedSetId == id { flashedSetId = nil }
                        }
                    }
                    // inside a superset, rest comes after the group's last exercise
                    if !store.exercises[exIdx].supersetWithNext, store.exercises[exIdx].restSeconds > 0 {
                        rest.start(seconds: store.exercises[exIdx].restSeconds,
                                   exercise: store.exercises[exIdx].name,
                                   nextSet: setIdx + 2,
                                   workoutName: store.name)
                    }
                }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(set.done ? .white : FG.muted.opacity(0.6))
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 9).fill(set.done ? FG.success : FG.secondary))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(set.done ? FG.success : FG.border, lineWidth: 1))
                    .opacity(!set.done && set.reps == nil ? 0.4 : 1)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(set.done
                  ? FG.ember.opacity(flashedSetId == set.id ? 0.32 : 0.14)
                  : (set.amrap ? FG.gold.opacity(0.07) : .clear))
            // inset so a tinted row never butts against the row separator
            .padding(.vertical, 2))
        .padding(.horizontal, -6)
        .animation(.easeOut(duration: 0.25), value: set.done)
    }

    /// Front-of-row glyph: the set's kind, or its number when it's a plain
    /// working set.
    private func setMarker(_ set: DraftSet, number: Int) -> String {
        if set.warmup { return "W" }
        if set.setType == "drop" { return "D" }
        if set.setType == "failure" { return "F" }
        if set.amrap { return "A" }
        return "\(number)"
    }

    private func markerColor(_ set: DraftSet) -> Color {
        if set.amrap { return FG.gold }
        if set.warmup { return FG.ember }
        if set.setType == "drop" { return FG.ember }
        if set.setType == "failure" { return FG.destructive }
        return FG.muted
    }

    private func valueField(id: String, width: CGFloat, placeholder: String, keyboard: UIKeyboardType,
                            accent: Bool = false,
                            get: @escaping () -> String, set: @escaping (String) -> Void) -> some View {
        TextField(placeholder, text: Binding(get: get, set: set))
            .keyboardType(keyboard)
            .multilineTextAlignment(.center)
            .font(.system(size: 15, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .focused($focusedField, equals: id)
            .selectAllOnFocus()
            .frame(width: width, height: 38)
            .background(RoundedRectangle(cornerRadius: 9).fill(accent ? FG.gold.opacity(0.10) : FG.background))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(focusedField == id ? FG.ember : (accent ? FG.gold.opacity(0.55) : FG.border),
                            lineWidth: focusedField == id ? 1.5 : (accent ? 1.5 : 1))
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
                Button {
                    rest.adjust(by: -15)
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "minus").font(.system(size: 10, weight: .bold))
                        Text("15")
                    }
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(FG.secondary))
                }
                Button {
                    rest.adjust(by: 15)
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                        Text("15")
                    }
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(FG.secondary))
                }
                Button {
                    rest.stop()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "forward.fill").font(.system(size: 11))
                        Text("Skip")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.8))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(FG.ember))
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

    private func restLabel(_ seconds: Int) -> String {
        seconds == 0 ? "Off" : "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    /// Heaviest weight in play for the exercise — filled sets first, then the
    /// server suggestion (PWA's plateWeightFor semantics).
    private func plateWeight(for idx: Int) -> Double? {
        guard store.exercises.indices.contains(idx) else { return nil }
        let ex = store.exercises[idx]
        let filled = ex.sets.compactMap(\.weight).filter { $0 > 0 }
        if let maxW = filled.max() { return maxW }
        return ex.suggestedWeight
    }

    // MARK: finish

    private func finish() async {
        finishing = true
        postError = nil
        let doc = store.buildSync(finished: true)
        do {
            finishSummary = try await ForgeAPI.sync(doc)
            rest.stop()
            store.music.stop()
            WorkoutStore.clearPersisted()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            finished = true
        } catch let error as APIError {
            // the server rejected the payload — a retry sends the same thing
            postError = error.localizedDescription
        } catch {
            // offline: queue it, it syncs automatically when the network is back
            SyncQueue.shared.enqueue(doc)
            rest.stop()
            store.music.stop()
            WorkoutStore.clearPersisted()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            queuedOffline = true
            finished = true
        }
        if finished {
            let start = store.startedAt
            let end = store.finishIntent ?? Date()
            Task { await HealthSync.saveWorkout(start: start, end: end) }
        }
        finishing = false
    }

    private var doneView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52)).foregroundStyle(FG.ember)
                .scaleEffect(donePopped ? 1 : 0.4)
                .opacity(donePopped ? 1 : 0)
                .onAppear {
                    withAnimation(.spring(duration: 0.45, bounce: 0.45)) { donePopped = true }
                }
            Text(queuedOffline ? "Saved on this phone" : "Saved to Forge")
                .font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
            Text("\(store.doneSets) sets · \(trim(store.volume)) kg · \(Int(Date().timeIntervalSince(store.startedAt) / 60)) min")
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(FG.muted)
            if queuedOffline {
                Text("No connection — it syncs to Forge automatically once you're back online.")
                    .font(.system(size: 13)).foregroundStyle(FG.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
            }
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
        guard !query.isEmpty else { return all }
        let match = ExerciseSearch.matcher(for: query)
        return all.filter { match($0.name) }
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

/// Quick peek at the last sessions of an exercise, without leaving the workout.
struct RecentSessionsSheet: View {
    let exerciseId: Int
    let name: String
    @State private var sessions: [RecentWorkout] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ZStack {
                FG.background.ignoresSafeArea()
                if loading {
                    ProgressView().tint(FG.ember)
                } else if sessions.isEmpty {
                    Text("No previous sessions of this exercise yet.")
                        .font(.system(size: 13)).foregroundStyle(FG.muted)
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(sessions, id: \.workout_id) { s in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(s.name)
                                            .font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(String(s.date.prefix(10)))
                                            .font(.system(size: 12).monospacedDigit()).foregroundStyle(FG.muted)
                                    }
                                    Text(s.sets.map { "\(trim($0.weight ?? 0))×\($0.reps)\($0.is_pr ? " 🏆" : "")" }
                                        .joined(separator: "  ·  "))
                                        .font(.system(size: 13).monospacedDigit())
                                        .foregroundStyle(FG.muted)
                                }
                                .padding(13)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 13).fill(FG.card))
                                .overlay(RoundedRectangle(cornerRadius: 13).stroke(FG.border, lineWidth: 1))
                            }
                        }
                        .padding(18)
                    }
                }
            }
            .navigationTitle("Recent — \(name)")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
        .task {
            sessions = (try? await ForgeAPI.recent(exerciseId: exerciseId)) ?? []
            loading = false
        }
    }
}

/// Left-swipe to delete on custom rows: horizontal-dominant drags reveal a
/// trash zone; past the threshold the release deletes with a spring. Vertical
/// scrolling stays untouched.
struct SwipeToDelete<Content: View>: View {
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var horizontal = false

    private let revealWidth: CGFloat = 76
    private let deleteThreshold: CGFloat = -58

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset < -2 {
                HStack {
                    Spacer()
                    Image(systemName: "trash.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: revealWidth)
                        .scaleEffect(offset < deleteThreshold ? 1.15 : 1)
                        .animation(.spring(duration: 0.2), value: offset < deleteThreshold)
                }
                .frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(FG.destructive))
            }
            content()
                .offset(x: offset)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 24, coordinateSpace: .local)
                .onChanged { g in
                    // commit to horizontal only when the drag clearly is
                    if !horizontal {
                        guard abs(g.translation.width) > abs(g.translation.height) * 1.4 else { return }
                        horizontal = true
                    }
                    offset = min(0, max(-revealWidth - 14, g.translation.width))
                }
                .onEnded { g in
                    defer { horizontal = false }
                    if horizontal, offset < deleteThreshold {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.spring(duration: 0.25)) { offset = -500 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            onDelete()
                            offset = 0
                        }
                    } else {
                        withAnimation(.spring(duration: 0.3)) { offset = 0 }
                    }
                }
        )
    }
}
