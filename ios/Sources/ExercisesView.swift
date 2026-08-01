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

    private struct Family: Identifiable {
        let head: LibraryExercise
        let variants: [LibraryExercise]
        var id: Int { head.id }
    }

    @State private var expandedFamilies: Set<Int> = []

    /// Searching flattens to plain matches; browsing groups variants under
    /// their family head (PWA semantics).
    private var grouped: [(String, [Family])] {
        if !query.isEmpty {
            let match = ExerciseSearch.matcher(for: query)
            let filtered = all.filter { match($0.name) }
            let dict = Dictionary(grouping: filtered) { $0.muscle_group ?? "Other" }
            return dict.sorted { $0.key < $1.key }.map { group, exs in
                (group, exs.map { Family(head: $0, variants: []) })
            }
        }
        let byRoot = Dictionary(grouping: all) { $0.variant_of_id ?? $0.id }
        var families: [Family] = []
        for (rootId, members) in byRoot {
            let head = members.first { $0.id == rootId } ?? members[0]
            let variants = members.filter { $0.id != head.id }
                .sorted { $0.name < $1.name }
            families.append(Family(head: head, variants: variants))
        }
        let dict = Dictionary(grouping: families) { $0.head.muscle_group ?? "Other" }
        return dict.sorted { $0.key < $1.key }.map { group, fams in
            (group, fams.sorted { $0.head.name < $1.head.name })
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                FG.background.ignoresSafeArea()
                if loading {
                    ProgressView().tint(FG.ember)
                } else {
                    List {
                        ForEach(grouped, id: \.0) { group, families in
                            Section {
                                ForEach(families) { family in
                                    HStack(spacing: 8) {
                                        NavigationLink(value: ExerciseRef(id: family.head.id, name: family.head.name)) {
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(family.head.name).font(.system(size: 15)).foregroundStyle(.white)
                                                Text(family.head.equipment ?? "")
                                                    .font(.system(size: 11)).foregroundStyle(FG.muted)
                                            }
                                        }
                                        if !family.variants.isEmpty {
                                            Button {
                                                withAnimation(.spring(duration: 0.3)) {
                                                    if expandedFamilies.contains(family.id) {
                                                        expandedFamilies.remove(family.id)
                                                    } else {
                                                        expandedFamilies.insert(family.id)
                                                    }
                                                }
                                            } label: {
                                                HStack(spacing: 3) {
                                                    Text("\(family.variants.count)")
                                                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                                    Image(systemName: "chevron.down")
                                                        .font(.system(size: 9, weight: .semibold))
                                                        .rotationEffect(.degrees(expandedFamilies.contains(family.id) ? 180 : 0))
                                                }
                                                .foregroundStyle(FG.ember)
                                                .padding(.horizontal, 8).padding(.vertical, 4)
                                                .background(Capsule().fill(FG.emberSoft))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .listRowBackground(FG.card)
                                    if expandedFamilies.contains(family.id) {
                                        ForEach(family.variants) { v in
                                            NavigationLink(value: ExerciseRef(id: v.id, name: v.name)) {
                                                HStack(spacing: 8) {
                                                    Rectangle().fill(FG.ember.opacity(0.5))
                                                        .frame(width: 2, height: 22)
                                                    VStack(alignment: .leading, spacing: 1) {
                                                        Text(v.name).font(.system(size: 14)).foregroundStyle(.white)
                                                        Text(v.equipment ?? "")
                                                            .font(.system(size: 11)).foregroundStyle(FG.muted)
                                                    }
                                                }
                                            }
                                            .listRowBackground(FG.card.opacity(0.6))
                                        }
                                    }
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
