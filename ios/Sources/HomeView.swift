import SwiftUI

struct HomeView: View {
    @State private var routines: [Routine] = []
    @State private var loading = true
    @State private var error: String?
    @State private var activeRoutine: Routine?
    @State private var startEmpty = false
    @AppStorage("forge_base_url") private var storedURL = ""
    @AppStorage("forge_token") private var storedToken = ""

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

                    Text("ROUTINES")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(FG.muted)
                        .padding(.top, 10)

                    if loading {
                        ProgressView().tint(FG.ember).frame(maxWidth: .infinity).padding(.vertical, 30)
                    } else if let error {
                        Text(error).font(.system(size: 13)).foregroundStyle(.red)
                    }

                    ForEach(routines) { r in
                        Button {
                            activeRoutine = r
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
                        startEmpty = true
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
        }
        .preferredColorScheme(.dark)
        .task { await load() }
        .refreshable { await load() }
        .fullScreenCover(item: $activeRoutine) { r in
            ActiveWorkoutView(store: WorkoutStore(routine: r))
        }
        .fullScreenCover(isPresented: $startEmpty) {
            ActiveWorkoutView(store: WorkoutStore(routine: nil))
        }
    }

    private func load() async {
        do {
            routines = try await ForgeAPI.routines()
            error = nil
            if CommandLine.arguments.contains("-demo-start"), let first = routines.first {
                activeRoutine = first
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
