import AppKit
import MacBarCore
import SwiftUI

/// Settings window with general, permissions, diagnostics and about tabs.
public struct SettingsRootView: View {
    @EnvironmentObject private var model: AppModel
    @Binding private var selection: SettingsTab
    public var onOpenPanel: () -> Void

    public init(selection: Binding<SettingsTab>, onOpenPanel: @escaping () -> Void) {
        _selection = selection
        self.onOpenPanel = onOpenPanel
    }

    public var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsView()
                .tabItem { Label("通用", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            PermissionsView()
                .tabItem { Label("权限", systemImage: "lock.shield") }
                .tag(SettingsTab.permissions)
            DiagnosticsView()
                .tabItem { Label("诊断", systemImage: "stethoscope") }
                .tag(SettingsTab.diagnostics)
            AboutView()
                .tabItem { Label("关于", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 560, height: 460)
    }
}

/// Tabs of the settings window.
public enum SettingsTab: Int, Hashable, CaseIterable, Identifiable {
    case general
    case permissions
    case diagnostics
    case about

    public var id: Int { rawValue }
}

/// General preferences.
public struct GeneralSettingsView: View {
    @EnvironmentObject private var model: AppModel

    public init() {}

    public var body: some View {
        Form {
            Section("启动") {
                Toggle("登录时启动 MacBar", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.toggleLaunchAtLogin($0) }
                ))
                Toggle("在 Dock 中显示图标", isOn: model.settingBinding(\.showDockIcon))
                    .onChange(of: model.settings.showDockIcon) { _, value in
                        NSApp.setActivationPolicy(value ? .regular : .accessory)
                    }
                Toggle("退出时恢复所有图标", isOn: model.settingBinding(\.restoreOnQuit))
            }

            Section("布局") {
                Toggle("管理所有显示器", isOn: model.settingBinding(\.manageAllDisplays))
                Toggle("在列表中显示系统图标", isOn: model.settingBinding(\.showSystemItemsInPanel))
                Toggle("使用屏幕录制截取图标缩略图", isOn: model.settingBinding(\.captureIcons))
                Picker("同类工具冲突策略", selection: model.settingBinding(\.conflictPolicy)) {
                    ForEach(ConflictPolicy.allCases, id: \.self) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
            }

            Section("快捷键") {
                LabeledContent("切换隐藏区") {
                    Text(model.settings.hotkeyToggleHidden)
                        .font(DesignTokens.Typography.mono)
                }
                LabeledContent("紧急恢复全部图标") {
                    Text(model.settings.hotkeyEmergencyRestore)
                        .font(DesignTokens.Typography.mono)
                }
                Text("修改快捷键请在后续版本使用录制控件；当前版本使用默认组合。")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding(DesignTokens.Spacing.m)
    }
}

/// Permission status cards with one-click links into System Settings.
public struct PermissionsView: View {
    @EnvironmentObject private var model: AppModel

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                if model.isStatusItemSuppressed {
                    MenuBarAllowCard()
                }
                if model.needsReauthorizationAfterRebuild {
                    ReauthorizationCard()
                }
                ForEach(PermissionKind.allCases) { kind in
                    PermissionCard(kind: kind, status: model.permissions[kind] ?? .unknown)
                }
                SignatureCard()

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text("隐私说明")
                        .font(DesignTokens.Typography.sectionTitle)
                        .foregroundStyle(.secondary)
                    Text("MacBar 完全在本机运行，不联网、不上传任何数据。权限仅用于读取菜单栏与模拟拖拽，日志保存在本地。")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DesignTokens.Spacing.m)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: DesignTokens.cornerStyle)
                        .fill(DesignTokens.Colors.infoBackground)
                )
            }
            .padding(DesignTokens.Spacing.l)
        }
    }
}

/// Entry point for the macOS 26 "Allow in the Menu Bar" switch.
private struct MenuBarAllowCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            Label("菜单栏中未显示 MacBar", systemImage: "menubar.rectangle")
                .font(DesignTokens.Typography.body.weight(.semibold))
                .foregroundStyle(Color(nsColor: .systemOrange))
            Text("macOS 26 由系统统一管理菜单栏。若图标不出现，请在「系统设置 → 菜单栏 → 允许在菜单栏中显示」中启用 MacBar；已启用时可先关闭再打开以刷新绑定。")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("打开菜单栏设置") { model.openMenuBarSettings() }
                    .buttonStyle(.borderedProminent)
                Button("我已完成，重新检测") { model.refreshHostingStatus() }
            }
            .controlSize(.small)
        }
        .padding(DesignTokens.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: DesignTokens.cornerStyle)
                .fill(DesignTokens.Colors.warningBackground)
        )
    }
}

/// Explains why an already-checked app can still be denied, and how to fix it.
private struct ReauthorizationCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            Label("系统设置里已勾选，但仍提示需要授权？", systemImage: "signature")
                .font(DesignTokens.Typography.body.weight(.semibold))
                .foregroundStyle(Color(nsColor: .systemRed))
            Text("本次运行的 MacBar 是重新构建的版本。辅助功能授权绑定的是构建指纹，旧版本的勾选对当前版本无效，但系统仍会显示为已勾选。")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 3) {
                step(1, "点击下方「打开辅助功能设置」")
                step(2, "在列表中找到 MacBar，选中后点「−」移除")
                step(3, "点「+」，选择当前 MacBar.app 重新添加并勾选")
                step(4, "回到 MacBar，权限会自动刷新")
            }
            HStack {
                Button("打开辅助功能设置") {
                    model.openSystemSettings(for: .accessibility)
                }
                .buttonStyle(.borderedProminent)
                Button("我已完成，重新检测") {
                    model.refreshPermissions()
                }
            }
            .controlSize(.small)
        }
        .padding(DesignTokens.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: DesignTokens.cornerStyle)
                .fill(DesignTokens.Colors.errorBackground)
        )
    }

    private func step(_ index: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.xs) {
            Text("\(index).")
                .font(DesignTokens.Typography.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
            Text(text)
                .font(DesignTokens.Typography.caption)
        }
    }
}

/// Shows which identity the system associates the grant with.
private struct SignatureCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.m) {
            Image(systemName: model.signature.isAdHoc ? "exclamationmark.seal" : "checkmark.seal.fill")
                .foregroundStyle(model.signature.isAdHoc ? Color(nsColor: .systemOrange) : Color(nsColor: .systemGreen))
            VStack(alignment: .leading, spacing: 2) {
                Text("构建签名")
                    .font(DesignTokens.Typography.caption.weight(.semibold))
                Text(model.signature.summary)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
                Text("指纹 \(model.signature.shortFingerprint)")
                    .font(DesignTokens.Typography.mono)
                    .foregroundStyle(.tertiary)
                if model.signature.isAdHoc {
                    Text("开发版使用 ad-hoc 签名，每次重新构建后都需要重新授权。发布版请使用签名证书构建（Scripts/build.sh --sign \"...\"）。")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DesignTokens.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: DesignTokens.cornerStyle)
                .fill(DesignTokens.Colors.card)
        )
    }
}

private struct PermissionCard: View {
    @EnvironmentObject private var model: AppModel
    let kind: PermissionKind
    let status: PermissionStatus

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.m) {
            Image(systemName: status.isGranted ? "checkmark.shield.fill" : "shield.slash")
                .font(.system(size: 20))
                .foregroundStyle(status.isGranted ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange))
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack {
                    Text(kind.title)
                        .font(DesignTokens.Typography.body.weight(.semibold))
                    Text(kind.isRequired ? "必需" : "可选")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                    Spacer()
                    Text(statusLabel)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(status.isGranted ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange))
                }
                Text(kind.explanation)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if status.isGranted {
                        Button("打开系统设置") {
                            model.openSystemSettings(for: kind)
                        }
                    } else if model.needsReauthorizationAfterRebuild && kind == .accessibility {
                        Button("打开辅助功能设置") {
                            model.openSystemSettings(for: kind)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("重新检测") {
                            model.refreshPermissions()
                        }
                    } else {
                        Button("授权") {
                            model.requestPermission(kind)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("打开系统设置") {
                            model.openSystemSettings(for: kind)
                        }
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(DesignTokens.Spacing.m)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: DesignTokens.cornerStyle)
                .fill(DesignTokens.Colors.card)
        )
    }

    private var statusLabel: String {
        switch status {
        case .granted: "已授权"
        case .denied: "未授权"
        case .restricted: "受限"
        case .unknown: "未知"
        }
    }
}

/// About page with build information and reset actions.
public struct AboutView: View {
    @EnvironmentObject private var model: AppModel

    public init() {}

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.m) {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(DesignTokens.Colors.accent)
            Text("MacBar")
                .font(.system(size: 20, weight: .semibold))
            Text("版本 \(MacBarVersion.current) (\(MacBarVersion.build))")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
            Text("管理 macOS 菜单栏图标的显示与隐藏。")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(.secondary)

            Divider()
                .frame(width: 260)

            HStack(spacing: DesignTokens.Spacing.m) {
                Button("紧急恢复全部图标") {
                    model.emergencyRestore()
                }
                .disabled(!model.canOperate)
                Button("导出诊断信息") {
                    model.exportDiagnostics()
                }
            }
            .controlSize(.small)

            Spacer()
            Text("© 2026 MacBar")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
