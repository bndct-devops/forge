import SwiftUI

/// Port of the PWA's ExerciseForm: create or edit a custom exercise.
struct ExerciseFormView: View {
    let title: String
    let submitLabel: String
    var initial: LibraryExercise?
    let onSubmit: (String, String, String, String?) async throws -> Void
    var onDelete: (() async throws -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var muscleGroup = ExerciseFormView.muscleGroups[0]
    @State private var equipment = ExerciseFormView.equipmentOptions[0]
    @State private var grip: String?
    @State private var error: String?
    @State private var busy = false
    @State private var confirmDelete = false

    static let muscleGroups = ["Chest", "Back", "Shoulders", "Arms", "Legs", "Core", "Full Body", "Other"]
    static let equipmentOptions = ["Barbell", "Dumbbell", "Machine", "Plate-Loaded", "Smith Machine",
                                   "Cable", "Bodyweight", "EZ Bar", "Trap Bar", "Kettlebell", "Other"]
    static let grips = ["Overhand", "Underhand", "Neutral", "Mixed", "Wide", "Close"]

    var body: some View {
        NavigationStack {
            ZStack {
                FG.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        field("Name") {
                            TextField("e.g. Incline Cable Fly", text: $name)
                                .font(.system(size: 15))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14).frame(height: 46)
                                .background(RoundedRectangle(cornerRadius: 12).fill(FG.card))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(FG.border, lineWidth: 1))
                        }
                        field("Muscle group") {
                            optionMenu(Self.muscleGroups, selection: $muscleGroup)
                        }
                        field("Equipment") {
                            optionMenu(Self.equipmentOptions, selection: $equipment)
                        }
                        field("Grip (optional)") {
                            Menu {
                                Button("None") { grip = nil }
                                ForEach(Self.grips, id: \.self) { g in
                                    Button {
                                        grip = g
                                    } label: {
                                        if g == grip {
                                            Label(g, systemImage: "checkmark")
                                        } else {
                                            Text(g)
                                        }
                                    }
                                }
                            } label: {
                                menuLabel(grip ?? "None")
                            }
                        }
                        if let error {
                            Text(error).font(.system(size: 13)).foregroundStyle(FG.destructive)
                        }
                        Button {
                            Task { await submit() }
                        } label: {
                            Text(busy ? "…" : submitLabel)
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .background(RoundedRectangle(cornerRadius: 14).fill(FG.ember))
                                .foregroundStyle(.black.opacity(0.8))
                        }
                        .buttonStyle(Pressable())
                        .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                        if onDelete != nil {
                            Button {
                                confirmDelete = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "trash").font(.system(size: 13))
                                    Text("Delete")
                                }
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(FG.destructive)
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .background(RoundedRectangle(cornerRadius: 14).fill(FG.secondary))
                            }
                            .buttonStyle(Pressable())
                        }
                        Spacer()
                    }
                    .padding(18)
                }
                if confirmDelete { deleteModal }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(FG.muted)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if let initial {
                name = initial.name
                muscleGroup = initial.muscle_group ?? Self.muscleGroups[0]
                equipment = initial.equipment ?? Self.equipmentOptions[0]
                grip = initial.grip
            }
        }
    }

    private var deleteModal: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().onTapGesture { confirmDelete = false }
            VStack(spacing: 6) {
                Text("Delete \"\(name)\"?")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Also removes it from every workout and template. Exercises with logged history can't be deleted.")
                    .font(.system(size: 13)).foregroundStyle(FG.muted).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button {
                        confirmDelete = false
                    } label: {
                        Text("Keep").font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 12).fill(FG.secondary))
                            .foregroundStyle(.white)
                    }
                    Button {
                        confirmDelete = false
                        Task { await performDelete() }
                    } label: {
                        Text("Delete").font(.system(size: 15, weight: .semibold))
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

    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
            content()
        }
    }

    private func optionMenu(_ options: [String], selection: Binding<String>) -> some View {
        Menu {
            ForEach(options, id: \.self) { o in
                Button {
                    selection.wrappedValue = o
                } label: {
                    if o == selection.wrappedValue {
                        Label(o, systemImage: "checkmark")
                    } else {
                        Text(o)
                    }
                }
            }
        } label: {
            menuLabel(selection.wrappedValue)
        }
    }

    private func menuLabel(_ value: String) -> some View {
        HStack {
            Text(value).font(.system(size: 15)).foregroundStyle(.white)
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11)).foregroundStyle(FG.muted)
        }
        .padding(.horizontal, 14).frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 12).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FG.border, lineWidth: 1))
    }

    private func submit() async {
        busy = true
        error = nil
        do {
            try await onSubmit(name.trimmingCharacters(in: .whitespaces), muscleGroup, equipment, grip)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }

    private func performDelete() async {
        busy = true
        error = nil
        do {
            try await onDelete?()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }
}
