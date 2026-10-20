import MacBarCore
import SwiftUI

/// A titled group of item tiles for one section.
public struct SectionGroupView: View {
    @EnvironmentObject private var model: AppModel
    public let section: MenuBarSection
    public let items: [MenuBarItemRecord]
    public var onToggle: (MenuBarItemRecord) -> Void
    public var onMove: (MenuBarItemRecord, MenuBarSection) -> Void
    public var onEditAlias: (MenuBarItemRecord) -> Void

    @State private var collapsed = false

    public init(
        section: MenuBarSection,
        items: [MenuBarItemRecord],
        onToggle: @escaping (MenuBarItemRecord) -> Void,
        onMove: @escaping (MenuBarItemRecord, MenuBarSection) -> Void,
        onEditAlias: @escaping (MenuBarItemRecord) -> Void
    ) {
        self.section = section
        self.items = items
        self.onToggle = onToggle
        self.onMove = onMove
        self.onEditAlias = onEditAlias
    }

    private let columns = [
        GridItem(.adaptive(minimum: DesignTokens.Panel.tileMinWidth, maximum: 200), spacing: DesignTokens.Spacing.s),
    ]

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { collapsed.toggle() }
            } label: {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                    Image(systemName: section.systemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignTokens.Colors.tint(for: section))
                    Text(section.displayName)
                        .font(DesignTokens.Typography.sectionTitle)
                        .foregroundStyle(.secondary)
                    Text("\(items.count)")
                        .font(DesignTokens.Typography.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !collapsed {
                if items.isEmpty {
                    Text(emptyHint)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, DesignTokens.Spacing.xs)
                        .padding(.leading, DesignTokens.Spacing.l)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: DesignTokens.Spacing.s) {
                        ForEach(items) { item in
                            ItemTileView(
                                item: item,
                                onToggle: { onToggle(item) },
                                onMove: { onMove(item, $0) },
                                onEditAlias: { onEditAlias(item) }
                            )
                        }
                    }
                }
            }
        }
    }

    private var emptyHint: String {
        switch section {
        case .visible: "所有图标都已隐藏"
        case .hidden: "没有隐藏的图标"
        case .alwaysHidden: "没有始终隐藏的图标"
        }
    }
}

/// Empty state for scans that produced no items.
public struct EmptyStateView: View {
    public var isReadOnly: Bool
    public var onRequestPermission: () -> Void

    public init(isReadOnly: Bool, onRequestPermission: @escaping () -> Void) {
        self.isReadOnly = isReadOnly
        self.onRequestPermission = onRequestPermission
    }

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.m) {
            Image(systemName: isReadOnly ? "lock.shield" : "menubar.rectangle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(isReadOnly ? "只读模式" : "没有找到菜单栏图标")
                .font(DesignTokens.Typography.title)
            Text(
                isReadOnly
                    ? "授予「辅助功能」权限后即可扫描并隐藏图标。"
                    : "请确认菜单栏中存在状态图标，然后重新扫描。"
            )
            .font(DesignTokens.Typography.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 300)
            if isReadOnly {
                Button("授予权限", action: onRequestPermission)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260)
        .padding(DesignTokens.Spacing.l)
    }
}
