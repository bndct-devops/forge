import SwiftUI

/// Port of the PWA's RoutineEditorPage: create or edit a workout template.
struct RoutineEditorView: View {
    let routineId: Int?
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss

    private struct EditorExercise: Identifiable {
        let id = UUID()
        var exerciseId: Int
        var name: String
        var setCount: Int
        var restSeconds: Int?     // nil = account default
        var supersetWithNext: Bool
        var repMin: Int?
        var repMax: Int?
        var increment: Double?
        var amrapLastSet: Bool
    }

    @State private var name = ""
    @State private var exercises: [EditorExercise] = []
    @State private var loading = true
    @State private var pickerOpen = false
    @State private var error: String?
    @State private var busy = false
    @State private var dirty = false
    @State private var confirmLeave = false

    private let restOptions = [0, 30, 45, 60, 90, 120, 150, 180, 240, 300]
    private let increments: [Double] = [1.25, 2.5, 5]

    var body: some View {
        NavigationStack {
            ZStack {
                FG.background.ignoresSafeArea()
                if loading {
                    ProgressView().tint(FG.ember)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            TextField("Template name (e.g. Push Day)", text: $name)
                                .font(.system(size: 15))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14).frame(height: 48)
                                .background(RoundedRectangle(cornerRadius: 12).fill(FG.card))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(FG.border, lineWidth: 1))
                                .onChange(of: name) { _, _ in dirty = true }

                            ForEach(Array(exercises.enumerated()), id: \.element.id) { i, ex in
                                exerciseCard(ex, at: i)
                            }

                            Button {
                                pickerOpen = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                                    Text("Add exercise").font(.system(size: 15, weight: .semibold))
                                }
                                .foregroundStyle(FG.ember)
                                .frame(maxWidth: .infinity).frame(height: 50)
                                .overlay(RoundedRectangle(cornerRadius: 14)
                                    .stroke(FG.border, style: StrokeStyle(lineWidth: 1, dash: [5])))
                            }
                            .buttonStyle(Pressable())

                            if let error {
                                Text(error).font(.system(size: 13)).foregroundStyle(FG.destructive)
                            }

                            Button {
                                Task { await save() }
                            } label: {
                                Text(busy ? "Saving…" : "Save template")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(maxWidth: .infinity).frame(height: 48)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(FG.ember))
                                    .foregroundStyle(.black.opacity(0.8))
                            }
                            .buttonStyle(Pressable())
                            .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty || exercises.isEmpty)
                            .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty || exercises.isEmpty ? 0.5 : 1)

                            Color.clear.frame(height: 20)
                        }
                        .padding(18)
                    }
                }
                if confirmLeave { leaveModal }
            }
            .navigationTitle(routineId == nil ? "New template" : "Edit template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        if dirty { confirmLeave = true } else { dismiss() }
                    }
                    .foregroundStyle(FG.muted)
                }
            }
        }
        .interactiveDismissDisabled(dirty)
        .fullScreenCover(isPresented: $pickerOpen) {
            ExercisePicker { ex in
                dirty = true
                exercises.append(EditorExercise(
                    exerciseId: ex.id, name: ex.name, setCount: 3,
                    restSeconds: nil, supersetWithNext: false,
                    repMin: nil, repMax: nil, increment: nil,
                    amrapLastSet: false
                ))
            }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    // MARK: exercise card

    private func exerciseCard(_ ex: EditorExercise, at i: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(ex.name)
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                if i > 0 {
                    iconButton("arrow.up") { move(i, by: -1) }
                }
                if i < exercises.count - 1 {
                    iconButton("arrow.down") { move(i, by: 1) }
                }
                iconButton("trash") {
                    dirty = true
                    withAnimation(.spring(duration: 0.3)) { _ = exercises.remove(at: i) }
                }
            }

            HStack {
                HStack(spacing: 8) {
                    Text("Sets").font(.system(size: 13)).foregroundStyle(FG.muted)
                    HStack(spacing: 0) {
                        stepButton("minus") { updateSets(i, delta: -1) }
                        Text("\(ex.setCount)")
                            .font(.system(size: 14, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: 28)
                        stepButton("plus") { updateSets(i, delta: 1) }
                    }
                    .background(RoundedRectangle(cornerRadius: 9).fill(FG.secondary))
                }
                Spacer()
                HStack(spacing: 6) {
                    Text("Rest").font(.system(size: 13)).foregroundStyle(FG.muted)
                    Menu {
                        Button {
                            dirty = true
                            exercises[i].restSeconds = nil
                        } label: {
                            if ex.restSeconds == nil {
                                Label("Default", systemImage: "checkmark")
                            } else {
                                Text("Default")
                            }
                        }
                        ForEach(restOptions, id: \.self) { s in
                            Button {
                                dirty = true
                                exercises[i].restSeconds = s
                            } label: {
                                if s == ex.restSeconds {
                                    Label(restLabel(s), systemImage: "checkmark")
                                } else {
                                    Text(restLabel(s))
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(ex.restSeconds.map(restLabel) ?? "Default")
                                .font(.system(size: 13, weight: .medium))
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 9).fill(FG.secondary))
                    }
                }
            }

            HStack {
                HStack(spacing: 6) {
                    Text("Reps").font(.system(size: 13)).foregroundStyle(FG.muted)
                    repField(value: Binding(
                        get: { exercises[i].repMin },
                        set: { dirty = true; exercises[i].repMin = $0 }
                    ), placeholder: "min")
                    Text("–").foregroundStyle(FG.muted)
                    repField(value: Binding(
                        get: { exercises[i].repMax },
                        set: { dirty = true; exercises[i].repMax = $0 }
                    ), placeholder: "max")
                }
                Spacer()
                if ex.repMax != nil {
                    HStack(spacing: 6) {
                        Text("Progress").font(.system(size: 13)).foregroundStyle(FG.muted)
                        Menu {
                            ForEach(increments, id: \.self) { inc in
                                Button {
                                    dirty = true
                                    exercises[i].increment = inc
                                } label: {
                                    if inc == (ex.increment ?? 2.5) {
                                        Label("+\(fmtPlate(inc)) kg", systemImage: "checkmark")
                                    } else {
                                        Text("+\(fmtPlate(inc)) kg")
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("+\(fmtPlate(ex.increment ?? 2.5))")
                                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 9).fill(FG.secondary))
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    dirty = true
                    exercises[i].amrapLastSet.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "flame").font(.system(size: 11, weight: .semibold))
                        Text(ex.amrapLastSet ? "Last set AMRAP" : "Last set AMRAP?")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ex.amrapLastSet ? FG.gold : FG.muted)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9)
                        .fill(ex.amrapLastSet ? FG.gold.opacity(0.16) : FG.secondary))
                }
                .buttonStyle(.plain)
                if i < exercises.count - 1 {
                    Button {
                        dirty = true
                        exercises[i].supersetWithNext.toggle()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "link").font(.system(size: 11, weight: .semibold))
                            Text(ex.supersetWithNext ? "Superset" : "Superset?")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(ex.supersetWithNext ? FG.ember : FG.muted)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 9)
                            .fill(ex.supersetWithNext ? FG.emberSoft : FG.secondary))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }

    // MARK: pieces

    private func iconButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(FG.muted)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(FG.secondary))
        }
        .buttonStyle(.plain)
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }

    private func repField(value: Binding<Int?>, placeholder: String) -> some View {
        TextField(placeholder, text: Binding(
            get: { value.wrappedValue.map(String.init) ?? "" },
            set: { value.wrappedValue = Int($0) }
        ))
        .keyboardType(.numberPad)
        .multilineTextAlignment(.center)
        .font(.system(size: 13).monospacedDigit())
        .foregroundStyle(.white)
        .frame(width: 46, height: 34)
        .background(RoundedRectangle(cornerRadius: 9).fill(FG.secondary))
    }

    private var leaveModal: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().onTapGesture { confirmLeave = false }
            VStack(spacing: 6) {
                Text("Discard changes?")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                Text("Your edits to this template haven't been saved.")
                    .font(.system(size: 13)).foregroundStyle(FG.muted).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button {
                        confirmLeave = false
                    } label: {
                        Text("Keep editing").font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 12).fill(FG.secondary))
                            .foregroundStyle(.white)
                    }
                    Button {
                        confirmLeave = false
                        dismiss()
                    } label: {
                        Text("Discard").font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 12).fill(FG.destructive))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.top, 14)
            }
            .padding(20)
            .frame(maxWidth: 340)
            .background(RoundedRectangle(cornerRadius: 16).fill(FG.card))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(FG.border, lineWidth: 1))
            .padding(24)
        }
    }

    // MARK: actions

    private func move(_ i: Int, by offset: Int) {
        let target = i + offset
        guard exercises.indices.contains(target) else { return }
        dirty = true
        withAnimation(.spring(duration: 0.3)) { exercises.swapAt(i, target) }
    }

    private func updateSets(_ i: Int, delta: Int) {
        dirty = true
        exercises[i].setCount = min(20, max(1, exercises[i].setCount + delta))
    }

    private func restLabel(_ seconds: Int) -> String {
        seconds == 0 ? "Off" : "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private func load() async {
        if let routineId {
            if let r = try? await ForgeAPI.routineDetail(id: routineId) {
                name = r.name
                exercises = r.exercises.sorted { $0.position < $1.position }.map {
                    EditorExercise(
                        exerciseId: $0.exercise_id, name: $0.name, setCount: $0.set_count,
                        restSeconds: $0.rest_seconds, supersetWithNext: $0.superset_with_next,
                        repMin: $0.rep_min, repMax: $0.rep_max, increment: $0.increment,
                        amrapLastSet: ($0.set_types ?? []).last == "amrap"
                    )
                }
            } else {
                error = "Could not load the template."
            }
        }
        loading = false
    }

    private func save() async {
        busy = true
        error = nil
        let lastIndex = exercises.count - 1
        var wire: [RoutinePayloadExercise] = []
        for (i, e) in exercises.enumerated() {
            var markers: [String]?
            if e.amrapLastSet {
                var out = Array(repeating: "", count: max(1, e.setCount))
                out[out.count - 1] = "amrap"
                markers = out
            }
            let increment: Double? = e.repMax != nil ? (e.increment ?? 2.5) : nil
            wire.append(RoutinePayloadExercise(
                set_types: markers,
                exercise_id: e.exerciseId,
                set_count: e.setCount,
                rest_seconds: e.restSeconds,
                superset_with_next: i < lastIndex && e.supersetWithNext,
                rep_min: e.repMin,
                rep_max: e.repMax,
                increment: increment
            ))
        }
        let payload = RoutinePayload(
            name: name.trimmingCharacters(in: .whitespaces),
            exercises: wire
        )
        do {
            try await ForgeAPI.saveRoutine(id: routineId, payload)
            await onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }
}
