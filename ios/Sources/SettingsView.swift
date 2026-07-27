import SwiftUI

/// Native settings: the personal preference slice of the PWA's SettingsPage.
/// Server administration (users, backups, tokens, OIDC) stays in the PWA.
struct SettingsView: View {
    let onUnpair: () -> Void

    @State private var me: Me?
    @State private var serverVersion: String?
    @State private var loading = true
    @State private var confirmUnpair = false

    // editable state
    @State private var unit = "kg"
    @State private var defaultRest = 120
    @State private var weeklyGoal = 3
    @State private var gapNudges = true
    @State private var deloadHints = true
    @State private var weeklyDigest = false
    @State private var weighInReminder = false
    @State private var weighInHour = 7

    private let restOptions = [30, 45, 60, 90, 120, 150, 180, 240, 300]

    var body: some View {
        ZStack {
            FG.background.ignoresSafeArea()
            if loading {
                ProgressView().tint(FG.ember)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        preferencesCard
                        insightsCard
                        remindersCard
                        serverCard
                        unpairButton
                        Color.clear.frame(height: 30)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                }
            }
            if confirmUnpair { unpairModal }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    // MARK: cards

    private var preferencesCard: some View {
        card("Training") {
            pickerRow("Unit", value: unit) {
                ForEach(["kg", "lb"], id: \.self) { u in
                    Button {
                        unit = u
                        save(["unit": u])
                    } label: {
                        if u == unit {
                            Label(u, systemImage: "checkmark")
                        } else {
                            Text(u)
                        }
                    }
                }
            }
            divider
            pickerRow("Default rest", value: restLabel(defaultRest)) {
                ForEach(restOptions, id: \.self) { s in
                    Button {
                        defaultRest = s
                        save(["default_rest_seconds": s])
                    } label: {
                        if s == defaultRest {
                            Label(restLabel(s), systemImage: "checkmark")
                        } else {
                            Text(restLabel(s))
                        }
                    }
                }
            }
            divider
            HStack {
                Text("Weekly goal").font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                Spacer()
                Stepper("\(weeklyGoal) workout\(weeklyGoal == 1 ? "" : "s")",
                        value: $weeklyGoal, in: 1...7)
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(FG.muted)
                    .fixedSize()
                    .onChange(of: weeklyGoal) { _, v in save(["weekly_goal": v]) }
            }
            .padding(.vertical, 4)
        }
    }

    private var insightsCard: some View {
        card("Insights") {
            toggleRow("Gap nudges", "\"No Legs work in 12 days\" on the stats page",
                      $gapNudges, field: "gap_nudges")
            divider
            toggleRow("Deload hints", "suggest a deload after stalled sessions",
                      $deloadHints, field: "deload_hints")
            divider
            toggleRow("Weekly digest", "a summary notification once a week",
                      $weeklyDigest, field: "weekly_digest")
        }
    }

    private var remindersCard: some View {
        card("Reminders") {
            toggleRow("Weigh-in reminder", "a nudge to log your weight",
                      $weighInReminder, field: "weigh_in_reminder")
            if weighInReminder {
                divider
                pickerRow("Reminder hour", value: String(format: "%02d:00", weighInHour)) {
                    ForEach(5..<13, id: \.self) { h in
                        Button {
                            weighInHour = h
                            save(["weigh_in_hour": h])
                        } label: {
                            if h == weighInHour {
                                Label(String(format: "%02d:00", h), systemImage: "checkmark")
                            } else {
                                Text(String(format: "%02d:00", h))
                            }
                        }
                    }
                }
            }
        }
    }

    private var serverCard: some View {
        card("Server") {
            infoRow("Address", ForgeAPI.baseURL
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: ""))
            divider
            infoRow("Forge version", serverVersion ?? "—")
            divider
            infoRow("App", (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—")
            divider
            Text("Users, backups, API tokens and account admin live in the web app.")
                .font(.system(size: 12)).foregroundStyle(FG.muted)
                .padding(.vertical, 6)
        }
    }

    private var unpairButton: some View {
        Button {
            confirmUnpair = true
        } label: {
            Text("Unpair from server")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FG.destructive)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
        }
        .buttonStyle(Pressable())
    }

    private var unpairModal: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().onTapGesture { confirmUnpair = false }
            VStack(spacing: 6) {
                Text("Unpair from server?")
                    .font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                Text("The token is removed from this device. Your data stays on the server.")
                    .font(.system(size: 13)).foregroundStyle(FG.muted).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button {
                        confirmUnpair = false
                    } label: {
                        Text("Keep").font(.system(size: 15, weight: .medium))
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 12).fill(FG.secondary))
                            .foregroundStyle(.white)
                    }
                    Button {
                        confirmUnpair = false
                        onUnpair()
                    } label: {
                        Text("Unpair").font(.system(size: 15, weight: .semibold))
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

    // MARK: pieces

    private func card(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold)).tracking(0.8)
                .foregroundStyle(FG.muted)
                .padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
        }
    }

    private var divider: some View {
        Divider().overlay(FG.border.opacity(0.5))
    }

    private func pickerRow(_ label: String, value: String,
                           @ViewBuilder options: () -> some View) -> some View {
        HStack {
            Text(label).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
            Spacer()
            Menu {
                options()
            } label: {
                HStack(spacing: 5) {
                    Text(value).font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9))
                }
                .foregroundStyle(FG.muted)
            }
        }
        .padding(.vertical, 11)
    }

    private func toggleRow(_ label: String, _ sub: String,
                           _ binding: Binding<Bool>, field: String) -> some View {
        Toggle(isOn: Binding(
            get: { binding.wrappedValue },
            set: { v in
                binding.wrappedValue = v
                save([field: v])
            }
        )) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                Text(sub).font(.system(size: 12)).foregroundStyle(FG.muted)
            }
        }
        .tint(FG.ember)
        .padding(.vertical, 9)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
            Spacer()
            Text(value).font(.system(size: 13).monospacedDigit()).foregroundStyle(FG.muted)
                .lineLimit(1).truncationMode(.middle)
        }
        .padding(.vertical, 11)
    }

    private func restLabel(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    // MARK: data

    private func load() async {
        me = try? await ForgeAPI.me()
        serverVersion = try? await ForgeAPI.health().version
        if let me {
            unit = me.unit ?? "kg"
            defaultRest = me.default_rest_seconds ?? 120
            weeklyGoal = me.weekly_goal ?? 3
            gapNudges = me.gap_nudges ?? true
            deloadHints = me.deload_hints ?? true
            weeklyDigest = me.weekly_digest ?? false
            weighInReminder = me.weigh_in_reminder ?? false
            weighInHour = me.weigh_in_hour ?? 7
        }
        loading = false
    }

    private func save(_ fields: [String: Any]) {
        Task { try? await ForgeAPI.updateMe(fields) }
    }
}
