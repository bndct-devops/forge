import SwiftUI

struct ExercisesView: View {
    @State private var all: [LibraryExercise] = []
    @State private var records: [RecordEntry] = []
    @State private var query = ""
    @State private var loading = true

    private var grouped: [(String, [LibraryExercise])] {
        let filtered = query.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(query) }
        let dict = Dictionary(grouping: filtered) { $0.muscle_group ?? "Other" }
        return dict.sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FG.background.ignoresSafeArea()
                if loading {
                    ProgressView().tint(FG.ember)
                } else {
                    List {
                        ForEach(grouped, id: \.0) { group, exercises in
                            Section {
                                ForEach(exercises) { ex in
                                    NavigationLink {
                                        ExerciseDetailView(exercise: ex, record: records.first { $0.exercise_id == ex.id })
                                    } label: {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(ex.name).font(.system(size: 15)).foregroundStyle(.white)
                                            Text(ex.equipment ?? "")
                                                .font(.system(size: 11)).foregroundStyle(FG.muted)
                                        }
                                    }
                                    .listRowBackground(FG.card)
                                }
                            } header: {
                                Text(group)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(FG.muted)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .searchable(text: $query)
                }
            }
            .navigationTitle("Exercises")
            .navigationBarTitleDisplayMode(.large)
        }
        .preferredColorScheme(.dark)
        .task {
            all = (try? await ForgeAPI.exercises()) ?? []
            records = (try? await ForgeAPI.records()) ?? []
            loading = false
        }
    }
}

struct ExerciseDetailView: View {
    let exercise: LibraryExercise
    let record: RecordEntry?
    @State private var recent: [RecentWorkout] = []
    @State private var loading = true

    var body: some View {
        ZStack {
            FG.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        ForEach([exercise.muscle_group, exercise.equipment].compactMap { $0 }, id: \.self) { chip in
                            Text(chip)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(FG.muted)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(FG.secondary))
                        }
                    }
                    .padding(.top, 4)

                    if let record {
                        HStack(spacing: 10) {
                            if let bw = record.best_weight {
                                statTile("Best set", "\(trim(bw.weight)) kg × \(bw.reps)")
                            }
                            if let rm = record.best_1rm {
                                statTile("Est. 1RM", "\(trim(rm.value)) kg")
                            }
                            statTile("Sessions", "\(record.sessions)")
                        }
                    }

                    Text("Recent")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.top, 6)

                    if loading {
                        ProgressView().tint(FG.ember).frame(maxWidth: .infinity).padding(.vertical, 20)
                    } else if recent.isEmpty {
                        Text("No sessions yet.").font(.system(size: 13)).foregroundStyle(FG.muted)
                    }

                    ForEach(recent, id: \.workout_id) { w in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(w.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                                Spacer()
                                Text(String(w.date.prefix(10)))
                                    .font(.system(size: 12).monospacedDigit())
                                    .foregroundStyle(FG.muted)
                            }
                            Text(w.sets.map { s in
                                "\(trim(s.weight ?? 0))×\(s.reps)\(s.is_pr ? " 🏅" : "")"
                            }.joined(separator: " · "))
                                .font(.system(size: 14).monospacedDigit())
                                .foregroundStyle(FG.muted)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
                    }

                    Color.clear.frame(height: 30)
                }
                .padding(.horizontal, 18)
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            recent = (try? await ForgeAPI.recent(exerciseId: exercise.id)) ?? []
            loading = false
        }
    }

    private func statTile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(FG.muted)
            Text(value).font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FG.border, lineWidth: 1))
    }
}
