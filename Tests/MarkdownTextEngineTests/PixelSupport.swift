import CoreGraphics

// MARK: - Shared pixel test support

/// A single RGBA8 pixel value, used in bitmap-sampling assertions.
struct Pixel: Equatable {
    let r, g, b, a: UInt8
}

/// Reads one RGBA pixel from a raw RGBA8 bitmap buffer at the given column/row.
func pixel(at x: Int, y: Int, width: Int, buffer: UnsafeMutableRawPointer) -> Pixel {
    let offset = (y * width + x) * 4
    let p = buffer.assumingMemoryBound(to: UInt8.self)
    return Pixel(r: p[offset], g: p[offset + 1], b: p[offset + 2], a: p[offset + 3])
}

/// Creates a fresh white RGBA8 CGContext and returns `(context, rawBuffer)`.
/// The caller is responsible for calling `rawBuffer.deallocate()` when done.
func makeWhiteContext(width: Int, height: Int)
    -> (ctx: CGContext, buffer: UnsafeMutableRawPointer)?
{
    let bytesPerRow = width * 4
    let bufferSize = height * bytesPerRow
    let rawBuffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
    rawBuffer.initializeMemory(as: UInt8.self, repeating: 0xFF, count: bufferSize)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(
            data: rawBuffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        rawBuffer.deallocate()
        return nil
    }
    return (ctx, rawBuffer)
}
