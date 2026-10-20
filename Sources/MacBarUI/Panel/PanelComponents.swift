import MacBarCore
import SwiftUI

/// Header of the panel: title, scan status, search and section filter.
public struct PanelHeaderView: View {
    @EnvironmentObject private var model: AppModel
    public var onRefresh: () -> Void
    public var onOpenSettings: () -> Void

    public init(onRefresh: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.onRefresh = onRefresh
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("菜单栏管理")
                    .font(DesignTokens.Typography.title)
                Spacer()
                Text(model.subtitle)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.tertiary)
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("重新扫描")
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("设置")
            }

            HStack(spacing: DesignTokens.Spacing.s) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索图标或应用", text: $model.searchText)
                        .textFieldStyle(.plain)
                    if !model.searchText.isEmpty {
                        Button {
                            model.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.s)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.small, style: DesignTokens.cornerStyle)
                        .fill(Color.primary.opacity(0.06))
                )

                Picker("分区", selection: $model.sectionFilter) {
                    Text("全部").tag(MenuBarSection?.none)
                    ForEach(MenuBarSection.allCases) { section in
                        Text(section.displayName).tag(MenuBarSection?.some(section))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 104)
            }
        }
    }
}

/// Banner shown for missing permissions, conflicts, or compatibility findings.
public struct PanelBannerView: View {
    @EnvironmentObject private var model: AppModel
    public var onAction: () -> Void

    public init(onAction: @escaping () -> Void) {
        self.onAction = onAction
    }

    public var body: some View {
        if let message = model.bannerMessage {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.s) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(message)
                        .font(DesignTokens.Typography.body)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = actionDetail {
                        Text(detail)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if actionTitle != nil {
                    Button(actionTitle ?? "", action: onAction)
                        .controlSize(.small)
                }
            }
            .padding(DesignTokens.Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: DesignTokens.cornerStyle)
                    .fill(background)
            )
        }
    }

    private var icon: String {
        if model.needsReauthorizationAfterRebuild { return "signature" }
        if !model.accessibilityStatus.isGranted { return "lock.shield" }
        return "exclamationmark.triangle"
    }

    private var tint: Color {
        if model.needsReauthorizationAfterRebuild { return Color(nsColor: .systemRed) }
        if !model.accessibilityStatus.isGranted { return Color(nsColor: .systemOrange) }
        return Color(nsColor: .systemRed)
    }

    private var background: Color {
        if model.needsReauthorizationAfterRebuild { return DesignTokens.Colors.errorBackground }
        if !model.accessibilityStatus.isGranted { return DesignTokens.Colors.warningBackground }
        return DesignTokens.Colors.errorBackground
    }

    private var actionTitle: String? {
        if model.needsReauthorizationAfterRebuild { return "如何修复" }
        if !model.accessibilityStatus.isGranted { return "去授权" }
        if !model.conflicts.isEmpty { return "前往设置" }
        return nil
    }

    private var actionDetail: String? {
        if model.needsReauthorizationAfterRebuild {
            return "请在「辅助功能」中先移除 MacBar，再用 + 重新添加当前版本"
        }
        if !model.accessibilityStatus.isGranted {
            return "移动图标需要模拟拖拽，授予后即可使用完整功能"
        }
        if !model.conflicts.isEmpty {
            return "同时运行可能互相抢占菜单栏布局"
        }
        return nil
    }
}

/// Footer with batch actions and the current busy indicator.
public struct PanelFooterView: View {
    @EnvironmentObject private var model: AppModel
    public var onHideAll: () -> Void
    public var onShowAll: () -> Void
    public var onReset: () -> Void
    public var onCancel: () -> Void

    public init(
        onHideAll: @escaping () -> Void,
        onShowAll: @escaping () -> Void,
        onReset: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onHideAll = onHideAll
        self.onShowAll = onShowAll
        self.onReset = onReset
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.s) {
            if model.busy.isBusy {
                HStack(spacing: DesignTokens.Spacing.s) {
                    ProgressView()
                        .controlSize(.small)
                    Text(model.busy.label)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("停止", action: onCancel)
                        .controlSize(.small)
                }
            }
            HStack(spacing: DesignTokens.Spacing.s) {
                Button(action: onHideAll) {
                    Label("全部隐藏", systemImage: "eye.slash")
                }
                .disabled(!model.canOperate)
                Button(action: onShowAll) {
                    Label("全部显示", systemImage: "eye")
                }
                .disabled(!model.canOperate)
                Spacer()
                Button(action: onReset) {
                    Label("重置布局", systemImage: "arrow.counterclockwise")
                }
                .disabled(!model.canOperate)
            }
            .controlSize(.small)
        }
    }
}
