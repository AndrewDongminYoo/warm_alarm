import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

@available(iOS 26.0, *)
extension Never: @retroactive AlarmMetadata {}

@main
struct WarmAlarmWidgetBundle: WidgetBundle {
    var body: some Widget {
        WarmAlarmLiveActivityWidget()
        if #available(iOS 26.0, *) {
            WarmAlarmAlarmKitWidget()
        }
    }
}

@available(iOS 26.0, *)
struct WarmAlarmAlarmKitWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<Never>.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "alarm")
                    .accessibilityHidden(true)
                WarmAlarmAlarmKitStatusView(mode: context.state.mode)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    WarmAlarmAlarmKitStatusView(mode: context.state.mode)
                }
            } compactLeading: {
                Image(systemName: "alarm")
            } compactTrailing: {
                WarmAlarmAlarmKitStatusView(mode: context.state.mode)
            } minimal: {
                Image(systemName: "alarm")
            }
        }
    }
}

@available(iOS 26.0, *)
private struct WarmAlarmAlarmKitStatusView: View {
    let mode: AlarmPresentationState.Mode

    var body: some View {
        switch mode {
        case .countdown(let countdown):
            Text(countdown.fireDate, style: .timer)
                .monospacedDigit()
        case .paused:
            Text("Paused")
        case .alert:
            Text("Alarm")
        }
    }
}

struct WarmAlarmLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WarmAlarmActivityAttributes.self) { context in
            WarmAlarmLockScreenView(context: context)
                .activityBackgroundTint(.orange.opacity(0.18))
                .activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.status.systemImageName)
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.center) {
                    WarmAlarmStatusView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WarmAlarmScheduleView(scheduledAt: context.state.scheduledAt)
                }
            } compactLeading: {
                Image(systemName: context.state.status.systemImageName)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(context.state.accessibilityLabel)
            } compactTrailing: {
                WarmAlarmScheduleView(scheduledAt: context.state.scheduledAt)
            } minimal: {
                Image(systemName: context.state.status.systemImageName)
                    .foregroundStyle(.orange)
                    .accessibilityLabel(context.state.accessibilityLabel)
            }
            .keylineTint(.orange)
        }
    }
}

private struct WarmAlarmLockScreenView: View {
    let context: ActivityViewContext<WarmAlarmActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: context.state.status.systemImageName)
                .font(.title2)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            WarmAlarmStatusView(context: context)
            Spacer(minLength: 12)
            WarmAlarmScheduleView(scheduledAt: context.state.scheduledAt)
        }
        .padding()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(context.state.accessibilityLabel)
    }
}

private struct WarmAlarmStatusView: View {
    let context: ActivityViewContext<WarmAlarmActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(context.state.title)
                .font(.headline)
                .lineLimit(1)
            Text(context.state.status.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(context.state.accessibilityLabel)
    }
}

private struct WarmAlarmScheduleView: View {
    let scheduledAt: Date?

    var body: some View {
        if let scheduledAt {
            Text(scheduledAt, style: .timer)
                .font(.system(.body, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .accessibilityLabel(Text("Alarm time, \(scheduledAt.formatted(date: .omitted, time: .shortened))"))
        }
    }
}

private extension WarmAlarmActivityAttributes.Status {
    var displayName: String {
        switch self {
        case .scheduled: "Scheduled"
        case .ringing: "Ringing"
        case .snoozed: "Snoozed"
        }
    }

    var systemImageName: String {
        switch self {
        case .scheduled: "alarm"
        case .ringing: "bell.and.waves.left.and.right"
        case .snoozed: "zzz"
        }
    }
}

private extension WarmAlarmActivityAttributes.ContentState {
    var accessibilityLabel: Text {
        if let scheduledAt {
            return Text(
                "\(title), \(status.displayName), alarm time \(scheduledAt.formatted(date: .omitted, time: .shortened))"
            )
        }
        return Text("\(title), \(status.displayName)")
    }
}
