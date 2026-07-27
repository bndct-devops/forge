import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @State private var routines: [Routine] = []
    @State private var programs: [Program] = []
    @State private var loading = true
    @State private var error: String?
    @State private var previewProgram: Program?
    @AppStorage("forge_base_url") private var storedURL = ""
    @AppStorage("forge_paired") private var storedPaired = false
    @State private var showSettings = false

    private struct EditorTarget: Identifiable {
        let id: Int  // 0 = new
        var routineId: Int? { id == 0 ? nil : id }
    }

    @State private var editorTarget: EditorTarget?
    @State private var deleteTarget: Routine?

    var body: some View {
        ZStack {
            FG.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Workout")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(.white)
                        Spacer()
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape").font(.system(size: 17)).foregroundStyle(FG.muted).padding(6)
                        }
                    }
                    .padding(.top, 8)

                    Button {
                        state.start(routine: nil)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill").font(.system(size: 15))
                            Text("Start empty workout").font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundStyle(.black.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(RoundedRectangle(cornerRadius: 16).fill(FG.ember))
                    }
                    .buttonStyle(Pressable())
                    .padding(.top, 16)
                    .disabled(state.hasActive)

                    if loading {
                        ProgressView().tint(FG.ember).frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else if let error {
                        Text(error).font(.system(size: 13)).foregroundStyle(FG.destructive).padding(.top, 16)
                    }
                    if let startError = state.startError {
                        Text(startError).font(.system(size: 13)).foregroundStyle(FG.destructive).padding(.top, 12)
                    }

                    if !programs.isEmpty {
                        Text("Programs")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.top, 28)

                        ForEach(programs) { p in
                            Button {
                                previewProgram = p
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(p.name)
                                                .font(.system(size: 17, weight: .semibold))
                                                .foregroundStyle(.white)
                                            Text("\(p.scheme_name) · Cycle \(p.cycle_number ?? 1) · Week \(p.current_week)/\(p.cycle_length ?? 4)")
                                                .font(.system(size: 13))
                                                .foregroundStyle(FG.muted)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(FG.muted)
                                    }
                                    if let next = p.next {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Next · \(next.exercise_name)")
                                                .font(.system(size: 13))
                                                .foregroundStyle(FG.muted)
                                            Text(next.sets.map { "\(trim($0.weight))×\($0.reps)\($0.amrap ? "+" : "")" }.joined(separator: " · ") + " kg")
                                                .font(.system(size: 16, weight: .semibold).monospacedDigit())
                                                .foregroundStyle(.white)
                                            if let accessory = p.lifts?.first(where: { $0.id == next.lift_id })?.routine_name {
                                                Text("+ \(accessory)")
                                                    .font(.system(size: 12))
                                                    .foregroundStyle(FG.muted)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(14)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(FG.secondary.opacity(0.7)))
                                    }
                                }
                                .padding(16)
                                .background(RoundedRectangle(cornerRadius: 16).fill(FG.card))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(FG.border, lineWidth: 1))
                            }
                            .buttonStyle(Pressable())
                            .padding(.top, 12)
                        }
                    }

                    HStack {
                        Text("Templates")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                        Spacer()
                        Button {
                            editorTarget = EditorTarget(id: 0)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                                Text("New").font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(FG.ember)
                        }
                        .buttonStyle(Pressable())
                    }
                    .padding(.top, 28)

                    if !routines.isEmpty {
                        ForEach(routines) { r in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(r.name)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Menu {
                                        Button {
                                            editorTarget = EditorTarget(id: r.id)
                                        } label: {
                                            Label("Edit template", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            deleteTarget = r
                                        } label: {
                                            Label("Delete template", systemImage: "trash")
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 13)).foregroundStyle(FG.muted).padding(6)
                                    }
                                }
                                Text(r.exercises.map { "\($0.set_count) × \($0.name)" }.joined(separator: ", "))
                                    .font(.system(size: 14))
                                    .foregroundStyle(FG.muted)
                                    .lineLimit(2)
                                Button {
                                    state.start(routine: r)
                                } label: {
                                    Text("Start workout")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(FG.ember)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 44)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(FG.emberSoft))
                                }
                                .buttonStyle(Pressable())
                                .disabled(state.hasActive)
                            }
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 16).fill(FG.card))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(FG.border, lineWidth: 1))
                            .padding(.top, 12)
                        }
                    }

                    Color.clear.frame(height: 90)
                }
                .padding(.horizontal, 18)
            }
        }
        .task {
            await load()
            // debug hooks: `-settings` / `-edit-template` open sheets at launch
            if CommandLine.arguments.contains("-settings") { showSettings = true }
            if CommandLine.arguments.contains("-edit-template"), let first = routines.first {
                editorTarget = EditorTarget(id: first.id)
            }
            if CommandLine.arguments.contains("-program"), let first = programs.first {
                previewProgram = first
            }
        }
        .refreshable { await load() }
        .sheet(item: $previewProgram) { p in
            ProgramDetailView(program: p)
        }
        .sheet(item: $editorTarget) { target in
            RoutineEditorView(routineId: target.routineId) { await load() }
        }
        .alert("Delete \"\(deleteTarget?.name ?? "")\"?", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let r = deleteTarget {
                    Task {
                        try? await ForgeAPI.deleteRoutine(id: r.id)
                        await load()
                    }
                }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("Logged workouts keep their history.")
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView {
                    Keychain.delete("forge_token")
                    UserDefaults.standard.removeObject(forKey: "forge_token")
                    showSettings = false
                    storedURL = ""
                    storedPaired = false
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { showSettings = false }.foregroundStyle(FG.ember)
                    }
                }
            }
        }
        .onChange(of: state.showWorkout) { _, showing in
            if !showing { Task { await load() } }
        }
    }

    private func load() async {
        do {
            routines = try await ForgeAPI.routines()
            programs = (try? await ForgeAPI.programs()) ?? []
            error = nil
            if CommandLine.arguments.contains("-demo-start"), let first = routines.first {
                state.start(routine: first)
            }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

extension Routine: Equatable {
    static func == (lhs: Routine, rhs: Routine) -> Bool { lhs.id == rhs.id }
}

extension Program: Equatable {
    static func == (lhs: Program, rhs: Program) -> Bool { lhs.id == rhs.id }
}
