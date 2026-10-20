import AppKit
import MacBarCore
import SwiftUI

/// Diagnostics: live findings, environment, item table and audit log export.
public struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedItem: MenuBarItemRecord?

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
            HStack {
                Text("运行诊断")
                    .font(DesignTokens.Typography.title)
                Spacer()
                Button("刷新") {
                    model.reloadLogs()
                    Task { await model.refresh() }
                }
                Button("导出发送", action: model.exportDiagnostics)
                    .buttonStyle(.borderedProminent)
            }

            findingsSection
            environmentSection
            itemsSection
            logSection
        }
        .padding(DesignTokens.Spacing.l)
        .task { model.reloadLogs() }
    }

    @ViewBuilder
    private var findingsSection: some View {
        if model.findings.isEmpty {
            Label("未发现异常", systemImage: "checkmark.circle")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(Color(nsColor: .systemGreen))
        } else {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                ForEach(model.findings) { finding in
                    HStack(alignment: .top, spacing: DesignTokens.Spacing.s) {
                        Image(systemName: icon(for: finding.severity))
                            .foregroundStyle(tint(for: finding.severity))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(finding.message)
                                .font(DesignTokens.Typography.body)
                            if let recovery = finding.recovery {
                                Text(recovery)
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Text(finding.code)
                            .font(DesignTokens.Typography.mono)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 3)
                }
            }
            .padding(DesignTokens.Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.medium, style: DesignTokens.cornerStyle)
                    .fill(DesignTokens.Colors.card)
            )
        }
    }

    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("环境")
                .font(DesignTokens.Typography.sectionTitle)
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 2) {
                GridRow {
                    Text("系统").foregroundStyle(.secondary)
                    Text(ProcessInfo.processInfo.operatingSystemVersionString)
                }
                GridRow {
                    Text("应用").foregroundStyle(.secondary)
                    Text("\(MacBarVersion.current) (\(MacBarVersion.build))")
                }
                GridRow {
                    Text("模式").foregroundStyle(.secondary)
                    Text(model.mode.displayName)
                }
                GridRow {
                    Text("显示区边界").foregroundStyle(.secondary)
                    Text("visibleX=\(Int(model.anchors.visibleX)) hiddenX=\(Int(model.anchors.hiddenX))")
                        .font(DesignTokens.Typography.mono)
                }
                GridRow {
                    Text("构建签名").foregroundStyle(.secondary)
                    Text("\(model.signature.summary) · \(model.signature.shortFingerprint)")
                        .font(DesignTokens.Typography.mono)
                }
                GridRow {
                    Text("冲突工具").foregroundStyle(.secondary)
                    Text(model.conflicts.isEmpty ? "无" : model.conflicts.joined(separator: "、"))
                }
            }
            .font(DesignTokens.Typography.caption)
        }
    }

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text("状态项（\(model.allItems.count)）")
                .font(DesignTokens.Typography.sectionTitle)
                .foregroundStyle(.secondary)
            Table(model.allItems) {
                TableColumn("名称") { item in
                    Text(item.displayName).lineLimit(1)
                }
                .width(min: 110, ideal: 150)
                TableColumn("归属") { item in
                    Text(item.ownerName).foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 70, ideal: 100)
                TableColumn("分区") { item in
                    Text(item.section.displayName)
                        .foregroundStyle(DesignTokens.Colors.tint(for: item.section))
                }
                .width(70)
                TableColumn("X") { item in
                    Text("\(Int(item.frame.x))").font(DesignTokens.Typography.mono)
                }
                .width(46)
                TableColumn("可隐藏") { item in
                    Image(systemName: item.isHideable ? "checkmark" : "xmark")
                        .foregroundStyle(item.isHideable ? .secondary : .tertiary)
                }
                .width(48)
            }
            .frame(height: 130)
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack {
                Text("最近操作")
                    .font(DesignTokens.Typography.sectionTitle)
                    .foregroundStyle(.secondary)
                Spacer()
                if let last = model.logs.last {
                    Text("\(model.logs.count) 条 · 最近 \(last.opType.displayName)")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            List(model.logs.suffix(60).reversed()) { log in
                HStack(spacing: DesignTokens.Spacing.s) {
                    Image(systemName: resultIcon(log.result))
                        .foregroundStyle(resultTint(log.result))
                    Text(time(log.startedAt))
                        .font(DesignTokens.Typography.mono)
                        .foregroundStyle(.tertiary)
                    Text(log.opType.displayName)
                    Text(log.itemName ?? log.itemID ?? "-")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if let code = log.errorCode {
                        Text(code)
                            .font(DesignTokens.Typography.mono)
                            .foregroundStyle(.tertiary)
                    }
                    Text("\(log.durationMs)ms")
                        .font(DesignTokens.Typography.mono)
                        .foregroundStyle(.tertiary)
                }
                .font(DesignTokens.Typography.caption)
            }
            .listStyle(.inset)
            .frame(height: 120)
        }
    }

    private func icon(for severity: AppModel.DiagnosticsFinding.Severity) -> String {
        switch severity {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .critical: "exclamationmark.octagon"
        }
    }

    private func tint(for severity: AppModel.DiagnosticsFinding.Severity) -> Color {
        switch severity {
        case .info: Color(nsColor: .systemBlue)
        case .warning: Color(nsColor: .systemOrange)
        case .critical: Color(nsColor: .systemRed)
        }
    }

    private func resultIcon(_ result: OperationLog.Result) -> String {
        switch result {
        case .success: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .rolledBack: "arrow.uturn.backward.circle"
        case .skipped: "minus.circle"
        }
    }

    private func resultTint(_ result: OperationLog.Result) -> Color {
        switch result {
        case .success: Color(nsColor: .systemGreen)
        case .failed: Color(nsColor: .systemRed)
        case .rolledBack: Color(nsColor: .systemOrange)
        case .skipped: Color(nsColor: .secondaryLabelColor)
        }
    }

    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
