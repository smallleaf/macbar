import Foundation

/// An auditable record of a single menu bar operation.
public struct OperationLog: Codable, Hashable, Sendable, Identifiable {
    public enum OpType: String, Codable, Sendable {
        case move
        case hide
        case show
        case batchHide
        case batchShow
        case reset
        case restore
        case selfHeal
        case permission
        case scan

        public var displayName: String {
            switch self {
            case .move: "移动"
            case .hide: "隐藏"
            case .show: "显示"
            case .batchHide: "批量隐藏"
            case .batchShow: "批量显示"
            case .reset: "重置布局"
            case .restore: "恢复布局"
            case .selfHeal: "启动自愈"
            case .permission: "权限"
            case .scan: "扫描"
            }
        }
    }

    public enum Result: String, Codable, Sendable {
        case success
        case failed
        case rolledBack
        case skipped
    }

    public var id: UUID
    public var opType: OpType
    public var itemID: String?
    public var itemName: String?
    public var fromSection: MenuBarSection?
    public var toSection: MenuBarSection?
    public var fromFrame: ItemFrame?
    public var toFrame: ItemFrame?
    public var result: Result
    public var errorCode: String?
    public var message: String?
    public var retryCount: Int
    public var durationMs: Int
    public var startedAt: Date
    public var finishedAt: Date
    public var appVersion: String
    public var osVersion: String

    public init(
        id: UUID = UUID(),
        opType: OpType,
        itemID: String? = nil,
        itemName: String? = nil,
        fromSection: MenuBarSection? = nil,
        toSection: MenuBarSection? = nil,
        fromFrame: ItemFrame? = nil,
        toFrame: ItemFrame? = nil,
        result: Result,
        errorCode: String? = nil,
        message: String? = nil,
        retryCount: Int = 0,
        durationMs: Int = 0,
        startedAt: Date = Date(),
        finishedAt: Date = Date(),
        appVersion: String = MacBarVersion.current,
        osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString
    ) {
        self.id = id
        self.opType = opType
        self.itemID = itemID
        self.itemName = itemName
        self.fromSection = fromSection
        self.toSection = toSection
        self.fromFrame = fromFrame
        self.toFrame = toFrame
        self.result = result
        self.errorCode = errorCode
        self.message = message
        self.retryCount = retryCount
        self.durationMs = durationMs
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.appVersion = appVersion
        self.osVersion = osVersion
    }
}

/// Categories written to the unified log. Kept as constants so log output stays
/// searchable: `log stream --predicate 'subsystem == "com.miyuan.macbar"'`.
public enum LogCategory: String, Sendable {
    case app
    case scan
    case layout
    case move
    case permission
    case store
    case compatibility
    case hotkey
    case conflict
}
