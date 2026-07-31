import SwiftUI
import WidgetKit

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

                    WeightQuickLogView()
                        .padding(.top, 12)

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
            // debug hook: `-demo-amrap` builds a mock program session locally
            // (start-workout needs a write token) to eyeball the AMRAP row
            if CommandLine.arguments.contains("-demo-amrap"), let p = programs.first, let n = p.next {
                state.activeStore = WorkoutStore(server: mockProgramSession(p, n))
                state.showWorkout = true
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
            Task { await refreshWidgetSnapshot(programs: programs) }
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}

/// Refresh the home-screen widget's data: next program session + streak.
func refreshWidgetSnapshot(programs: [Program]) async {
    let stats = try? await ForgeAPI.stats()
    let goal = (try? await ForgeAPI.me())?.weekly_goal ?? 3
    let program = programs.first
    let next = program?.next
    WidgetSnapshot(
        programName: program?.name,
        nextExercise: next?.exercise_name,
        prescription: next?.sets.map { "\(trim($0.weight))×\($0.reps)\($0.amrap ? "+" : "")" }
            .joined(separator: " · "),
        accessory: next.flatMap { n in
            program?.lifts?.first { $0.id == n.lift_id }?.routine_name
        },
        week: next?.week,
        streakWeeks: stats?.streak_weeks ?? 0,
        weekWorkouts: stats?.weeks.last?.workouts ?? 0,
        weeklyGoal: goal,
        updated: Date()
    ).save()
    WidgetCenter.shared.reloadAllTimelines()
}

extension Routine: Equatable {
    static func == (lhs: Routine, rhs: Routine) -> Bool { lhs.id == rhs.id }
}

extension Program: Equatable {
    static func == (lhs: Program, rhs: Program) -> Bool { lhs.id == rhs.id }
}

// MARK: - quick weight log (PWA's WeightQuickLog row)

struct WeightQuickLogView: View {
    @State private var latest: MeasureLatest?
    @State private var ratePerWeek: Double?
    @State private var open = false
    @State private var value = ""
    @State private var busy = false

    var body: some View {
        Button {
            value = ""
            open = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "scalemass")
                    .font(.system(size: 14)).foregroundStyle(FG.ember)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10).fill(FG.emberSoft))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Log weight").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    if let latest {
                        (Text("\(trim(latest.value)) kg · \(relativeMeasureDate(latest.measured_at))")
                         + Text(ratePerWeek.map { r in
                             "  \(r > 0 ? "+" : "")\(trim(r))/wk"
                         } ?? ""))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(FG.muted)
                    } else {
                        Text("track it on the scale days")
                            .font(.system(size: 12)).foregroundStyle(FG.muted)
                    }
                }
                Spacer()
                Image(systemName: "plus").font(.system(size: 13, weight: .semibold)).foregroundStyle(FG.muted)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
        }
        .buttonStyle(Pressable())
        .task { await load() }
        .sheet(isPresented: $open) {
            NavigationStack {
                ZStack {
                    FG.background.ignoresSafeArea()
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Weight (kg)")
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                            TextField(latest.map { trim($0.value) } ?? "0", text: $value)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 22, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .frame(height: 54)
                                .background(RoundedRectangle(cornerRadius: 12).fill(FG.card))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(FG.border, lineWidth: 1))
                        }
                        Button {
                            Task { await save() }
                        } label: {
                            Text(busy ? "…" : "Save")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .background(RoundedRectangle(cornerRadius: 14).fill(FG.ember))
                                .foregroundStyle(.black.opacity(0.8))
                        }
                        .disabled(busy || Double(value.replacingOccurrences(of: ",", with: ".")) == nil)
                        .opacity(Double(value.replacingOccurrences(of: ",", with: ".")) == nil ? 0.5 : 1)
                        Spacer()
                    }
                    .padding(18)
                }
                .navigationTitle("Log weight")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { open = false }.foregroundStyle(FG.muted)
                    }
                }
            }
            .presentationDetents([.height(280)])
            .preferredColorScheme(.dark)
        }
    }

    private func load() async {
        latest = (try? await ForgeAPI.measurements())?.first { $0.kind == "Weight" }?.latest
        ratePerWeek = (try? await ForgeAPI.measurementTrend(kind: "Weight"))?.rate_per_week
    }

    private func save() async {
        guard let v = Double(value.replacingOccurrences(of: ",", with: ".")), v > 0 else { return }
        busy = true
        try? await ForgeAPI.addMeasurement(kind: "Weight", value: v, measuredAt: Date())
        open = false
        busy = false
        await load()
    }
}

/// Debug-only: a program session built locally, so the AMRAP treatment can be
/// eyeballed without a write token to call start-workout.
func mockProgramSession(_ p: Program, _ n: ProgramNext) -> ServerWorkout {
    let serverSets: [ServerSet] = n.sets.map { s in
        ServerSet(weight: s.weight,
                  reps: s.amrap ? nil : s.reps,
                  is_warmup: false,
                  set_type: s.amrap ? "amrap" : nil)
    }
    let previous: [RecentSet] = [
        RecentSet(weight: 60, reps: 8, is_pr: false, rpe: nil),
        RecentSet(weight: 70, reps: 8, is_pr: false, rpe: nil),
        RecentSet(weight: 80, reps: 9, is_pr: true, rpe: nil),
    ]
    let exercise = ServerExercise(
        id: -1, exercise_id: n.exercise_id, name: n.exercise_name,
        muscle_group: "Shoulders", rest_seconds: 150,
        superset_with_next: false, rep_min: nil, rep_max: nil,
        suggested_weight: nil, suggestion_kind: nil, note: nil,
        previous_sets: previous, sets: serverSets
    )
    return ServerWorkout(
        id: -1, name: "5/3/1 — \(n.exercise_name) (W\(n.week))",
        program_id: p.id, program_lift_id: n.lift_id,
        exercises: [exercise],
        program: ProgramStartInfo(week: n.week, sets: n.sets),
        amrap_target: AmrapTarget(we_id: -1, weight: n.sets.last?.weight ?? 0, beat_reps: 10)
    )
}
