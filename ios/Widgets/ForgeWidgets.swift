import WidgetKit
import SwiftUI

@main
struct ForgeWidgetBundle: WidgetBundle {
    var body: some Widget {
        RestLiveActivity()
        NextSessionWidget()
    }
}

private enum WC {
    static let background = Color(red: 0.059, green: 0.051, blue: 0.047)
    static let card = Color(red: 0.102, green: 0.094, blue: 0.086)
    static let secondary = Color(red: 0.153, green: 0.145, blue: 0.137)
    static let muted = Color(red: 0.682, green: 0.667, blue: 0.647)
    static let ember = Color(red: 0.871, green: 0.518, blue: 0.310)
}

// MARK: - home screen widget

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: WidgetSnapshot(
            programName: "5/3/1", nextExercise: "Shoulder Press",
            prescription: "65×3 · 70×3 · 80×3+", accessory: "Pulldown & Triceps",
            week: 2, streakWeeks: 3, weekWorkouts: 1, weeklyGoal: 3, updated: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: .now, snapshot: WidgetSnapshot.load())
        completion(Timeline(entries: [entry],
                            policy: .after(.now.addingTimeInterval(4 * 3600))))
    }
}

struct NextSessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextSession", provider: SnapshotProvider()) { entry in
            NextSessionView(entry: entry)
                .containerBackground(WC.background, for: .widget)
        }
        .configurationDisplayName("Next session")
        .description("Your next program session and weekly streak.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct NextSessionView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnapshotEntry

    var body: some View {
        if let s = entry.snapshot {
            if family == .systemSmall { small(s) } else { medium(s) }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "dumbbell.fill").font(.system(size: 20)).foregroundStyle(WC.ember)
                Text("Open Forge once\nto fill the widget")
                    .font(.system(size: 11)).foregroundStyle(WC.muted)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func small(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "flame.fill").font(.system(size: 13)).foregroundStyle(WC.ember)
                Text("\(s.streakWeeks)w")
                    .font(.system(size: 16, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                Spacer()
            }
            Spacer()
            if let ex = s.nextExercise {
                Text(ex)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let p = s.prescription {
                    Text(p)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(WC.ember)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
            }
            Spacer()
            goalDots(s)
        }
    }

    private func medium(_ s: WidgetSnapshot) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "dumbbell.fill").font(.system(size: 10, weight: .semibold))
                    Text((s.programName ?? "NEXT").uppercased())
                        .font(.system(size: 10, weight: .bold)).tracking(1.5)
                    if let w = s.week {
                        Text("W\(w)").font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(WC.muted)
                    }
                }
                .foregroundStyle(WC.ember)
                if let ex = s.nextExercise {
                    Text(ex)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                }
                if let p = s.prescription {
                    Text(p + " kg")
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(WC.ember)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                if let a = s.accessory {
                    Text("+ \(a)")
                        .font(.system(size: 11)).foregroundStyle(WC.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "flame.fill").font(.system(size: 13)).foregroundStyle(WC.ember)
                    Text("\(s.streakWeeks)w")
                        .font(.system(size: 16, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(s.weekWorkouts) of \(s.weeklyGoal)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(WC.muted)
                    goalDots(s)
                }
            }
        }
    }

    private func goalDots(_ s: WidgetSnapshot) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<max(1, s.weeklyGoal), id: \.self) { i in
                Capsule()
                    .fill(i < s.weekWorkouts ? WC.ember : WC.secondary)
                    .frame(width: 16, height: 5)
            }
        }
    }
}

struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            // lock screen
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: "timer")
                        .font(.system(size: 20))
                        .foregroundStyle(WC.ember)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                            .font(.system(size: 28, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                        Text("\(context.state.exercise) · set \(context.state.nextSet)")
                            .font(.system(size: 12))
                            .foregroundStyle(WC.muted)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(context.attributes.workoutName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WC.muted)
                }
                HStack(spacing: 8) {
                    Button(intent: AdjustRestIntent(seconds: 15)) {
                        HStack(spacing: 3) {
                            Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                            Text("15s").font(.system(size: 13, weight: .semibold).monospacedDigit())
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    Button(intent: SkipRestIntent()) {
                        HStack(spacing: 4) {
                            Image(systemName: "forward.fill").font(.system(size: 10))
                            Text("Skip").font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    Button(intent: CompleteSetIntent()) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                            Text("Set done").font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.black.opacity(0.8))
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: 10).fill(WC.ember))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .activityBackgroundTint(WC.background)
            .activitySystemActionForegroundColor(WC.ember)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "timer").foregroundStyle(WC.ember)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                        .font(.system(size: 24, weight: .semibold).monospacedDigit())
                        .multilineTextAlignment(.center)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        Text("\(context.state.exercise) · set \(context.state.nextSet)")
                            .font(.system(size: 12))
                            .foregroundStyle(WC.muted)
                        HStack(spacing: 8) {
                            Button(intent: AdjustRestIntent(seconds: 15)) {
                                Text("+15s").font(.system(size: 12, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity).frame(height: 32)
                                    .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                            Button(intent: CompleteSetIntent()) {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                                    Text("Set done").font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundStyle(.black.opacity(0.8))
                                .frame(maxWidth: .infinity).frame(height: 32)
                                .background(RoundedRectangle(cornerRadius: 9).fill(WC.ember))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(WC.ember)
            } compactTrailing: {
                Text(timerInterval: Date()...context.state.endDate, countsDown: true)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(WC.ember)
                    .frame(maxWidth: 46)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(WC.ember)
            }
        }
    }
}
