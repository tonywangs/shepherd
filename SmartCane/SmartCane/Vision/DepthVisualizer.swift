//
//  DepthVisualizer.swift
//  SmartCane
//
//  Converts depth map CVPixelBuffer to heat map UIImage for visualization
//  Red (close) → Orange → Yellow → Green → Cyan → Blue (far)
//

import Foundation
import UIKit
import CoreVideo
import Accelerate

class DepthVisualizer {
    // Detection range (extended for better visualization)
    private let minDepth: Float = 0.2  // meters
    private let maxDepth: Float = 3.0  // meters

    // Downsampling factor for performance (4x = 16x fewer pixels)
    private let downsampleFactor = 4

    // Pre-allocated buffer for color data (reused across frames)
    private var colorBuffer: [UInt8]?
    private var outputWidth: Int = 0
    private var outputHeight: Int = 0

    /// Convert depth map to heat map UIImage
    /// - Parameters:
    ///   - depthMap: CVPixelBuffer containing Float32 depth values in meters
    ///   - orientation: Device orientation for proper image rotation
    /// - Returns: UIImage with color-coded depth visualization, or nil on error
    func visualize(depthMap: CVPixelBuffer, orientation: UIDeviceOrientation = .portrait) -> UIImage? {
        // Lock pixel buffer for reading
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            print("[DepthVisualizer] Failed to get base address")
            return nil
        }

        // Calculate downsampled dimensions
        let newWidth = width / downsampleFactor
        let newHeight = height / downsampleFactor

        // Allocate color buffer if needed
        if colorBuffer == nil || outputWidth != newWidth || outputHeight != newHeight {
            let pixelCount = newWidth * newHeight
            colorBuffer = [UInt8](repeating: 0, count: pixelCount * 4) // RGBA
            outputWidth = newWidth
            outputHeight = newHeight
            print("[DepthVisualizer] Allocated buffer: \(newWidth)×\(newHeight)")
        }

        guard var buffer = colorBuffer else { return nil }

        // Convert depth to color
        let depthBuffer = baseAddress.assumingMemoryBound(to: Float32.self)
        let stride = bytesPerRow / MemoryLayout<Float32>.stride

        for y in 0..<newHeight {
            for x in 0..<newWidth {
                // Sample from original depth map (downsampling)
                let srcX = x * downsampleFactor
                let srcY = y * downsampleFactor
                let srcIndex = srcY * stride + srcX
                let depth = depthBuffer[srcIndex]

                // Convert depth to color
                let color = depthToColor(depth)

                // Write RGBA values
                let dstIndex = (y * newWidth + x) * 4
                buffer[dstIndex + 0] = color.r
                buffer[dstIndex + 1] = color.g
                buffer[dstIndex + 2] = color.b
                buffer[dstIndex + 3] = 255 // Alpha
            }
        }

        // Create CGImage from color buffer
        guard let image = createImage(from: buffer, width: newWidth, height: newHeight) else {
            print("[DepthVisualizer] Failed to create image")
            return nil
        }

        // Apply rotation based on device orientation
        let imageOrientation: UIImage.Orientation
        switch orientation {
        case .portrait:
            imageOrientation = .right        // Fixed: back to original for portrait
        case .portraitUpsideDown:
            imageOrientation = .left         // Fixed: back to original for portrait
        case .landscapeLeft:
            imageOrientation = .up           // Keep as is (works in landscape)
        case .landscapeRight:
            imageOrientation = .down         // Keep as is (works in landscape)
        default:
            imageOrientation = .right
        }

        return UIImage(cgImage: image, scale: 1.0, orientation: imageOrientation)
    }

    /// Map depth value to heat map color
    /// - Parameter depth: Depth in meters
    /// - Returns: RGB color tuple
    private func depthToColor(_ depth: Float) -> (r: UInt8, g: UInt8, b: UInt8) {
        // Handle invalid depths
        if depth.isNaN || depth.isInfinite {
            return (128, 128, 128) // Gray for invalid
        }

        // Normalize depth to 0.0-1.0 range
        let normalized = (depth - minDepth) / (maxDepth - minDepth)
        let clamped = max(0.0, min(1.0, normalized))

        // Invert so close = 1.0 (red), far = 0.0 (blue)
        let value = 1.0 - clamped

        // Heat map gradient:
        // 0.0 (far)  → Blue   (0, 0, 255)
        // 0.25       → Cyan   (0, 255, 255)
        // 0.5        → Green  (0, 255, 0)
        // 0.75       → Yellow (255, 255, 0)
        // 1.0 (close)→ Red    (255, 0, 0)

        let r: UInt8
        let g: UInt8
        let b: UInt8

        if value < 0.25 {
            // Blue → Cyan
            let t = value / 0.25
            r = 0
            g = UInt8(t * 255)
            b = 255
        } else if value < 0.5 {
            // Cyan → Green
            let t = (value - 0.25) / 0.25
            r = 0
            g = 255
            b = UInt8((1.0 - t) * 255)
        } else if value < 0.75 {
            // Green → Yellow
            let t = (value - 0.5) / 0.25
            r = UInt8(t * 255)
            g = 255
            b = 0
        } else {
            // Yellow → Red
            let t = (value - 0.75) / 0.25
            r = 255
            g = UInt8((1.0 - t) * 255)
            b = 0
        }

        return (r, g, b)
    }

    /// Create CGImage from RGB buffer
    private func createImage(from buffer: [UInt8], width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: UnsafeMutablePointer(mutating: buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }

        return context.makeImage()
    }
}
