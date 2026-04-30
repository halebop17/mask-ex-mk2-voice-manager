import Foundation

/// Reading and writing of bank file formats.
///
///   `.m1b`  — raw, no header, packed 64-byte voice records (Kodamo native).
///   `.syx`  — concatenated full SysEx voice frames (132 bytes each).
///   `.csv`  — flat slot/name listing.
public enum FileIO {

    public enum Error: Swift.Error, Equatable {
        case unalignedM1B(Int)          // file size not a multiple of 64
        case malformedSyx(String)
        case writeFailed(String)
    }

    // MARK: .m1b

    public static func readM1B(_ url: URL) throws -> [Voice] {
        let data = try Data(contentsOf: url)
        return try parseM1B(Array(data))
    }

    public static func parseM1B(_ bytes: [UInt8]) throws -> [Voice] {
        let recordSize = MaskProtocol.voiceRecordSize
        guard bytes.count % recordSize == 0 else {
            throw Error.unalignedM1B(bytes.count)
        }
        let count = bytes.count / recordSize
        var voices: [Voice] = []
        voices.reserveCapacity(count)
        for i in 0..<count {
            let start = i * recordSize
            let record = Array(bytes[start..<start + recordSize])
            voices.append(try Voice.fromM1BRecord(record, index: i))
        }
        return voices
    }

    public static func writeM1B(_ voices: [Voice], to url: URL) throws {
        var blob = Data()
        blob.reserveCapacity(voices.count * MaskProtocol.voiceRecordSize)
        for v in voices { blob.append(contentsOf: v.m1bRecord()) }
        try atomicWrite(blob, to: url)
    }

    // MARK: .syx

    public static func readSyx(_ url: URL) throws -> [Voice] {
        let data = try Data(contentsOf: url)
        return try parseSyx(Array(data))
    }

    public static func parseSyx(_ bytes: [UInt8]) throws -> [Voice] {
        var voices: [Voice] = []
        var i = 0
        var index = 0
        while i < bytes.count {
            guard bytes[i] == MaskProtocol.sysExStart else {
                throw Error.malformedSyx("expected F0 at offset \(i)")
            }
            // Find next F7
            guard let endRel = bytes[i...].firstIndex(of: MaskProtocol.sysExEnd) else {
                throw Error.malformedSyx("unterminated SysEx starting at offset \(i)")
            }
            let frame = Array(bytes[i...endRel])
            if frame.count == MaskProtocol.responseFrameSize {
                voices.append(try Voice.fromSysExResponse(frame, index: index))
                index += 1
            }
            // skip frames of the wrong length silently (could be other SysEx mixed in)
            i = endRel + 1
        }
        return voices
    }

    public static func writeSyx(_ voices: [Voice], to url: URL) throws {
        var blob = Data()
        for v in voices { blob.append(contentsOf: v.sysExResponseFrame()) }
        try atomicWrite(blob, to: url)
    }

    // MARK: .csv

    public static func writeCSV(_ voices: [Voice], to url: URL) throws {
        var lines = ["slot,name"]
        for v in voices {
            let escaped = v.displayName.replacingOccurrences(of: "\"", with: "\"\"")
            lines.append(String(format: "%03d,\"%@\"", v.index + 1, escaped))
        }
        let text = lines.joined(separator: "\n") + "\n"
        guard let data = text.data(using: .utf8) else {
            throw Error.writeFailed("could not encode csv as utf-8")
        }
        try atomicWrite(data, to: url)
    }

    // MARK: helpers

    private static func atomicWrite(_ data: Data, to url: URL) throws {
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent("." + url.lastPathComponent + ".tmp")
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try? FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: tmp, to: url)
    }
}
