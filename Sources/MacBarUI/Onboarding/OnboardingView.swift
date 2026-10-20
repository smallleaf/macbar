import MacBarCore
import SwiftUI

/// Three-step first launch flow: welcome, permissions, done.
public struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    public var onFinish: () -> Void

    @State private var step: Int = 0

    public init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.l) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? DesignTokens.Colors.accent : Color.primary.opacity(0.12))
                        .frame(width: index == step ? 22 : 8, height: 4)
                        .animation(.easeInOut(duration: 0.18), value: step)
                }
                Spacer()
            }

            Spacer(minLength: 0)

            switch step {
            case 0: welcome
            case 1: permissions
            default: finish
            }

            Spacer(minLength: 0)

            HStack {
                if step > 0 {
                    Button("上一步") { step -= 1 }
                }
                Spacer()
                if step < 2 {
                    Button("跳过") {
                        model.completeOnboarding()
                        onFinish()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    Button("继续") { step += 1 }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("开始使用") {
                        model.completeOnboarding()
                        onFinish()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
        }
        .padding(DesignTokens.Spacing.xxl)
        .frame(width: 480, height: 400)
    }

    private var welcome: some View {
        VStack(spacing: DesignTokens.Spacing.m) {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(DesignTokens.Colors.accent)
            Text("欢迎使用 MacBar")
                .font(.system(size: 22, weight: .semibold))
            Text("点击菜单栏上的 MacBar 图标即可打开面板，查看并管理菜单栏里的所有图标。\n你可以隐藏不常用的图标，让菜单栏保持整洁。")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
            if model.isStatusItemSuppressed {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Label("先在菜单栏设置中允许 MacBar", systemImage: "menubar.rectangle")
                        .font(DesignTokens.Typography.body.weight(.semibold))
                        .foregroundStyle(Color(nsColor: .systemOrange))
                    Text("macOS 26 默认由系统管理菜单栏。请在「系统设置 → 菜单栏 → 允许在菜单栏中显示」中启用 MacBar，否则图标不会出现。")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("打开菜单栏设置") { model.openMenuBarSettings() }
                        .controlSize(.small)
                }
                .padding(DesignTokens.Spacing.s)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: DesignTokens.cornerStyle)
                        .fill(DesignTokens.Colors.warningBackground)
                )
            }

            Text("需要两项系统权限")
                .font(.system(size: 18, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .center)

            ForEach(PermissionKind.allCases) { kind in
                HStack(alignment: .top, spacing: DesignTokens.Spacing.m) {
                    Image(systemName: status(for: kind).isGranted ? "checkmark.shield.fill" : "shield")
                        .foregroundStyle(status(for: kind).isGranted ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange))
                        .font(.system(size: 18))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(kind.title)
                                .font(DesignTokens.Typography.body.weight(.semibold))
                            Text(kind.isRequired ? "必需" : "可选")
                                .font(DesignTokens.Typography.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Text(kind.explanation)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if !status(for: kind).isGranted {
                        Button("授权") { model.requestPermission(kind) }
                            .controlSize(.small)
                    }
                }
                .padding(DesignTokens.Spacing.s)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: DesignTokens.cornerStyle)
                        .fill(DesignTokens.Colors.card)
                )
            }

            if model.needsReauthorizationAfterRebuild {
                Text("提示：当前版本是重新构建的，系统里旧的勾选对本次运行无效。请在「辅助功能」中先移除 MacBar，再用「+」重新添加当前版本。")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("所有数据仅保存在本机，MacBar 不会联网。")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var finish: some View {
        VStack(spacing: DesignTokens.Spacing.m) {
            Image(systemName: model.accessibilityStatus.isGranted ? "checkmark.circle.fill" : "lock.circle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(model.accessibilityStatus.isGranted ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange))
            Text(model.accessibilityStatus.isGranted ? "一切就绪" : "当前为只读模式")
                .font(.system(size: 20, weight: .semibold))
            Text(
                model.accessibilityStatus.isGranted
                    ? "点击菜单栏图标打开面板。点击任意图标即可隐藏或显示，右键可移动分区或设置名称。"
                    : "你仍可以查看菜单栏图标列表。授予「辅助功能」后即可隐藏与显示图标。"
            )
            .font(DesignTokens.Typography.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            if model.accessibilityStatus.isGranted {
                HStack(spacing: DesignTokens.Spacing.l) {
                    label(icon: "cursorarrow.click", text: "点击图标切换")
                    label(icon: "contextualmenu.and.cursorarrow", text: "右键移动分区")
                    label(icon: "keyboard", text: "⌥⌘H 切换隐藏区")
                }
                .padding(.top, DesignTokens.Spacing.xs)
            }
        }
    }

    private func label(icon: String, text: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(text)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func status(for kind: PermissionKind) -> PermissionStatus {
        model.permissions[kind] ?? .unknown
    }
}
