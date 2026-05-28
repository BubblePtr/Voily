import AVFoundation
import SwiftUI
import VoilyCore

enum SettingsPermissionState: Equatable {
    case granted
    case needsRequest
    case needsSettings
    case restricted
    case unknown

    static func microphone(_ status: AVAuthorizationStatus) -> SettingsPermissionState {
        switch status {
        case .authorized:
            return .granted
        case .notDetermined:
            return .needsRequest
        case .denied:
            return .needsSettings
        case .restricted:
            return .restricted
        @unknown default:
            return .unknown
        }
    }

    static func accessibility(isTrusted: Bool) -> SettingsPermissionState {
        isTrusted ? .granted : .needsSettings
    }

    var isGranted: Bool {
        self == .granted
    }

    var statusLabel: String {
        switch self {
        case .granted:
            return AppLocalization.localized("已授权")
        case .needsRequest:
            return AppLocalization.localized("待确认")
        case .needsSettings:
            return AppLocalization.localized("需要处理")
        case .restricted:
            return AppLocalization.localized("受限制")
        case .unknown:
            return AppLocalization.localized("未知")
        }
    }

    var statusSymbolName: String {
        switch self {
        case .granted:
            return "checkmark.circle.fill"
        case .needsRequest, .needsSettings:
            return "exclamationmark.circle.fill"
        case .restricted:
            return "xmark.octagon.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }

    var statusColor: Color {
        switch self {
        case .granted:
            return .green
        case .needsRequest, .needsSettings:
            return .orange
        case .restricted:
            return .red
        case .unknown:
            return .secondary
        }
    }
}

struct SettingsPermissionSnapshot: Equatable {
    let microphone: SettingsPermissionState
    let accessibility: SettingsPermissionState

    static let unknown = SettingsPermissionSnapshot(
        microphone: .unknown,
        accessibility: .unknown
    )

    static let allGranted = SettingsPermissionSnapshot(
        microphone: .granted,
        accessibility: .granted
    )

    var hasMissingRequiredPermissions: Bool {
        !microphone.isGranted || !accessibility.isGranted
    }

    var hasKnownMissingRequiredPermissions: Bool {
        isKnownMissing(microphone) || isKnownMissing(accessibility)
    }

    private func isKnownMissing(_ state: SettingsPermissionState) -> Bool {
        switch state {
        case .needsRequest, .needsSettings, .restricted:
            return true
        case .granted, .unknown:
            return false
        }
    }
}

@MainActor
struct SettingsPermissionActions {
    let loadSnapshot: @MainActor () -> SettingsPermissionSnapshot
    let requestMicrophone: @MainActor () async -> Bool
    let openMicrophoneSettings: @MainActor () -> Void
    let openAccessibilitySettings: @MainActor () -> Void

    static func preview(snapshot: SettingsPermissionSnapshot = .allGranted) -> SettingsPermissionActions {
        SettingsPermissionActions(
            loadSnapshot: { snapshot },
            requestMicrophone: { false },
            openMicrophoneSettings: {},
            openAccessibilitySettings: {}
        )
    }
}

struct SettingsPermissionCard: View {
    let actions: SettingsPermissionActions

    @Environment(\.scenePhase) private var scenePhase
    @State private var snapshot = SettingsPermissionSnapshot.unknown
    @State private var isRequestingMicrophone = false

    var body: some View {
        SettingsCard(title: AppLocalization.localized("权限检查"), subtitle: subtitle) {
            VStack(alignment: .leading, spacing: 14) {
                SettingsPermissionRow(
                    title: AppLocalization.localized("麦克风"),
                    detail: microphoneDetail,
                    symbolName: "mic.fill",
                    status: snapshot.microphone,
                    actionTitle: microphoneActionTitle,
                    isActionDisabled: isRequestingMicrophone,
                    onAction: handleMicrophoneAction
                )

                Divider()

                SettingsPermissionRow(
                    title: AppLocalization.localized("辅助功能"),
                    detail: accessibilityDetail,
                    symbolName: "accessibility",
                    status: snapshot.accessibility,
                    actionTitle: accessibilityActionTitle,
                    isActionDisabled: false,
                    onAction: handleAccessibilityAction
                )

                HStack {
                    Text(footerText)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 12)

                    Button(action: refresh) {
                        Label(AppLocalization.localized("重新检查"), systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                }
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            refresh()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await refreshWhileVisible()
        }
    }

    private var subtitle: String {
        snapshot.hasMissingRequiredPermissions
            ? AppLocalization.localized("检查录音、触发键和文本粘贴所需的系统权限")
            : AppLocalization.localized("录音、触发键和文本粘贴所需权限都已就绪")
    }

    private var microphoneDetail: String {
        switch snapshot.microphone {
        case .granted:
            return AppLocalization.localized("可以录音，普通听写和快捷翻译都会使用这里的麦克风权限。")
        case .needsRequest:
            return AppLocalization.localized("还没有确认麦克风权限，点击后会出现 macOS 系统授权弹窗。")
        case .needsSettings:
            return AppLocalization.localized("麦克风权限已被拒绝，需要在系统设置里重新打开。")
        case .restricted:
            return AppLocalization.localized("当前环境限制麦克风权限，需要检查系统设置或设备管理策略。")
        case .unknown:
            return AppLocalization.localized("暂时无法判断麦克风权限状态，请重新检查。")
        }
    }

    private var accessibilityDetail: String {
        switch snapshot.accessibility {
        case .granted:
            return AppLocalization.localized("全局触发键监听和文本粘贴注入可用。")
        case .needsRequest, .needsSettings:
            return AppLocalization.localized("需要在系统设置的辅助功能列表中允许 Voily，否则触发键和自动粘贴不可用。")
        case .restricted:
            return AppLocalization.localized("当前环境限制辅助功能权限，需要检查系统设置或设备管理策略。")
        case .unknown:
            return AppLocalization.localized("暂时无法判断辅助功能权限状态，请重新检查。")
        }
    }

    private var footerText: String {
        snapshot.hasMissingRequiredPermissions
            ? AppLocalization.localized("授权状态会自动刷新；如果刚完成授权，也可以手动重新检查。")
            : AppLocalization.localized("如果更换安装位置或重新签名后失效，可以在这里重新修复。")
    }

    private var microphoneActionTitle: String? {
        switch snapshot.microphone {
        case .granted:
            return nil
        case .needsRequest:
            return AppLocalization.localized("请求权限")
        case .needsSettings, .restricted:
            return AppLocalization.localized("打开设置")
        case .unknown:
            return AppLocalization.localized("重新检查")
        }
    }

    private var accessibilityActionTitle: String? {
        snapshot.accessibility.isGranted ? nil : AppLocalization.localized("打开辅助功能")
    }

    @MainActor
    private func refresh() {
        snapshot = actions.loadSnapshot()
    }

    @MainActor
    private func refreshWhileVisible() async {
        while !Task.isCancelled {
            refresh()

            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
        }
    }

    private func handleMicrophoneAction() {
        switch snapshot.microphone {
        case .granted:
            return
        case .needsRequest:
            guard !isRequestingMicrophone else { return }
            isRequestingMicrophone = true
            Task { @MainActor in
                _ = await actions.requestMicrophone()
                refresh()
                isRequestingMicrophone = false
            }
        case .needsSettings, .restricted:
            actions.openMicrophoneSettings()
            refresh()
        case .unknown:
            refresh()
        }
    }

    private func handleAccessibilityAction() {
        guard !snapshot.accessibility.isGranted else { return }
        actions.openAccessibilitySettings()
        refresh()
    }
}

struct CompactSettingsPermissionStatusCapsules: View {
    let snapshot: SettingsPermissionSnapshot

    var body: some View {
        HStack(spacing: 8) {
            SettingsPermissionStatusCapsule(
                title: AppLocalization.localized("麦克风"),
                symbolName: "mic.fill",
                state: snapshot.microphone
            )

            SettingsPermissionStatusCapsule(
                title: AppLocalization.localized("辅助功能"),
                symbolName: "accessibility",
                state: snapshot.accessibility
            )
        }
    }
}

private struct SettingsPermissionStatusCapsule: View {
    let title: String
    let symbolName: String
    let state: SettingsPermissionState

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)

            Image(systemName: state.statusSymbolName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(state.statusColor)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .help(helpText)
        .accessibilityLabel("\(title)：\(state.statusLabel)")
    }

    private var helpText: String {
        "\(title)：\(state.statusLabel)"
    }
}

private struct SettingsPermissionRow: View {
    let title: String
    let detail: String
    let symbolName: String
    let status: SettingsPermissionState
    let actionTitle: String?
    let isActionDisabled: Bool
    let onAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(status.statusColor)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(status.statusColor.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))

                    Label(status.statusLabel, systemImage: status.statusSymbolName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(status.statusColor)
                        .labelStyle(.titleAndIcon)
                }

                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if let actionTitle {
                Button(action: onAction) {
                    Text(actionTitle)
                }
                .controlSize(.small)
                .disabled(isActionDisabled)
            }
        }
    }
}
