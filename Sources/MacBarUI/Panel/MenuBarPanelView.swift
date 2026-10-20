import AppKit
import MacBarCore
import SwiftUI

/// Root view of the menu bar panel.
public struct MenuBarPanelView: View {
    @EnvironmentObject private var model: AppModel
    public var onOpenSettings: () -> Void
    public var onOpenDiagnostics: () -> Void
    public var onQuit: () -> Void

    @State private var showingAliasEditor = false

    public init(
        onOpenSettings: @escaping () -> Void,
        onOpenDiagnostics: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onOpenSettings = onOpenSettings
        self.onOpenDiagnostics = onOpenDiagnostics
        self.onQuit = onQuit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
            PanelHeaderView(onRefresh: {
                Task { await model.refresh() }
            }, onOpenSettings: onOpenSettings)

            PanelBannerView {
                if model.needsReauthorizationAfterRebuild {
                    onOpenSettings()
                } else if !model.accessibilityStatus.isGranted {
                    model.requestPermission(.accessibility)
                } else {
                    onOpenSettings()
                }
            }

            Divider()

            content

            Divider()

            PanelFooterView(
                onHideAll: { model.hideAll() },
                onShowAll: { model.showAll() },
                onReset: { model.resetLayout() },
                onCancel: { model.cancelOperation() }
            )

            HStack(spacing: DesignTokens.Spacing.m) {
                Button("诊断") { onOpenDiagnostics() }
                Button("设置") { onOpenSettings() }
                Spacer()
                Text("\(model.items.count) 个图标 · \(model.hideableCount) 个可隐藏")
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(.tertiary)
                Button("退出") { onQuit() }
            }
            .buttonStyle(.borderless)
            .font(DesignTokens.Typography.caption)
        }
        .padding(DesignTokens.Spacing.l)
        .frame(width: DesignTokens.Panel.width)
        .frame(maxHeight: DesignTokens.Panel.maxHeight, alignment: .top)
        .overlay(alignment: .bottom) {
            ToastView(toast: model.toast) {
                model.dismissToast()
            }
        }
        .sheet(item: $model.aliasEditingItem) { item in
            AliasEditorView(item: item) { alias in
                model.setAlias(alias, for: item)
            } onCancel: {
                model.aliasEditingItem = nil
            }
            .frame(width: 320)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.visibleItems.isEmpty {
            EmptyStateView(isReadOnly: !model.accessibilityStatus.isGranted) {
                model.requestPermission(.accessibility)
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
                    ForEach(visibleSections) { section in
                        SectionGroupView(
                            section: section,
                            items: model.items(in: section),
                            onToggle: { model.toggle($0) },
                            onMove: { item, target in model.move(item, to: target) },
                            onEditAlias: { model.aliasEditingItem = $0 }
                        )
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.xs)
            }
            .scrollIndicators(.automatic)
            .frame(minHeight: 220, idealHeight: 360, maxHeight: 460)
        }
    }

    private var visibleSections: [MenuBarSection] {
        if let filter = model.sectionFilter {
            return [filter]
        }
        return MenuBarSection.allCases
    }
}

/// Sheet for renaming a status item.
struct AliasEditorView: View {
    let item: MenuBarItemRecord
    let onSave: (String?) -> Void
    let onCancel: () -> Void

    @State private var text: String

    init(item: MenuBarItemRecord, onSave: @escaping (String?) -> Void, onCancel: @escaping () -> Void) {
        self.item = item
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: item.alias ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
            Text("自定义名称")
                .font(DesignTokens.Typography.title)
            Text("原名：\(item.title.isEmpty ? item.ownerName : item.title)")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
            TextField("留空则使用系统名称", text: $text)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("恢复默认") {
                    onSave(nil)
                }
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    onSave(text)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignTokens.Spacing.l)
    }
}

/// Transient toast anchored to the bottom of the panel.
struct ToastView: View {
    let toast: AppModel.Toast?
    let onDismiss: () -> Void

    var body: some View {
        if let toast {
            HStack(spacing: DesignTokens.Spacing.s) {
                Image(systemName: icon(for: toast.kind))
                    .foregroundStyle(tint(for: toast.kind))
                VStack(alignment: .leading, spacing: 1) {
                    Text(toast.message)
                        .font(DesignTokens.Typography.body.weight(.medium))
                    if let detail = toast.detail {
                        Text(detail)
                            .font(DesignTokens.Typography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.borderless)
            }
            .padding(DesignTokens.Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: DesignTokens.cornerStyle)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            )
            .padding(DesignTokens.Spacing.l)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onTapGesture(perform: onDismiss)
        }
    }

    private func icon(for kind: AppModel.Toast.Kind) -> String {
        switch kind {
        case .success: "checkmark.circle.fill"
        case .failure: "exclamationmark.octagon.fill"
        case .info: "info.circle.fill"
        }
    }

    private func tint(for kind: AppModel.Toast.Kind) -> Color {
        switch kind {
        case .success: Color(nsColor: .systemGreen)
        case .failure: Color(nsColor: .systemRed)
        case .info: Color(nsColor: .systemBlue)
        }
    }
}
