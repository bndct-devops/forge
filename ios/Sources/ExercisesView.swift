import SwiftUI

struct ExercisesView: View {
    @State private var all: [LibraryExercise] = []
    @State private var query = ""
    @State private var loading = true
    @State private var creating = false
    @State private var path = NavigationPath()

    private struct ExerciseRef: Hashable {
        let id: Int
        let name: String
    }

    private var grouped: [(String, [LibraryExercise])] {
        let filtered = query.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(query) }
        let dict = Dictionary(grouping: filtered) { $0.muscle_group ?? "Other" }
        return dict.sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                FG.background.ignoresSafeArea()
                if loading {
                    ProgressView().tint(FG.ember)
                } else {
                    List {
                        ForEach(grouped, id: \.0) { group, exercises in
                            Section {
                                ForEach(exercises) { ex in
                                    NavigationLink(value: ExerciseRef(id: ex.id, name: ex.name)) {
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        creating = true
                    } label: {
                        Image(systemName: "plus").foregroundStyle(FG.ember)
                    }
                }
            }
            .navigationDestination(for: ExerciseRef.self) { ref in
                ExerciseDetailView(exerciseId: ref.id, name: ref.name)
            }
            .sheet(isPresented: $creating) {
                ExerciseFormView(title: "New exercise", submitLabel: "Create") { name, group, equipment, grip in
                    let created = try await ForgeAPI.createExercise(
                        name: name, muscleGroup: group, equipment: equipment, grip: grip)
                    all = (try? await ForgeAPI.exercises()) ?? all
                    path.append(ExerciseRef(id: created.id, name: created.name))
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            all = (try? await ForgeAPI.exercises()) ?? []
            loading = false
            // debug hook: `-exercise <id>` opens a detail page at launch
            if let i = CommandLine.arguments.firstIndex(of: "-exercise"), i + 1 < CommandLine.arguments.count,
               let id = Int(CommandLine.arguments[i + 1]), path.isEmpty {
                let name = all.first { $0.id == id }?.name ?? ""
                path.append(ExerciseRef(id: id, name: name))
            }
        }
    }
}
