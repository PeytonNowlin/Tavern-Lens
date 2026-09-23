import Foundation
import zlib

/// gzip (RFC 1952) compression with the system zlib, for saved log slices.
/// Text logs shrink about 10×, and the files open with `gunzip` or `zcat`.
public enum Gzip {
    public enum Failure: Error, Equatable {
        case zlib(Int32)
        case truncated
    }

    public static func compress(_ data: Data, level: Int32 = 6) throws -> Data {
        var stream = z_stream()
        // windowBits 15 + 16: write a gzip header and trailer instead of a zlib one.
        var status = deflateInit2_(
            &stream, level, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)
        )
        guard status == Z_OK else { throw Failure.zlib(status) }
        defer { deflateEnd(&stream) }
        var output = Data()
        let chunk = 1 << 18
        var buffer = [UInt8](repeating: 0, count: chunk)
        try data.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            repeat {
                status = buffer.withUnsafeMutableBufferPointer { out in
                    stream.next_out = out.baseAddress
                    stream.avail_out = uInt(chunk)
                    return deflate(&stream, Z_FINISH)
                }
                guard status == Z_OK || status == Z_STREAM_END || status == Z_BUF_ERROR else { throw Failure.zlib(status) }
                output.append(buffer, count: chunk - Int(stream.avail_out))
            } while status != Z_STREAM_END
        }
        return output
    }

    public static func decompress(_ data: Data) throws -> Data {
        var stream = z_stream()
        // windowBits 15 + 32: accept a gzip or zlib header.
        var status = inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { throw Failure.zlib(status) }
        defer { inflateEnd(&stream) }
        var output = Data()
        let chunk = 1 << 20
        var buffer = [UInt8](repeating: 0, count: chunk)
        try data.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            repeat {
                status = buffer.withUnsafeMutableBufferPointer { out in
                    stream.next_out = out.baseAddress
                    stream.avail_out = uInt(chunk)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                switch status {
                case Z_OK, Z_STREAM_END:
                    output.append(buffer, count: chunk - Int(stream.avail_out))
                case Z_BUF_ERROR where stream.avail_in == 0:
                    throw Failure.truncated
                default:
                    throw Failure.zlib(status)
                }
            } while status != Z_STREAM_END
        }
        return output
    }
}
