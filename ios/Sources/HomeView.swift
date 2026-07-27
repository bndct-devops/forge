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
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(FG.ember)
                            .frame(width: 34, height: 34)
                            .overlay(Image(systemName: "dumbbell.fill").font(.system(size: 15)).foregroundStyle(.black.opacity(0.8)))
                        Text("Forge").font(.system(size: 21, weight: .semibold)).foregroundStyle(.white)
                        Spacer()
                        Menu {
                            Button("Unpair", role: .destructive) {
                                storedURL = ""
                                storedToken = ""
                            }
                        } label: {
                            Image(systemName: "gearshape").foregroundStyle(FG.muted).padding(6)
                        }
                    }
                    .padding(.top, 6)

                    if loading {
                        ProgressView().tint(FG.ember).frame(maxWidth: .infinity).padding(.vertical, 30)
                    } else if let error {
                        Text(error).font(.system(size: 13)).foregroundStyle(.red)
                    }

                    if !programs.isEmpty {
                        Text("PROGRAMS")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(FG.muted)
                            .padding(.top, 10)

                        ForEach(programs) { p in
                            Button {
                                Task { await startProgram(p) }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(p.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                                        Text("W\(p.next?.week ?? p.current_week)")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(FG.ember)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Capsule().fill(FG.emberSoft))
                                        Spacer()
                                        if startingProgram {
                                            ProgressView().tint(FG.ember)
                                        } else {
                                            Image(systemName: "play.fill").font(.system(size: 13)).foregroundStyle(FG.ember)
                                        }
                                    }
                                    if let next = p.next {
                                        Text("next: \(next.exercise_name)")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.9))
                                        Text(next.sets.map { "\(trim($0.weight))×\($0.reps)\($0.amrap ? "+" : "")" }.joined(separator: " · "))
                                            .font(.system(size: 12).monospacedDigit())
                                            .foregroundStyle(FG.muted)
                                    }
                                }
                                .padding(14)
                                .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .disabled(startingProgram || activeStore != nil)
                        }
                    }

                    Text("ROUTINES")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(FG.muted)
                        .padding(.top, 10)

                    ForEach(routines) { r in
                        Button {
                            start(r)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(r.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                                    Spacer()
                                    Image(systemName: "play.fill").font(.system(size: 13)).foregroundStyle(FG.ember)
                                }
                                Text(r.exercises.map(\.name).joined(separator: " · "))
                                    .font(.system(size: 12))
                                    .foregroundStyle(FG.muted)
                                    .lineLimit(2)
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        start(nil)
                    } label: {
                        HStack {
                            Image(systemName: "plus")
                            Text("Empty workout")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(FG.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(FG.border, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
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
                            Text("· \(store.doneSets) sets")
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
