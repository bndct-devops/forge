import SwiftUI

/// Edit an existing program: name, rounding, per-lift training max,
/// increment and accessory template, add/remove lifts. (Creating programs
/// stays in the PWA.)
struct ProgramEditorView: View {
    let program: Program
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss

    private struct EditorLift: Identifiable {
        let id = UUID()
        var serverId: Int?
        var exerciseId: Int
        var name: String
        var trainingMax: Double
        var increment: Double
        var routineId: Int?
    }

    @State private var name = ""
    @State private var rounding = 5.0
    @State private var lifts: [EditorLift] = []
    @State private var routines: [Routine] = []
    @State private var pickerOpen = false
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            ZStack {
                FG.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("Program name", text: $name)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 12).fill(FG.card))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(FG.border, lineWidth: 1))

                        HStack {
                            Text("Round weights to")
                                .font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                            Spacer()
                            Menu {
                                ForEach([2.5, 5.0], id: \.self) { r in
                                    Button {
                                        rounding = r
                                    } label: {
                                        if r == rounding {
                                            Label("\(trim(r)) kg", systemImage: "checkmark")
                                        } else {
                                            Text("\(trim(r)) kg")
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("\(trim(rounding)) kg").font(.system(size: 13, weight: .medium))
                                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 9).fill(FG.secondary))
                            }
                        }

                        ForEach(Array(lifts.enumerated()), id: \.element.id) { i, lift in
                            liftCard(lift, at: i)
                        }

                        Button {
                            pickerOpen = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                                Text("Add lift").font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(FG.ember)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .stroke(FG.border, style: StrokeStyle(lineWidth: 1, dash: [5])))
                        }
                        .buttonStyle(Pressable())
                        .disabled(lifts.count >= 10)

                        Text("The training max drives every prescription. Around 90% of a true 1RM is standard — when in doubt, go lower.")
                            .font(.system(size: 12)).foregroundStyle(FG.muted)

                        if let error {
                            Text(error).font(.system(size: 13)).foregroundStyle(FG.destructive)
                        }

                        Button {
                            Task { await save() }
                        } label: {
                            Text(busy ? "Saving…" : "Save program")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .background(RoundedRectangle(cornerRadius: 14).fill(FG.ember))
                                .foregroundStyle(.black.opacity(0.8))
                        }
                        .buttonStyle(Pressable())
                        .disabled(busy || lifts.isEmpty)
                        .opacity(lifts.isEmpty ? 0.5 : 1)

                        Color.clear.frame(height: 20)
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Edit program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(FG.muted)
                }
            }
        }
        .fullScreenCover(isPresented: $pickerOpen) {
            ExercisePicker { ex in
                lifts.append(EditorLift(
                    serverId: nil, exerciseId: ex.id, name: ex.name,
                    trainingMax: 60, increment: 2.5, routineId: nil
                ))
            }
        }
        .preferredColorScheme(.dark)
        .task {
            name = program.name
            rounding = program.rounding ?? 5.0
            lifts = (program.lifts ?? []).compactMap { l in
                guard let exId = l.exercise_id else { return nil }
                return EditorLift(
                    serverId: l.id, exerciseId: exId, name: l.name ?? "Lift",
                    trainingMax: l.training_max ?? 60,
                    increment: l.increment ?? 2.5,
                    routineId: l.routine_id
                )
            }
            routines = (try? await ForgeAPI.routines()) ?? []
        }
    }

    private func liftCard(_ lift: EditorLift, at i: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(lift.name)
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Button {
                    withAnimation(.spring(duration: 0.3)) { _ = lifts.remove(at: i) }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13)).foregroundStyle(FG.muted)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8).fill(FG.secondary))
                }
                .buttonStyle(.plain)
            }
            HStack {
                HStack(spacing: 8) {
                    Text("TM").font(.system(size: 13)).foregroundStyle(FG.muted)
                    TextField("60", text: Binding(
                        get: { trim(lifts[i].trainingMax) },
                        set: { lifts[i].trainingMax = Double($0.replacingOccurrences(of: ",", with: ".")) ?? lifts[i].trainingMax }
                    ))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9).fill(FG.secondary))
                    Text("kg").font(.system(size: 12)).foregroundStyle(FG.muted)
                }
                Spacer()
                HStack(spacing: 6) {
                    Text("+/cycle").font(.system(size: 13)).foregroundStyle(FG.muted)
                    Menu {
                        ForEach([2.5, 5.0], id: \.self) { inc in
                            Button {
                                lifts[i].increment = inc
                            } label: {
                                if inc == lift.increment {
                                    Label("+\(trim(inc)) kg", systemImage: "checkmark")
                                } else {
                                    Text("+\(trim(inc)) kg")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("+\(trim(lift.increment))")
                                .font(.system(size: 13, weight: .medium).monospacedDigit())
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 9).fill(FG.secondary))
                    }
                }
            }
            HStack(spacing: 6) {
                Text("Accessories").font(.system(size: 13)).foregroundStyle(FG.muted)
                Spacer()
                Menu {
                    Button {
                        lifts[i].routineId = nil
                    } label: {
                        if lift.routineId == nil {
                            Label("None", systemImage: "checkmark")
                        } else {
                            Text("None")
                        }
                    }
                    ForEach(routines) { r in
                        Button {
                            lifts[i].routineId = r.id
                        } label: {
                            if r.id == lift.routineId {
                                Label(r.name, systemImage: "checkmark")
                            } else {
                                Text(r.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(routines.first { $0.id == lift.routineId }?.name ?? "None")
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9).fill(FG.secondary))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }

    private func save() async {
        busy = true
        error = nil
        do {
            try await ForgeAPI.patchProgram(
                id: program.id,
                name: name.trimmingCharacters(in: .whitespaces),
                rounding: rounding,
                lifts: lifts.map { l in
                    [
                        "id": l.serverId,
                        "exercise_id": l.exerciseId,
                        "training_max": l.trainingMax,
                        "increment": l.increment,
                        "routine_id": l.routineId,
                    ]
                }
            )
            await onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }
}
