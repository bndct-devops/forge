import SwiftUI

@main
struct ForgeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Forge design tokens — the family neutrals with the ember accent.
enum FG {
    static let background = Color(red: 0.059, green: 0.051, blue: 0.047) // #0f0d0c
    static let card = Color(red: 0.102, green: 0.094, blue: 0.086)       // #1a1816
    static let secondary = Color(red: 0.153, green: 0.145, blue: 0.137)  // #272523
    static let border = Color.white.opacity(0.16)
    static let muted = Color(red: 0.682, green: 0.667, blue: 0.647)      // #aeaaa5
    static let ember = Color(red: 0.871, green: 0.518, blue: 0.310)      // #de844f
    static let emberSoft = Color(red: 0.871, green: 0.518, blue: 0.310).opacity(0.16)
    static let gold = Color(red: 0.765, green: 0.604, blue: 0.333)       // #c39a55
    static let success = Color(red: 0.435, green: 0.718, blue: 0.537)
    static let destructive = Color(red: 1.0, green: 0.396, blue: 0.341)  // #ff6557
}

/// Workout session state, shared app-wide so the active workout and its
/// resume bar overlay every tab.
@MainActor
final class AppState: ObservableObject {
    @Published var activeStore: WorkoutStore?
    @Published var showWorkout = false
    @Published var startError: String?

    init() {
        // restore a draft the app was killed on — nothing logged is lost
        if let draft = WorkoutStore.loadPersisted() {
            activeStore = WorkoutStore(restored: draft)
        }
    }

    var hasActive: Bool { activeStore != nil }

    func start(routine: Routine?) {
        activeStore = WorkoutStore(routine: routine)
        showWorkout = true
    }

    func startProgram(id: Int) async {
        startError = nil
        do {
            let server = try await ForgeAPI.startProgramWorkout(programId: id)
            activeStore = WorkoutStore(server: server)
            showWorkout = true
        } catch {
            startError = error.localizedDescription
        }
    }

    func end() {
        showWorkout = false
        activeStore = nil
        WorkoutStore.clearPersisted()
    }
}

struct RootView: View {
    @AppStorage("forge_base_url") private var baseURL = ""
    @AppStorage("forge_token") private var token = ""
    @StateObject private var state = AppState()
    @State private var tab: Int = {
        // debug hook: `-tab history|exercises|stats` selects a tab at launch
        if let i = CommandLine.arguments.firstIndex(of: "-tab"), i + 1 < CommandLine.arguments.count {
            return ["workout": 0, "history": 1, "exercises": 2, "stats": 3][CommandLine.arguments[i + 1]] ?? 0
        }
        return 0
    }()

    var body: some View {
        if baseURL.isEmpty || token.isEmpty {
            PairingView()
        } else {
            ZStack {
                TabView(selection: $tab) {
                    HomeView()
                        .tabItem { Label("Workout", systemImage: "dumbbell.fill") }
                        .tag(0)
                    HistoryView()
                        .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                        .tag(1)
                    ExercisesView()
                        .tabItem { Label("Exercises", systemImage: "figure.strengthtraining.traditional") }
                        .tag(2)
                    StatsView()
                        .tabItem { Label("Stats", systemImage: "chart.line.uptrend.xyaxis") }
                        .tag(3)
                }
                .tint(FG.ember)
                if let store = state.activeStore, !state.showWorkout {
                    ResumeBar(store: store) { state.showWorkout = true }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.35), value: state.showWorkout)
            .environmentObject(state)
            .preferredColorScheme(.dark)
            .fullScreenCover(isPresented: $state.showWorkout) {
                if let store = state.activeStore {
                    ActiveWorkoutView(
                        store: store,
                        onMinimize: { state.showWorkout = false },
                        onEnd: { state.end() }
                    )
                }
            }
        }
    }
}

struct ResumeBar: View {
    @ObservedObject var store: WorkoutStore
    let onResume: () -> Void

    var body: some View {
        VStack {
            Spacer()
            Button(action: onResume) {
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
            .padding(.bottom, 60)
        }
    }
}
