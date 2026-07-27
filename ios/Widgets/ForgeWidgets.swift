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
                    Text("\(context.state.exercise) · set \(context.state.nextSet)")
                        .font(.system(size: 12))
                        .foregroundStyle(WC.muted)
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
