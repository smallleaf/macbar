import MacBarCore
import SwiftUI

/// A single menu bar item in the panel grid.
public struct ItemTileView: View {
    @EnvironmentObject private var model: AppModel
    public let item: MenuBarItemRecord
    public let onToggle: () -> Void
    public let onMove: (MenuBarSection) -> Void
    public let onEditAlias: () -> Void

    @State private var hovering = false

    public init(
        item: MenuBarItemRecord,
        onToggle: @escaping () -> Void,
        onMove: @escaping (MenuBarSection) -> Void,
        onEditAlias: @escaping () -> Void
    ) {
        self.item = item
        self.onToggle = onToggle
        self.onMove = onMove
        self.onEditAlias = onEditAlias
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                ItemIconView(item: item, image: model.icon(for: item))
                Spacer(minLength: 0)
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                statusDot
            }
            Text(item.displayName)
                .font(DesignTokens.Typography.body.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(item.subtitle)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(DesignTokens.Spacing.s)
        .frame(maxWidth: .infinity, minHeight: DesignTokens.Panel.tileHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: DesignTokens.cornerStyle)
                .fill(hovering ? Color.primary.opacity(0.06) : DesignTokens.Colors.card.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: DesignTokens.cornerStyle)
                .strokeBorder(
                    item.section == .visible ? Color.clear : DesignTokens.Colors.tint(for: item.section).opacity(0.35),
                    lineWidth: 1
                )
        )
        .opacity(item.isMovable && item.isHideable ? 1 : 0.55)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .help(helpText)
        .contextMenu {
            Button(item.section == .visible ? "隐藏" : "显示", action: onToggle)
                .disabled(!item.isHideable || !item.isMovable)
            Divider()
            Button("移到显示区") { onMove(.visible) }
                .disabled(!item.isMovable)
            Button("移到隐藏区") { onMove(.hidden) }
                .disabled(!item.isHideable || !item.isMovable)
            Button("移到始终隐藏") { onMove(.alwaysHidden) }
                .disabled(!item.isHideable || !item.isMovable)
            Divider()
            Button("设置名称…", action: onEditAlias)
            Button("固定到当前分区") { model.pin(item, to: item.section) }
            Button("固定到显示区") { model.pin(item, to: .visible) }
                .disabled(!item.isMovable)
            if item.isPinned {
                Button("取消固定") { model.pin(item, to: nil) }
            }
            Divider()
            Button("从列表移除") { model.hideFromList(item) }
            if let bundle = item.bundleIdentifier,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
                Divider()
                Button("打开 \(item.ownerName)") {
                    NSWorkspace.shared.openApplication(at: url, configuration: .init())
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.displayName)，\(item.section.displayName)")
        .accessibilityAddTraits(.isButton)
    }

    private var statusDot: some View {
        Circle()
            .fill(DesignTokens.Colors.tint(for: item.section))
            .frame(width: 6, height: 6)
    }

    private var helpText: String {
        if let reason = ItemCapabilityEvaluator().disabledReason(bundleIdentifier: item.bundleIdentifier, title: item.title) {
            return reason
        }
        return item.section == .visible ? "点击隐藏 \(item.displayName)" : "点击显示 \(item.displayName)"
    }
}
