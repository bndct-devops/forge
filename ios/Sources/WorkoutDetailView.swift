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
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
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
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
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

    private func load() async {
        workout = try? await ForgeAPI.workoutDetail(id: workoutId)
        loading = false
    }
}

func fmtDateLong(_ iso: String) -> String {
    guard let d = ISO8601DateFormatter().date(from: String(iso.prefix(19)) + "Z") else {
        return String(iso.prefix(10))
    }
    let f = DateFormatter()
    f.dateFormat = "EEEE, d MMMM yyyy · HH:mm"
    return f.string(from: d)
}
