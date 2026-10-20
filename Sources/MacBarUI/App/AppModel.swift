import AppKit
import Foundation
import MacBarCore
import SwiftUI

/// Observable application state shared by the panel, settings and onboarding.
///
/// The model owns no system calls of its own: everything goes through the
/// capability protocols, which keeps the UI testable and lets the App layer
/// supply real implementations. All mutations happen on the main actor.
@MainActor
public final class AppModel: ObservableObject {
    // MARK: Types

    public enum Busy: Equatable {
        case idle
        case scanning
        case operating(String)

        public var isBusy: Bool { self != .idle }

        public var label: String {
            switch self {
            case .idle: ""
            case .scanning: "正在扫描菜单栏…"
            case .operating(let title): title
            }
        }
    }

    public struct Toast: Identifiable, Equatable {
        public enum Kind: Equatable {
            case success
            case failure
            case info
        }

        public let id = UUID()
        public var kind: Kind
        public var message: String
        public var detail: String?

        public init(kind: Kind, message: String, detail: String? = nil) {
            self.kind = kind
            self.message = message
            self.detail = detail
        }
    }

    public struct DiagnosticsFinding: Identifiable, Equatable, Sendable {
        public enum Severity: String, Sendable {
            case info
            case warning
            case critical
        }

        public var id: String { code + message }
        public var severity: Severity
        public var code: String
        public var message: String
        public var recovery: String?
    }

    // MARK: Published state

    @Published public private(set) var items: [MenuBarItemRecord] = []
    @Published public private(set) var snapshot: LayoutSnapshot
    @Published public private(set) var settings: AppSettings
    @Published public private(set) var preferences: PreferencesFile
    @Published public private(set) var permissions: [PermissionKind: PermissionStatus] = [:]
    @Published public private(set) var conflicts: [String] = []
    @Published public private(set) var findings: [DiagnosticsFinding] = []
    @Published public private(set) var logs: [OperationLog] = []
    @Published public private(set) var busy: Busy = .idle
    @Published public private(set) var mode: AppMode = .onboarding
    @Published public private(set) var anchors: LayoutAnchors = .zero
    @Published public private(set) var display: DisplayGeometry = .unknown
    @Published public private(set) var icons: [String: NSImage] = [:]
    @Published public private(set) var lastScanAt: Date?
    @Published public private(set) var lastError: MacBarError?
    @Published public var searchText: String = ""
    @Published public var sectionFilter: MenuBarSection?
    @Published public var toast: Toast?
    @Published public var aliasEditingItem: MenuBarItemRecord?
    @Published public private(set) var hasCompletedOnboarding: Bool
    @Published public private(set) var launchAtLogin: Bool
    /// Identity of the running code signature, supplied by the App layer.
    @Published public private(set) var signature: SignatureInfo = .unknown
    /// True when the build changed since the last launch. With an ad-hoc
    /// signature an existing Accessibility grant no longer applies.
    @Published public private(set) var signatureChangedSinceLastLaunch: Bool = false
    /// Whether macOS is currently rendering the status item.
    @Published public private(set) var hostingStatus: MenuBarHosting.Status = .unknown

    // MARK: Dependencies

    private let scanner: MenuBarScanning
    private let mover: MenuBarMoving
    private let permissionProvider: PermissionProviding
    private let store: LayoutStoring
    private let capturer: ItemCapturing
    private let conflictDetector: ConflictDetecting
    private let loginItem: LoginItemRegistering
    private let engine: LayoutEngine
    private let registry: ItemRegistry
    private let coordinator: LayoutCoordinator
    private let restoreService: RestoreService
    private let anchorProvider: @MainActor () -> LayoutAnchors
    private let iconProvider: @MainActor (MenuBarItemRecord) -> NSImage?
    private let modeListener: @MainActor (AppMode) -> Void

    private var refreshTask: Task<Void, Never>?
    private var operationTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var didPerformStartupHeal = false

    // MARK: Init

    public init(
        scanner: MenuBarScanning,
        mover: MenuBarMoving,
        permissions: PermissionProviding,
        store: LayoutStoring,
        capturer: ItemCapturing,
        conflictDetector: ConflictDetecting,
        loginItem: LoginItemRegistering,
        engine: LayoutEngine = LayoutEngine(),
        anchorProvider: @MainActor @escaping () -> LayoutAnchors = { .zero },
        iconProvider: @MainActor @escaping (MenuBarItemRecord) -> NSImage? = { _ in nil },
        modeListener: @MainActor @escaping (AppMode) -> Void = { _ in }
    ) {
        self.scanner = scanner
        self.mover = mover
        self.permissionProvider = permissions
        self.store = store
        self.capturer = capturer
        self.conflictDetector = conflictDetector
        self.loginItem = loginItem
        self.engine = engine
        self.anchorProvider = anchorProvider
        self.iconProvider = iconProvider
        self.modeListener = modeListener

        let loadedSettings = store.loadSettings()
        let loadedPreferences = store.loadPreferences()
        self.settings = loadedSettings
        self.preferences = loadedPreferences
        self.snapshot = (try? store.loadSnapshot()) ?? LayoutSnapshot()
        self.hasCompletedOnboarding = loadedSettings.hasCompletedOnboarding
        self.launchAtLogin = loginItem.isEnabled
        self.signatureChangedSinceLastLaunch = false
        self.registry = ItemRegistry(preferences: loadedPreferences)
        self.coordinator = LayoutCoordinator(
            scanner: scanner,
            mover: mover,
            permissions: permissions,
            store: store,
            engine: engine,
            conflictDetector: conflictDetector
        )
        self.restoreService = RestoreService(
            scanner: scanner,
            coordinator: coordinator,
            store: store,
            engine: engine
        )
    }

    // MARK: Lifecycle

    /// First load: permissions, display geometry, initial scan and startup heal.
    public func start() async {
        refreshPermissions()
        await loadDisplay()
        await registry.updatePreferences(preferences)
        await refresh(persistSections: false)
        updateMode()
        await performStartupHealIfNeeded()
        startAutoRefresh()
    }

    /// Drives the panel's derived list. Filters system items, search and section.
    public var visibleItems: [MenuBarItemRecord] {
        var result = items.filter { item in
            if !settings.showSystemItemsInPanel && item.isSystemOwned { return false }
            return true
        }
        if let sectionFilter {
            result = result.filter { $0.section == sectionFilter }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter { item in
                item.displayName.lowercased().contains(query)
                    || item.ownerName.lowercased().contains(query)
                    || (item.bundleIdentifier ?? "").lowercased().contains(query)
            }
        }
        return result.sorted { lhs, rhs in
            if lhs.section != rhs.section {
                return lhs.section.sortIndex < rhs.section.sortIndex
            }
            return lhs.frame.minX < rhs.frame.minX
        }
    }

    public func items(in section: MenuBarSection) -> [MenuBarItemRecord] {
        visibleItems.filter { $0.section == section }
    }

    public var sectionCounts: [MenuBarSection: Int] {
        Dictionary(uniqueKeysWithValues: MenuBarSection.allCases.map { section in
            (section, visibleItems.filter { $0.section == section }.count)
        })
    }

    /// All scanned items, used by the diagnostics table.
    public var allItems: [MenuBarItemRecord] { items }

    public var hideableCount: Int {
        items.filter { $0.isHideable && $0.isMovable }.count
    }

    public var hiddenCount: Int {
        items.filter { $0.section != .visible }.count
    }

    public var accessibilityStatus: PermissionStatus {
        permissions[.accessibility] ?? .unknown
    }

    public var canOperate: Bool {
        mode.canOperate && !busy.isBusy
    }

    // MARK: Scanning

    public func refresh(persistSections: Bool = true) async {
        if case .operating = busy { return }
        guard !busy.isBusy else { return }
        busy = .scanning
        defer { if busy == .scanning { busy = .idle } }

        refreshPermissions()
        await loadDisplay()
        do {
            let raw = try await scanner.scan(displayID: settings.manageAllDisplays ? nil : display.displayID)
            let ownItems = raw.items.filter { isOwnItem($0) }
            let external = raw.items.filter { !isOwnItem($0) }
            _ = ownItems
            let anchored = external.map { record -> MenuBarItemRecord in
                var copy = record
                copy.section = engine.deriveSection(for: record.frame, anchors: anchors)
                if let pinned = preferences.items[record.id]?.pinnedSection {
                    copy.section = pinned
                    copy.isPinned = true
                }
                return copy
            }
            let scanned = ScanResult(
                items: anchored,
                accessibilityAvailable: raw.accessibilityAvailable,
                scannedAt: raw.scannedAt
            )
            let pinned = preferences.items.compactMapValues { $0.pinnedSection }
            let decorated = await registry.absorb(scan: scanned, pinnedSections: pinned)
            items = decorated
            lastScanAt = scanned.scannedAt
            await reconcileSnapshot(with: decorated, persistSections: persistSections)
            updateFindings()
            updateMode()
            scheduleIconCapture()
        } catch let error as MacBarError {
            lastError = error
            updateMode()
        } catch {
            lastError = .unknown(error.localizedDescription)
            updateMode()
        }
    }

    /// Filters MacBar's own control item out of the managed list.
    private func isOwnItem(_ record: MenuBarItemRecord) -> Bool {
        if record.bundleIdentifier == MacBarVersion.bundleIdentifier { return true }
        return record.ownerName == "MacBar"
    }

    private func reconcileSnapshot(with records: [MenuBarItemRecord], persistSections: Bool) async {
        let scan = ScanResult(items: records, accessibilityAvailable: accessibilityStatus.isGranted)
        let derived = Dictionary(
            uniqueKeysWithValues: records.map { record in
                (record.id, engine.deriveSection(for: record.frame, anchors: anchors))
            }
        )
        let reconciliation = await registry.reconcile(snapshot: snapshot, scan: scan, derivedSections: derived)
        var next = reconciliation.snapshot
        if persistSections {
            // A manual arrangement performed outside MacBar becomes the new
            // intent, otherwise MacBar would fight the user on every scan.
            for record in records {
                next.insert(itemID: record.id, into: record.section, at: nil)
            }
        }
        next.displayID = display.displayID
        next.screenWidth = display.bounds.width
        next.menuBarHeight = display.menuBarHeight
        snapshot = next
        try? store.saveSnapshot(next)
    }

    private func updateFindings() {
        var result: [AppModel.DiagnosticsFinding] = []
        if !accessibilityStatus.isGranted {
            if needsReauthorizationAfterRebuild {
                result.append(
                    DiagnosticsFinding(
                        severity: .critical,
                        code: "MB-E1011",
                        message: "本次运行的版本是重新构建的，系统已不再认可旧授权",
                        recovery: "在「辅助功能」中移除 MacBar，再用「+」添加当前版本；或使用签名证书构建"
                    )
                )
            } else {
                result.append(
                    DiagnosticsFinding(
                        severity: .critical,
                        code: MacBarError.accessibilityDenied.code,
                        message: "缺少「辅助功能」权限，当前为只读模式",
                        recovery: "前往系统设置授予权限后即可隐藏/显示图标"
                    )
                )
            }
        }
        if isStatusItemSuppressed {
            result.append(
                DiagnosticsFinding(
                    severity: .critical,
                    code: "MB-E1012",
                    message: "macOS 未托管 MacBar 的菜单栏图标",
                    recovery: "打开「系统设置 → 菜单栏」，在「允许在菜单栏中显示」里启用 MacBar；若已开启，先关闭再打开"
                )
            )
        }
        if !anchorsAreHealthy {
            result.append(
                DiagnosticsFinding(
                    severity: .warning,
                    code: MacBarError.compatibilityIssue(reason: "anchors unhealthy").code,
                    message: "菜单栏空间不足或图标被系统移到屏幕外",
                    recovery: "请关闭部分菜单栏图标，或在「系统设置 → 菜单栏」中确认 MacBar 未被隐藏"
                )
            )
        }
        if !conflicts.isEmpty {
            result.append(
                DiagnosticsFinding(
                    severity: settings.conflictPolicy == .block ? .critical : .warning,
                    code: MacBarError.conflictDetected(apps: conflicts).code,
                    message: "检测到同类工具：\(conflicts.joined(separator: "、"))",
                    recovery: "同时运行可能导致布局互相抢占，建议只保留一个"
                )
            )
        }
        if ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        ) {
            let offscreenVisible = items.filter { $0.section == .visible && $0.frame.minY < display.bounds.minY - 1 }
            if !offscreenVisible.isEmpty {
                result.append(
                    DiagnosticsFinding(
                        severity: .warning,
                        code: MacBarError.compatibilityIssue(reason: "offscreen").code,
                        message: "\(offscreenVisible.count) 个图标被系统布局到屏幕外",
                        recovery: "可尝试「重置布局」，若无效请导出诊断信息"
                    )
                )
            }
            result.append(
                DiagnosticsFinding(
                    severity: .info,
                    code: "MB-I3001",
                    message: "当前系统由控制中心统一管理菜单栏布局（macOS 26+）",
                    recovery: nil
                )
            )
        }
        findings = result
    }

    private func updateMode() {
        let next: AppMode
        if !hasCompletedOnboarding {
            next = .onboarding
        } else if accessibilityStatus.isGranted && (settings.conflictPolicy == .warn || conflicts.isEmpty) {
            next = .ready
        } else {
            next = .degraded
        }
        guard mode != next else { return }
        mode = next
        modeListener(next)
    }

    // MARK: Operations

    public func toggle(_ item: MenuBarItemRecord) {
        let target: MenuBarSection = item.section == .visible ? .hidden : .visible
        move(item, to: target)
    }

    public func move(_ item: MenuBarItemRecord, to section: MenuBarSection, silent: Bool = false) {
        guard canOperate else {
            presentBlockedReason()
            return
        }
        guard item.isMovable else {
            showToast(.init(kind: .failure, message: "该图标不允许移动", detail: "系统保留图标"))
            return
        }
        guard section == .visible || item.isHideable else {
            showToast(.init(kind: .failure, message: "该图标不允许隐藏", detail: "系统保留图标"))
            return
        }
        runOperation(title: section == .visible ? "正在显示 \(item.displayName)…" : "正在隐藏 \(item.displayName)…") { [weak self] in
            guard let self else { return }
            do {
                let outcome = try await self.coordinator.move(
                    item: item,
                    to: section,
                    anchors: self.anchors,
                    display: self.display,
                    logType: section == .visible ? .show : .hide
                )
                await self.refresh()
                if outcome.result == .failed {
                    let error = outcome.error ?? .moveTimedOut(itemID: item.id)
                    self.lastError = error
                    self.showToast(.init(kind: .failure, message: "\(item.displayName) 操作失败", detail: error.localizedDescription))
                } else if !silent {
                    self.showToast(
                        .init(
                            kind: .success,
                            message: section == .visible ? "已显示 \(item.displayName)" : "已隐藏 \(item.displayName)",
                            detail: outcome.result == .skipped ? "无需移动" : nil
                        )
                    )
                }
            } catch {
                self.handleOperationError(error, item: item)
            }
        }
    }

    public func hideAll() {
        guard canOperate else {
            presentBlockedReason()
            return
        }
        let candidates = items.filter { $0.isHideable && $0.isMovable && $0.section == .visible }
        guard !candidates.isEmpty else {
            showToast(.init(kind: .info, message: "没有可隐藏的图标"))
            return
        }
        batchMove(candidates, to: .hidden, title: "正在隐藏 \(candidates.count) 个图标…")
    }

    public func showAll() {
        guard canOperate else {
            presentBlockedReason()
            return
        }
        let candidates = items.filter { $0.isHideable && $0.isMovable && $0.section != .visible }
        guard !candidates.isEmpty else {
            showToast(.init(kind: .info, message: "没有需要显示的图标"))
            return
        }
        batchMove(candidates, to: .visible, title: "正在显示 \(candidates.count) 个图标…")
    }

    public func resetLayout() {
        guard canOperate else {
            presentBlockedReason()
            return
        }
        runOperation(title: "正在重置布局…") { [weak self] in
            guard let self else { return }
            let result = await self.restoreService.reset(items: self.items, anchors: self.anchors, display: self.display)
            await self.refresh()
            self.reportRestore(result, verb: "重置")
        }
    }

    public func emergencyRestore() {
        runOperation(title: "正在恢复全部图标…") { [weak self] in
            guard let self else { return }
            let result = await self.restoreService.reset(items: self.items, anchors: self.anchors, display: self.display)
            await self.refresh()
            self.reportRestore(result, verb: "恢复")
        }
    }

    public func selfHeal() {
        guard canOperate else {
            presentBlockedReason()
            return
        }
        runOperation(title: "正在修复布局…") { [weak self] in
            guard let self else { return }
            let result = await self.restoreService.heal(
                items: self.items,
                snapshot: self.snapshot,
                anchors: self.anchors,
                display: self.display
            )
            await self.refresh()
            self.reportRestore(result, verb: "修复")
        }
    }

    public func cancelOperation() {
        operationTask?.cancel()
        operationTask = nil
        busy = .idle
        showToast(.init(kind: .info, message: "已停止操作"))
    }

    private func batchMove(_ candidates: [MenuBarItemRecord], to section: MenuBarSection, title: String) {
        runOperation(title: title) { [weak self] in
            guard let self else { return }
            let targets = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, section) })
            let plan = await self.coordinator.plan(
                items: candidates,
                targetSections: targets,
                anchors: self.anchors,
                display: self.display
            )
            let batch = await self.coordinator.apply(
                plan: plan,
                items: self.items,
                anchors: self.anchors,
                display: self.display,
                logType: section == .visible ? .batchShow : .batchHide
            )
            await self.refresh()
            self.reportBatch(batch)
        }
    }

    private func runOperation(title: String, _ body: @escaping @MainActor () async -> Void) {
        operationTask?.cancel()
        busy = .operating(title)
        operationTask = Task { [weak self] in
            await body()
            guard let self else { return }
            if case .operating = self.busy {
                self.busy = .idle
            }
        }
    }

    private func reportBatch(_ batch: LayoutCoordinator.BatchOutcome) {
        if batch.outcomes.isEmpty {
            showToast(.init(kind: .info, message: "没有需要移动的图标"))
            return
        }
        if batch.failureCount == 0 {
            showToast(
                .init(
                    kind: .success,
                    message: "操作完成",
                    detail: "成功 \(batch.successCount) 个，跳过 \(batch.skippedCount) 个"
                )
            )
            return
        }
        let error = batch.outcomes.last(where: \.isFailure)?.error
        showToast(
            .init(
                kind: .failure,
                message: batch.aborted ? "操作已中止" : "部分操作失败",
                detail: "成功 \(batch.successCount) 个，失败 \(batch.failureCount) 个\(error.map { "，\($0.localizedDescription)" } ?? "")"
            )
        )
    }

    private func reportRestore(_ result: RestoreService.Result, verb: String) {
        if result.repaired.isEmpty && result.failed.isEmpty {
            showToast(.init(kind: .info, message: "布局无需\(verb)"))
            return
        }
        if result.failed.isEmpty {
            showToast(.init(kind: .success, message: "\(verb)完成", detail: "处理 \(result.repaired.count) 个图标"))
            return
        }
        showToast(
            .init(
                kind: .failure,
                message: "\(verb)未完全成功",
                detail: "成功 \(result.repaired.count) 个，失败 \(result.failed.count) 个"
            )
        )
    }

    private func handleOperationError(_ error: Error, item: MenuBarItemRecord?) {
        let typed = (error as? MacBarError) ?? .unknown(error.localizedDescription)
        lastError = typed
        showToast(
            .init(
                kind: .failure,
                message: item.map { "\($0.displayName) 操作失败" } ?? "操作失败",
                detail: typed.localizedDescription
            )
        )
        updateMode()
    }

    private func presentBlockedReason() {
        if !accessibilityStatus.isGranted {
            showToast(.init(kind: .failure, message: "当前为只读模式", detail: "请先授予「辅助功能」权限"))
            return
        }
        if !conflicts.isEmpty && settings.conflictPolicy == .block {
            showToast(.init(kind: .failure, message: "检测到同类工具", detail: conflicts.joined(separator: "、")))
            return
        }
        showToast(.init(kind: .info, message: "请等待当前操作完成"))
    }

    // MARK: Permissions

    public func refreshPermissions() {
        var next: [PermissionKind: PermissionStatus] = [:]
        for kind in PermissionKind.allCases {
            next[kind] = permissionProvider.status(of: kind)
        }
        permissions = next
        conflicts = conflictDetector.runningManagers()
        if next[.accessibility, default: .unknown].isGranted {
            signatureChangedSinceLastLaunch = false
        }

        // A changed code signature does not change the checkbox shown in System
        // Settings, but it does invalidate the grant. Surface that explicitly so
        // the user does not keep re-checking a box that appears to be on.
        if !permissions[.accessibility, default: .unknown].isGranted,
           signature.isAdHoc,
           !settings.lastSignatureFingerprint.isEmpty,
           settings.lastSignatureFingerprint != signature.fingerprint {
            if !signatureChangedSinceLastLaunch {
                signatureChangedSinceLastLaunch = true
                MacBarLog.warning(.permission, "ad-hoc signature changed, accessibility grant no longer applies")
            }
        }
    }

    /// Re-checked when the user returns from System Settings.
    public func refreshHostingStatus() {
        Task { [weak self] in
            guard let self else { return }
            let status = await hostingProbe()
            self.setHostingStatus(status)
        }
    }

    /// Supplied by the App layer: returns whether the system is hosting the
    /// status item.
    public var hostingProbe: @Sendable () async -> MenuBarHosting.Status = { .unknown }

    /// Called by the App layer with the status item hosting result.
    public func setHostingStatus(_ status: MenuBarHosting.Status) {
        hostingStatus = status
        updateFindings()
        if status == .notHosted {
            MacBarLog.warning(.compatibility, "status item not hosted by the system")
        }
    }

    /// True when macOS is not showing MacBar in the menu bar. On macOS 26 this
    /// means the app is disabled in System Settings > Menu Bar (or blocked by a
    /// stale mapping), and the onboarding should point there instead of asking
    /// for Accessibility again.
    public var isStatusItemSuppressed: Bool {
        hostingStatus == .notHosted
    }

    /// Called by the App layer once the code signature is known.
    public func setSignature(_ info: SignatureInfo) {
        signature = info
        if !info.fingerprint.isEmpty, info.fingerprint != "unknown" {
            updateSettings { $0.lastSignatureFingerprint = info.fingerprint }
        }
    }

    /// The user re-granted permission after a rebuild. macOS keeps the old entry
    /// under the same name, so the reliable path is to make the current entry
    /// the only one before asking for trust again.
    public func reauthorizeAfterRebuild() {
        permissionProvider.openSystemSettings(for: .accessibility)
        showToast(
            .init(
                kind: .info,
                message: "请在「辅助功能」中先移除 MacBar",
                detail: "再点击列表下方的「+」重新添加当前版本，然后回到本窗口"
            )
        )
    }

    public func requestPermission(_ kind: PermissionKind) {
        if kind == .accessibility, signatureChangedSinceLastLaunch, signature.isAdHoc {
            reauthorizeAfterRebuild()
            permissions[kind] = permissionProvider.status(of: kind)
            return
        }
        let granted = permissionProvider.request(kind)
        refreshPermissions()
        if granted {
            showToast(.init(kind: .success, message: "\(kind.title)权限已授予"))
            Task { await refresh() }
        } else {
            permissionProvider.openSystemSettings(for: kind)
            showToast(.init(kind: .info, message: "请在系统设置中勾选 MacBar", detail: kind.title))
        }
        updateMode()
    }

    /// Opens the macOS 26 "Menu Bar" pane where the app's allow switch lives.
    public func openMenuBarSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.controlcenter",
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    /// Marks the one-time allow-list guidance as shown.
    public func markAllowListGuidanceShown() {
        guard !settings.hasShownMenuBarAllowListGuidance else { return }
        updateSettings { $0.hasShownMenuBarAllowListGuidance = true }
    }

    public func openSystemSettings(for kind: PermissionKind) {
        permissionProvider.openSystemSettings(for: kind)
    }

    /// Called when the onboarding flow is dismissed.
    public func completeOnboarding() {
        hasCompletedOnboarding = true
        settings.consentVersion = max(settings.consentVersion, 1)
        persistSettings()
        updateMode()
    }

    // MARK: Settings & preferences

    public func updateSettings(_ transform: (inout AppSettings) -> Void) {
        var next = settings
        transform(&next)
        let hotkeysChanged = next.hotkeyToggleHidden != settings.hotkeyToggleHidden
            || next.hotkeyEmergencyRestore != settings.hotkeyEmergencyRestore
        settings = next
        persistSettings()
        if hotkeysChanged {
            modeListener(mode)
        }
        updateMode()
    }

    public func settingBinding<T: Equatable>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { value in
                guard self.settings[keyPath: keyPath] != value else { return }
                self.updateSettings { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func persistSettings() {
        do {
            try store.saveSettings(settings)
        } catch {
            handleOperationError(error, item: nil)
        }
    }

    public func setAlias(_ alias: String?, for item: MenuBarItemRecord) {
        var preferences = self.preferences
        var preference = preferences.items[item.id] ?? ItemPreference(itemID: item.id)
        let trimmed = alias?.trimmingCharacters(in: .whitespacesAndNewlines)
        preference.alias = (trimmed?.isEmpty ?? true) ? nil : trimmed
        preference.updatedAt = Date()
        preferences.items[item.id] = preference
        preferences.updatedAt = Date()
        self.preferences = preferences
        try? store.savePreferences(preferences)
        Task {
            await registry.updatePreferences(preferences)
            await refresh()
        }
        aliasEditingItem = nil
        showToast(.init(kind: .success, message: "已更新名称"))
    }

    public func pin(_ item: MenuBarItemRecord, to section: MenuBarSection?) {
        var preferences = self.preferences
        var preference = preferences.items[item.id] ?? ItemPreference(itemID: item.id)
        preference.pinnedSection = section
        preference.updatedAt = Date()
        preferences.items[item.id] = preference
        preferences.updatedAt = Date()
        self.preferences = preferences
        try? store.savePreferences(preferences)
        Task {
            await registry.updatePreferences(preferences)
            await refresh()
        }
    }

    public func hideFromList(_ item: MenuBarItemRecord) {
        var preferences = self.preferences
        var preference = preferences.items[item.id] ?? ItemPreference(itemID: item.id)
        preference.hiddenFromList = true
        preference.updatedAt = Date()
        preferences.items[item.id] = preference
        preferences.updatedAt = Date()
        self.preferences = preferences
        try? store.savePreferences(preferences)
        Task {
            await registry.updatePreferences(preferences)
            await refresh()
        }
        showToast(.init(kind: .info, message: "已从列表移除", detail: "可在诊断页恢复"))
    }

    public func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItem.setEnabled(enabled)
            launchAtLogin = loginItem.isEnabled
            updateSettings { $0.launchAtLogin = launchAtLogin }
            showToast(.init(kind: .success, message: enabled ? "已开启登录时启动" : "已关闭登录时启动"))
        } catch {
            launchAtLogin = loginItem.isEnabled
            handleOperationError(error, item: nil)
        }
    }

    // MARK: Diagnostics

    public func exportDiagnostics() {
        do {
            let url = try store.exportDiagnostics(items: items, permissions: permissions, conflicts: conflicts)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            showToast(.init(kind: .success, message: "诊断信息已导出", detail: url.lastPathComponent))
            logs = store.loadLogs(limit: 300)
        } catch {
            handleOperationError(error, item: nil)
        }
    }

    public func reloadLogs() {
        logs = store.loadLogs(limit: 300)
    }

    /// Restores an item previously hidden from the panel.
    public func restoreListVisibility() {
        var preferences = self.preferences
        for (id, var preference) in preferences.items where preference.hiddenFromList {
            preference.hiddenFromList = false
            preference.updatedAt = Date()
            preferences.items[id] = preference
        }
        self.preferences = preferences
        try? store.savePreferences(preferences)
        Task {
            await registry.updatePreferences(preferences)
            await refresh()
        }
    }

    // MARK: Anchors

    /// Anchors are supplied by the App layer once its control items are placed.
    public func updateAnchors(_ anchors: LayoutAnchors) {
        let changed = anchors != self.anchors
        self.anchors = anchors
        if changed {
            applyAnchorsToItems()
            updateFindings()
        }
    }

    /// True when permission is missing specifically because an ad-hoc build
    /// replaced the build that was authorized.
    public var needsReauthorizationAfterRebuild: Bool {
        !accessibilityStatus.isGranted && signature.isAdHoc && signatureChangedSinceLastLaunch
    }

    /// Whether the layout boundaries are usable (control item on screen and to
    /// the right of the hidden boundary).
    public var anchorsAreHealthy: Bool {
        anchors.visibleX > anchors.hiddenX + 60 && anchors.visibleX > 0
    }

    private func applyAnchorsToItems() {
        guard anchors != .zero else { return }
        items = items.map { item in
            var copy = item
            copy.section = engine.deriveSection(for: item.frame, anchors: anchors)
            return copy
        }
    }

    private func loadDisplay() async {
        let geometries = await scanner.displayGeometries()
        let main = await scanner.mainDisplay()
        display = geometries.first { $0.displayID == (settings.manageAllDisplays ? display.displayID : main.displayID) } ?? main
        if anchors == .zero {
            anchors = engine.synthesizedAnchors(display: display)
        }
    }

    // MARK: Self heal & icons

    private func performStartupHealIfNeeded() async {
        guard !didPerformStartupHeal else { return }
        didPerformStartupHeal = true
        guard accessibilityStatus.isGranted else { return }
        let drift = items.contains { item in
            guard let intended = snapshot.section(of: item.id) else { return false }
            return intended != item.section
        }
        guard drift else { return }
        let result = await restoreService.heal(
            items: items,
            snapshot: snapshot,
            anchors: anchors,
            display: display
        )
        if !result.repaired.isEmpty || !result.failed.isEmpty {
            MacBarLog.warning(.layout, "startup heal repaired=\(result.repaired.count) failed=\(result.failed.count)")
            await refresh()
        }
    }

    private func scheduleIconCapture() {
        guard settings.captureIcons, accessibilityStatus.isGranted else { return }
        let targets = items.filter { !$0.isSystemOwned && $0.section == .visible }
        Task { [weak self] in
            for item in targets {
                guard let self else { return }
                if self.icons[item.id] != nil { continue }
                if let data = await self.capturer.capture(windowID: item.windowID, scale: 2),
                   let image = NSImage(data: data) {
                    image.size = NSSize(width: 22, height: 22)
                    self.icons[item.id] = image
                }
            }
        }
    }

    public func icon(for item: MenuBarItemRecord) -> NSImage? {
        if let image = icons[item.id] { return image }
        return iconProvider(item)
    }

    // MARK: Auto refresh & toast

    private func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self else { return }
                if self.busy.isBusy { continue }
                await self.refresh()
            }
        }
    }

    public func stop() {
        refreshTask?.cancel()
        operationTask?.cancel()
        toastTask?.cancel()
    }

    public func showToast(_ toast: Toast) {
        self.toast = toast
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard let self, self.toast?.id == toast.id else { return }
            self.toast = nil
        }
    }

    public func dismissToast() {
        toastTask?.cancel()
        toast = nil
    }

    // MARK: Panel presentation helpers

    public var subtitle: String {
        guard let lastScanAt else { return "尚未扫描" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return "扫描于 \(formatter.string(from: lastScanAt))"
    }

    public var bannerMessage: String? {
        if isStatusItemSuppressed {
            return "macOS 未在菜单栏中显示 MacBar，请先在「系统设置 → 菜单栏」中允许"
        }
        if !accessibilityStatus.isGranted && signatureChangedSinceLastLaunch && signature.isAdHoc {
            return "本次运行的 MacBar 已重新构建，系统把旧版本的授权视为失效"
        }
        if !accessibilityStatus.isGranted { return "需要辅助功能权限才能隐藏或显示图标" }
        if !conflicts.isEmpty { return "检测到 \(conflicts.joined(separator: "、")) 正在运行" }
        if let critical = findings.first(where: { $0.severity == .critical }) { return critical.message }
        return nil
    }
}
