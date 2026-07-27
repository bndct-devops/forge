import WidgetKit
import SwiftUI

@main
struct ForgeWidgetBundle: WidgetBundle {
    var body: some Widget {
        RestLiveActivity()
    }
}

private enum WC {
    static let background = Color(red: 0.059, green: 0.051, blue: 0.047)
    static let muted = Color(red: 0.682, green: 0.667, blue: 0.647)
    static let ember = Color(red: 0.871, green: 0.518, blue: 0.310)
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
