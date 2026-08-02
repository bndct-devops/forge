import SwiftUI

struct WorkoutDetailView: View {
    let workoutId: Int
    let onChanged: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var workout: WorkoutFull?
    @State private var loading = true
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false
    @State private var editMode = false

    var body: some View {
        ZStack {
            FG.background.ignoresSafeArea()
            if loading {
                ProgressView().tint(FG.ember)
            } else if let w = workout {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(fmtDateLong(w.started_at))
                                .font(.system(size: 13))
                                .foregroundStyle(FG.muted)
                            HStack(spacing: 14) {
                                if let d = w.duration_seconds { headStat("\(d / 60)", "min") }
                                if let v = w.total_volume { headStat(trim(v), "kg") }
                                if let s = w.total_sets { headStat("\(s)", "sets") }
                                if let p = w.pr_count, p > 0 { headStat("\(p)", "PR", gold: true) }
                            }
                            if editMode {
                                timeEditor(w)
                            }
                        }
                        .padding(.top, 4)

                        if let notes = w.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.system(size: 13))
                                .foregroundStyle(FG.muted)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 12).fill(FG.card))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(FG.border, lineWidth: 1))
                        }

                        ForEach(Array(w.exercises.enumerated()), id: \.offset) { _, ex in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    if let exerciseId = ex.exercise_id {
                                        NavigationLink {
                                            ExerciseDetailView(exerciseId: exerciseId, name: ex.name)
                                        } label: {
                                            HStack(spacing: 4) {
                                                Text(ex.name)
                                                    .font(.system(size: 15, weight: .semibold))
                                                    .lineLimit(1)
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 10, weight: .semibold))
                                            }
                                            .foregroundStyle(FG.ember)
                                        }
                                        .buttonStyle(.plain)
                                    } else {
                                        Text(ex.name)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(FG.ember)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if let mg = ex.muscle_group {
                                        Text(mg)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(FG.muted)
                                            .padding(.horizontal, 7).padding(.vertical, 3)
                                            .background(Capsule().fill(FG.secondary))
                                    }
                                }
                                ForEach(Array(ex.sets.enumerated()), id: \.offset) { i, s in
                                    if editMode, let setId = s.id {
                                        EditableSetRow(index: i + 1, set: s, setId: setId) {
                                            await load()
                                            await onChanged()
                                        }
                                    } else {
                                        HStack(spacing: 10) {
                                            Text("\(i + 1)")
                                                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                                .foregroundStyle(FG.muted)
                                                .frame(width: 20, alignment: .leading)
                                            Text("\(trim(s.weight ?? 0)) kg × \(s.reps ?? 0)")
                                                .font(.system(size: 14).monospacedDigit())
                                                .foregroundStyle(.white)
                                            if s.is_warmup == true { badge("W") }
                                            if s.set_type == "drop" { badge("D") }
                                            if s.set_type == "failure" { badge("F") }
                                            if let rpe = s.rpe { badge("@\(trim(rpe))") }
                                            Spacer()
                                            if s.is_pr == true {
                                                Image(systemName: "trophy.fill").font(.system(size: 12)).foregroundStyle(FG.gold)
                                            }
                                        }
                                        .padding(.vertical, 3)
                                    }
                                }
                                if editMode, let weId = ex.id {
                                    HStack {
                                        Button {
                                            Task {
                                                try? await ForgeAPI.addSet(workoutId: workoutId, workoutExerciseId: weId)
                                                await load()
                                                await onChanged()
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                                                Text("Add set").font(.system(size: 13, weight: .medium))
                                            }
                                            .foregroundStyle(FG.ember)
                                        }
                                        .buttonStyle(.plain)
                                        Spacer()
                                        Button {
                                            Task {
                                                try? await ForgeAPI.removeWorkoutExercise(workoutId: workoutId, workoutExerciseId: weId)
                                                await load()
                                                await onChanged()
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "trash").font(.system(size: 11))
                                                Text("Remove exercise").font(.system(size: 13, weight: .medium))
                                            }
                                            .foregroundStyle(FG.destructive)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.top, 6)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
                        }

                        if let music = w.music, !music.isEmpty {
                            soundtrackCard(music, w)
                        }

                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 18)
                }
            }

            if confirmDelete {
                deleteModal
            }
        }
        .navigationTitle(workout?.name ?? "Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let w = workout {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: shareImage(w),
                        preview: SharePreview("Forge workout", image: shareImage(w))
                    ) {
                        Image(systemName: "square.and.arrow.up").foregroundStyle(FG.ember)
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { editMode.toggle() }
                    } label: {
                        Label(editMode ? "Done editing" : "Edit sets",
                              systemImage: editMode ? "checkmark" : "slider.horizontal.3")
                    }
                    Button {
                        newName = workout?.name ?? ""
                        renaming = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete workout", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(FG.muted)
                }
            }
        }
        .alert("Rename workout", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") {
                Task {
                    try? await ForgeAPI.patchWorkout(id: workoutId, name: newName, notes: nil)
                    await load()
                    await onChanged()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    private var deleteModal: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().onTapGesture { confirmDelete = false }
            VStack(spacing: 6) {
                Text("Delete workout?")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                Text("This removes it from your history and recomputes PRs.")
                    .font(.system(size: 13)).foregroundStyle(FG.muted).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button {
                        confirmDelete = false
                    } label: {
                        Text("Keep").font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 12).fill(FG.secondary))
                            .foregroundStyle(.white)
                    }
                    Button {
                        Task {
                            try? await ForgeAPI.deleteWorkout(id: workoutId)
                            await onChanged()
                            dismiss()
                        }
                    } label: {
                        Text("Delete").font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity).frame(height: 44)
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

    /// Edit-mode start/end pickers — corrects mis-stamped times (e.g. a
    /// finish that only synced after retries).
    private func timeEditor(_ w: WorkoutFull) -> some View {
        let iso = ISO8601DateFormatter()
        let started = iso.date(from: String(w.started_at.prefix(19)) + "Z") ?? Date()
        let finished = w.finished_at.flatMap { iso.date(from: String($0.prefix(19)) + "Z") }
        return VStack(alignment: .leading, spacing: 2) {
            DatePicker("Started", selection: Binding(
                get: { started },
                set: { newValue in
                    Task {
                        try? await ForgeAPI.patchWorkout(id: workoutId, startedAt: newValue)
                        await load()
                        await onChanged()
                    }
                }
            ))
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .tint(FG.ember)
            if let finished {
                DatePicker("Finished", selection: Binding(
                    get: { finished },
                    set: { newValue in
                        Task {
                            try? await ForgeAPI.patchWorkout(id: workoutId, finishedAt: newValue)
                            await load()
                            await onChanged()
                        }
                    }
                ))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .tint(FG.ember)
            }
        }
        .padding(.top, 8)
    }

    // MARK: soundtrack

    private func soundtrackCard(_ music: [WorkoutSongOut], _ w: WorkoutFull) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FG.muted)
                Text("Soundtrack")
                    .font(.system(size: 11, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(FG.muted)
                Spacer()
                Text("\(music.count) song\(music.count == 1 ? "" : "s")")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(FG.muted)
            }
            ForEach(Array(music.enumerated()), id: \.offset) { _, song in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(song.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let artist = song.artist {
                            Text(artist)
                                .font(.system(size: 11))
                                .foregroundStyle(FG.muted)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 12)
                    // ≈ marks a song Apple Music remembered but the app
                    // never saw play — its placement is approximate
                    Text((song.source == "inferred" ? "≈ " : "") + songContext(song, in: w))
                        .font(.system(size: 11))
                        .foregroundStyle(FG.muted)
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }

    /// What was happening while the song ran: the exercises whose sets were
    /// checked off inside its play window, else the wall-clock start.
    private func songContext(_ song: WorkoutSongOut, in w: WorkoutFull) -> String {
        guard let start = parseISOUTC(song.started_at) else { return "" }
        let end = parseISOUTC(song.ended_at) ?? start
        var names: [String] = []
        for ex in w.exercises {
            let hit = ex.sets.contains { s in
                guard let t = parseISOUTC(s.completed_at) else { return false }
                return t >= start && t <= end
            }
            if hit, !names.contains(ex.name) { names.append(ex.name) }
        }
        if names.isEmpty {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f.string(from: start)
        }
        if names.count > 2 {
            return names.prefix(2).joined(separator: " · ") + " · …"
        }
        return names.joined(separator: " · ")
    }

    private func headStat(_ value: String, _ unit: String, gold: Bool = false) -> some View {
        HStack(spacing: 3) {
            Text(value).font(.system(size: 17, weight: .semibold).monospacedDigit())
            Text(unit).font(.system(size: 12))
        }
        .foregroundStyle(gold ? FG.gold : .white)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(FG.ember)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(FG.emberSoft))
    }

    @MainActor
    private func shareImage(_ w: WorkoutFull) -> Image {
        let date = ISO8601DateFormatter().date(from: String(w.started_at.prefix(19)) + "Z") ?? Date()
        // rebuild the PR list from the stored trophy flags
        var prs: [FinishPR] = []
        for ex in w.exercises {
            for s in ex.sets where s.is_pr == true {
                let isWeight = (s.weight ?? 0) > 0
                prs.append(FinishPR(
                    exercise_name: ex.name,
                    kind: isWeight ? "weight" : "reps",
                    value: isWeight ? s.weight : (s.reps).map(Double.init),
                    reps: s.reps
                ))
            }
        }
        return renderShareCard(ShareCard(
            name: w.name,
            date: date,
            volume: w.total_volume ?? 0,
            sets: w.total_sets ?? 0,
            minutes: (w.duration_seconds ?? 0) / 60,
            prs: prs,
            workoutNumber: nil
        ))
    }

    private func load() async {
        workout = try? await ForgeAPI.workoutDetail(id: workoutId)
        loading = false
        // debug hook: `-edit-sets` starts in edit mode
        if CommandLine.arguments.contains("-edit-sets") { editMode = true }
    }
}

/// Inline editor for one logged set: weight/reps fields that PATCH on
/// commit, warm-up toggle, delete.
private struct EditableSetRow: View {
    let index: Int
    let set: WorkoutFullSet
    let setId: Int
    let onChanged: () async -> Void

    @State private var weightText = ""
    @State private var repsText = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index)")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(FG.muted)
                .frame(width: 20, alignment: .leading)
            TextField("kg", text: $weightText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 62, height: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(FG.secondary))
                .focused($focused)
            Text("×").font(.system(size: 13)).foregroundStyle(FG.muted)
            TextField("reps", text: $repsText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 50, height: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(FG.secondary))
                .focused($focused)
            Button {
                Task {
                    try? await ForgeAPI.patchSet(id: setId, weight: nil, reps: nil,
                                                 warmup: !(set.is_warmup ?? false))
                    await onChanged()
                }
            } label: {
                Text("W")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(set.is_warmup == true ? FG.ember : FG.muted)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(set.is_warmup == true ? FG.emberSoft : FG.secondary))
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                Task {
                    try? await ForgeAPI.deleteSet(id: setId)
                    await onChanged()
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12)).foregroundStyle(FG.muted)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
        .onAppear {
            weightText = set.weight.map(trim) ?? ""
            repsText = set.reps.map(String.init) ?? ""
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { commit() }
        }
    }

    private func commit() {
        let w = Double(weightText.replacingOccurrences(of: ",", with: "."))
        let r = Int(repsText)
        guard w != set.weight || r != set.reps, w != nil || r != nil else { return }
        Task {
            try? await ForgeAPI.patchSet(id: setId, weight: w, reps: r, warmup: nil)
            await onChanged()
        }
    }
}

/// Server timestamps are UTC, sometimes with an offset suffix, sometimes
/// naive — prefix(19)+Z normalises both (same trick as fmtDateLong).
func parseISOUTC(_ iso: String?) -> Date? {
    guard let iso, iso.count >= 19 else { return nil }
    return ISO8601DateFormatter().date(from: String(iso.prefix(19)) + "Z")
}

func fmtDateLong(_ iso: String) -> String {
    guard let d = ISO8601DateFormatter().date(from: String(iso.prefix(19)) + "Z") else {
        return String(iso.prefix(10))
    }
    let f = DateFormatter()
    f.dateFormat = "EEEE, d MMMM yyyy · HH:mm"
    return f.string(from: d)
}
