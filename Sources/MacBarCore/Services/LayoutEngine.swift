import Foundation

/// Computes where each status item should sit for a given section.
///
/// The algorithm is pure: it receives the current frames and the anchors and
/// returns a plan, which keeps the geometry testable without a window server.
///
/// ## Coordinate model
///
/// Menu bar items live at window level 25 in the top-left origin coordinate
/// space. macOS hides overflowing items by keeping their windows but placing
/// them to the left of the display, which was verified on macOS 26.2 where
/// collapsed Control Center items sat at `x = -398 ... y = -145`. Hiding an item
/// therefore means moving it to a negative `x`, and showing it means moving it
/// back inside `[0, visibleX]`.
///
/// Anchors are boundaries, not widgets:
/// - `visibleX`: rightmost x an item may occupy (left of MacBar's control item).
/// - `hiddenX`: boundary between visible and hidden. Defaults to the display's
///   left edge (`0`).
/// - `alwaysHiddenX`: boundary between hidden and always-hidden, further left.
public struct LayoutEngine: Sendable {
    /// Minimum gap kept between neighbouring items.
    public var spacing: Double
    /// Offset from a boundary so the first item in a section does not collide
    /// with the boundary itself.
    public var boundaryOffset: Double
    /// Space used between items inside the hidden sections.
    public var hiddenSpacing: Double

    public init(spacing: Double = 2, boundaryOffset: Double = 6, hiddenSpacing: Double = 4) {
        self.spacing = spacing
        self.boundaryOffset = boundaryOffset
        self.hiddenSpacing = hiddenSpacing
    }

    /// Determines which section an item belongs to from its frame alone.
    public func deriveSection(for frame: ItemFrame, anchors: LayoutAnchors) -> MenuBarSection {
        let midX = frame.midX
        if let alwaysHiddenX = anchors.alwaysHiddenX, midX < alwaysHiddenX {
            return .alwaysHidden
        }
        if midX < anchors.hiddenX {
            return .hidden
        }
        return .visible
    }

    /// Builds the plan that moves `items` into their target sections.
    ///
    /// Moves for hidden sections are ordered from left to right so placing one
    /// item never shifts an item that has not been placed yet.
    public func plan(
        items: [MenuBarItemRecord],
        targetSections: [String: MenuBarSection],
        anchors: LayoutAnchors,
        display: DisplayGeometry,
        includeAlreadyPlaced: Bool = false
    ) -> LayoutPlan {
        var plan = LayoutPlan()
        let ordered = items.sorted { $0.frame.minX < $1.frame.minX }
        var indexes: [MenuBarSection: Int] = [:]

        for item in ordered {
            guard let section = targetSections[item.id] else { continue }
            plan.targetSections[item.id] = section
            let index = indexes[section, default: 0]
            indexes[section] = index + 1

            let alreadyThere = deriveSection(for: item.frame, anchors: anchors) == section
            if alreadyThere && !includeAlreadyPlaced {
                plan.skipped.append(SkippedMove(itemID: item.id, reason: .alreadyInPlace))
                continue
            }
            guard item.isMovable else {
                plan.skipped.append(SkippedMove(itemID: item.id, reason: .notMovable))
                continue
            }
            if section != .visible && !item.isHideable {
                plan.skipped.append(SkippedMove(itemID: item.id, reason: .notHideable))
                continue
            }
            let target = targetFrame(for: section, index: index, size: item.frame, anchors: anchors, display: display)
            plan.moves.append(PlannedMove(itemID: item.id, from: item.section, to: section, targetFrame: target))
        }

        // Items with no explicit target that are off screen are brought back.
        for item in ordered where targetSections[item.id] == nil {
            guard item.section != .visible, item.isMovable, item.isHideable else { continue }
            let index = indexes[.visible, default: 0]
            indexes[.visible] = index + 1
            let target = targetFrame(for: .visible, index: index, size: item.frame, anchors: anchors, display: display)
            plan.moves.append(PlannedMove(itemID: item.id, from: item.section, to: .visible, targetFrame: target))
        }

        plan.moves.sort { lhs, rhs in
            if lhs.to != rhs.to {
                // Restore visible items first, then hidden from right to left so
                // the section keeps stacking outward.
                return lhs.to.sortIndex < rhs.to.sortIndex
            }
            return lhs.targetFrame.minX > rhs.targetFrame.minX
        }
        return plan
    }

    /// Frame a single item should occupy in the given section at the given index.
    public func targetFrame(
        for section: MenuBarSection,
        index: Int,
        size: ItemFrame,
        anchors: LayoutAnchors,
        display: DisplayGeometry
    ) -> ItemFrame {
        let width = max(size.width, 1)
        let height = size.height > 0 ? size.height : display.menuBarHeight
        switch section {
        case .visible:
            // Pack items to the left of the visible boundary, inwards from the
            // rightmost usable slot.
            let right = anchors.visibleX - boundaryOffset
            let x = right - width - Double(index) * (width + spacing)
            return ItemFrame(x: x, y: display.bounds.minY, width: width, height: height)
        case .hidden:
            // First hidden item ends just left of the visible boundary.
            let right = anchors.hiddenX - boundaryOffset
            let x = right - width - Double(index) * (width + hiddenSpacing)
            return ItemFrame(x: x, y: display.bounds.minY, width: width, height: height)
        case .alwaysHidden:
            let base = anchors.alwaysHiddenX ?? (anchors.hiddenX - 600)
            let right = base - boundaryOffset
            let x = right - width - Double(index) * (width + hiddenSpacing)
            return ItemFrame(x: x, y: display.bounds.minY, width: width, height: height)
        }
    }

    /// True when the item's frame already places it inside `section`.
    public func isAt(item: MenuBarItemRecord, section: MenuBarSection, anchors: LayoutAnchors, tolerance: Double = 6) -> Bool {
        if deriveSection(for: item.frame, anchors: anchors) == section { return true }
        switch section {
        case .visible:
            return item.frame.minX >= anchors.hiddenX - tolerance && item.frame.maxX <= anchors.visibleX + tolerance
        case .hidden:
            return item.frame.maxX <= anchors.hiddenX + tolerance
                && (anchors.alwaysHiddenX.map { item.frame.minX >= $0 - tolerance } ?? true)
        case .alwaysHidden:
            guard let alwaysHiddenX = anchors.alwaysHiddenX else { return false }
            return item.frame.maxX <= alwaysHiddenX + tolerance
        }
    }

    /// Anchors derived from the display geometry.
    public func synthesizedAnchors(display: DisplayGeometry) -> LayoutAnchors {
        LayoutAnchors(
            visibleX: display.bounds.maxX - 8,
            hiddenX: display.bounds.minX,
            alwaysHiddenX: display.bounds.minX - 600
        )
    }

    /// Clamps the plan so hidden moves always end outside the display. This is
    /// the last line of defence against a misconfigured anchor: a hidden item
    /// that stays visible is a user-visible bug, whereas one that overshoots is
    /// harmless.
    public func sanitize(_ plan: LayoutPlan, display: DisplayGeometry) -> LayoutPlan {
        var result = plan
        result.moves = result.moves.map { move in
            var fixed = move
            switch move.to {
            case .visible:
                let minimum = display.bounds.minX + 4
                if fixed.targetFrame.minX < minimum {
                    fixed.targetFrame.x = minimum
                }
                let maximum = display.bounds.maxX - fixed.targetFrame.width - 4
                if fixed.targetFrame.minX > maximum {
                    fixed.targetFrame.x = maximum
                }
            case .hidden:
                let maximum = display.bounds.minX - boundaryOffset * 2
                if fixed.targetFrame.maxX > maximum {
                    fixed.targetFrame.x = maximum - fixed.targetFrame.width
                }
            case .alwaysHidden:
                let boundary = (move.targetFrame.minX < display.bounds.minX - 600)
                    ? move.targetFrame.minX
                    : display.bounds.minX - 600
                let maximum = boundary - boundaryOffset * 2
                if fixed.targetFrame.maxX > maximum {
                    fixed.targetFrame.x = maximum - fixed.targetFrame.width
                }
            }
            return fixed
        }
        return result
    }
}
