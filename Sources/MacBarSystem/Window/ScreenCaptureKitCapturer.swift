import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import MacBarCore
import ScreenCaptureKit

/// Captures individual status item windows as PNG thumbnails.
///
/// ScreenCaptureKit is the supported path on macOS 14+. Captures are best
/// effort: a denied permission or a busy window simply yields `nil`, and the UI
/// falls back to the owning application's icon.
public final class ScreenCaptureKitCapturer: ItemCapturing, @unchecked Sendable {
    private let cache = NSCache<NSString, NSData>()

    public init() {
        cache.countLimit = 128
    }

    public func capture(windowID: UInt32, scale: Double = 2) async -> Data? {
        let key = "\(windowID)-\(scale)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached as Data
        }
        guard CGPreflightScreenCaptureAccess() else {
            return nil
        }
        guard let image = await captureImage(windowID: windowID, scale: scale) else {
            return nil
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        cache.setObject(data as NSData, forKey: key)
        return data
    }

    private func captureImage(windowID: UInt32, scale: Double) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                return nil
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            let width = max(1, Int(window.frame.width * scale))
            let height = max(1, Int(window.frame.height * scale))
            configuration.width = width
            configuration.height = height
            configuration.showsCursor = false
            configuration.captureResolution = .best
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch {
            MacBarLog.warning(.compatibility, "window capture failed code=\(MacBarError.screenCaptureDenied.code)")
            return nil
        }
    }

    /// Stores a thumbnail on disk for diagnostics and offline previews.
    public func persist(data: Data, for itemID: String, directory: URL) {
        let safeName = itemID.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("\(safeName).png")
        try? data.write(to: url, options: .atomic)
    }
}
