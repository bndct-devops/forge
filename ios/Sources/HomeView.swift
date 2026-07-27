import SwiftUI

struct HomeView: View {
    @State private var routines: [Routine] = []
    @State private var programs: [Program] = []
    @State private var loading = true
    @State private var error: String?
    @State private var startingProgram = false
    @State private var activeStore: WorkoutStore?
    @State private var showWorkout = false
    @AppStorage("forge_base_url") private var storedURL = ""
    @AppStorage("forge_token") private var storedToken = ""

    private func start(_ routine: Routine?) {
        activeStore = WorkoutStore(routine: routine)
        showWorkout = true
    }

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
                        Menu {
                            Button("Unpair", role: .destructive) {
                                storedURL = ""
                                storedToken = ""
                            }
                        } label: {
                            Image(systemName: "gearshape").font(.system(size: 17)).foregroundStyle(FG.muted).padding(6)
                        }
                    }
                    .padding(.top, 8)

                    Button {
                        start(nil)
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
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                    .disabled(activeStore != nil)

                    if loading {
                        ProgressView().tint(FG.ember).frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else if let error {
                        Text(error).font(.system(size: 13)).foregroundStyle(FG.destructive).padding(.top, 16)
                    }

                    if !routines.isEmpty {
                        Text("Templates")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.top, 28)

                        ForEach(routines) { r in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(r.name)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(.white)
                                Text(r.exercises.map { "\($0.set_count) × \($0.name)" }.joined(separator: ", "))
                                    .font(.system(size: 14))
                                    .foregroundStyle(FG.muted)
                                    .lineLimit(2)
                                Button {
                                    start(r)
                                } label: {
                                    Text("Start workout")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(FG.ember)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 44)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(FG.emberSoft))
                                }
                                .buttonStyle(.plain)
                                .disabled(activeStore != nil)
                            }
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: 16).fill(FG.card))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(FG.border, lineWidth: 1))
                            .padding(.top, 12)
                        }
                    }

                    if !programs.isEmpty {
                        Text("Programs")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.top, 28)

                        ForEach(programs) { p in
                            VStack(alignment: .leading, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Text("\(p.scheme_name) · Cycle \(p.cycle_number ?? 1) · Week \(p.current_week)/\(p.cycle_length ?? 4)")
                                        .font(.system(size: 13))
                                        .foregroundStyle(FG.muted)
                                }
                                if let next = p.next {
                                    Button {
                                        Task { await startProgram(p) }
                                    } label: {
                                        HStack(spacing: 10) {
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
                                            Spacer()
                                            if startingProgram {
                                                ProgressView().tint(FG.ember)
                                            } else {
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundStyle(FG.muted)
                                            }
                                        }
                                        .padding(14)
                                        .background(RoundedRectangle(cornerRadius: 12).fill(FG.secondary.opacity(0.7)))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(startingProgram || activeStore != nil)
                                }
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
            if let store = activeStore, !showWorkout {
                resumeBar(store)
            }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
        .refreshable { await load() }
        .fullScreenCover(isPresented: $showWorkout) {
            if let store = activeStore {
                ActiveWorkoutView(
                    store: store,
                    onMinimize: { showWorkout = false },
                    onEnd: {
                        showWorkout = false
                        activeStore = nil
                        Task { await load() }
                    }
                )
            }
        }
    }

    private func resumeBar(_ store: WorkoutStore) -> some View {
        VStack {
            Spacer()
            Button {
                showWorkout = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "dumbbell.fill").font(.system(size: 14)).foregroundStyle(FG.ember)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(store.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        HStack(spacing: 4) {
                            Text(store.startedAt, style: .timer)
                            Text("· \(store.doneSets) \(store.doneSets == 1 ? "set" : "sets")")
                        }
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(FG.muted)
                    }
                    Spacer()
                    Text("Resume")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FG.ember)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 16).fill(FG.card))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(FG.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private func startProgram(_ p: Program) async {
        startingProgram = true
        error = nil
        do {
            let server = try await ForgeAPI.startProgramWorkout(programId: p.id)
            activeStore = WorkoutStore(server: server)
            showWorkout = true
        } catch {
            self.error = error.localizedDescription
        }
        startingProgram = false
    }

    private func load() async {
        do {
            routines = try await ForgeAPI.routines()
            programs = (try? await ForgeAPI.programs()) ?? []
            error = nil
            if CommandLine.arguments.contains("-demo-start"), let first = routines.first {
                start(first)
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
