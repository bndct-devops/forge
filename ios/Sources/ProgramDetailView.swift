import SwiftUI

/// The PWA's program view: upcoming sessions with prescribed weights/reps,
/// scrollable through the rest of the cycle. Start launches the next one.
struct ProgramDetailView: View {
    let program: Program
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [PreviewSession] = []
    @State private var loading = true
    @State private var starting = false

    var body: some View {
        NavigationStack {
            ZStack {
                FG.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(program.name)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.white)
                            Text("\(program.scheme_name) · Cycle \(program.cycle_number ?? 1) · Week \(program.current_week)/\(program.cycle_length ?? 4)")
                                .font(.system(size: 14))
                                .foregroundStyle(FG.muted)
                        }
                        .padding(.top, 4)

                        Button {
                            starting = true
                            Task {
                                await state.startProgram(id: program.id)
                                starting = false
                                if state.hasActive { dismiss() }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill").font(.system(size: 14))
                                Text(starting ? "starting…" : "Start session").font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(.black.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(RoundedRectangle(cornerRadius: 14).fill(FG.ember))
                            .opacity(state.hasActive || starting ? 0.4 : 1)
                        }
                        .buttonStyle(.plain)
                        .disabled(state.hasActive || starting)

                        if let err = state.startError {
                            Text(err).font(.system(size: 13)).foregroundStyle(FG.destructive)
                        }

                        Text("Upcoming")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.top, 10)

                        if loading {
                            ProgressView().tint(FG.ember).frame(maxWidth: .infinity).padding(.vertical, 30)
                        }

                        ForEach(sessions) { s in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Text("W\(s.week)")
                                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                                        .foregroundStyle(s.offset == 0 ? .black.opacity(0.8) : FG.ember)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(s.offset == 0 ? FG.ember : FG.emberSoft))
                                    Text(s.exercise_name)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Spacer()
                                    if s.offset == 0 {
                                        Text("next")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(FG.ember)
                                    } else if s.cycle_number != (program.cycle_number ?? 1) {
                                        Text("C\(s.cycle_number)")
                                            .font(.system(size: 11).monospacedDigit())
                                            .foregroundStyle(FG.muted)
                                    }
                                }
                                Text(s.sets.map { "\(trim($0.weight))×\($0.reps)\($0.amrap ? "+" : "")" }.joined(separator: " · ") + " kg")
                                    .font(.system(size: 16, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(.white)
                                HStack(spacing: 10) {
                                    Text("TM \(trim(s.training_max)) kg")
                                    if let beat = s.beat_reps {
                                        HStack(spacing: 3) {
                                            Image(systemName: "trophy.fill").font(.system(size: 10)).foregroundStyle(FG.gold)
                                            Text("\(beat)+ beats your best")
                                        }
                                    }
                                }
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(FG.muted)
                                if let routine = s.routine_name, let acc = s.accessories, !acc.isEmpty {
                                    Text("+ \(routine): \(acc.map(\.name).joined(separator: ", "))")
                                        .font(.system(size: 12))
                                        .foregroundStyle(FG.muted)
                                        .lineLimit(2)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(s.offset == 0 ? FG.ember.opacity(0.5) : FG.border, lineWidth: 1)
                            )
                        }

                        Color.clear.frame(height: 30)
                    }
                    .padding(.horizontal, 18)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(FG.muted)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            sessions = (try? await ForgeAPI.programPreview(id: program.id)) ?? []
            loading = false
        }
    }
}
