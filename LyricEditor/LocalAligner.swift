//
//  LocalAligner.swift
//  LyricEditor
//
//  Swift wrapper around the QwenAligner xcframework's C FFI.
//  Loads the qwen3-aligner-0.6b model once, then handles forced alignment of
//  user-supplied lyrics against decoded PCM samples.
//

import Foundation
import AVFoundation
import QwenAligner

enum LocalAligner {

    /// Word-level alignment result decoded from `qwen_asr_align_pcm`'s JSON.
    struct Aligned: Decodable {
        let text: String
        let start_ms: Double
        let end_ms: Double
    }

    enum AlignerError: Error {
        case modelMissing
        case audioDecodeFailed
        case alignFailed
    }

    // MARK: - Engine lifecycle

    /// Lazily-loaded engine. The model dir must contain the qwen3-aligner-0.6b
    /// weights + tokenizer files. By convention we look under the app's
    /// Application Support directory at `Models/qwen3-aligner-0.6b`.
    private static let engineQueue = DispatchQueue(label: "LocalAligner.engine")
    private static var engineHandle: OpaquePointer? = nil

    private static func loadEngine() throws -> OpaquePointer {
        try engineQueue.sync {
            if let h = engineHandle { return h }
            let dir = modelDirectoryURL
            print("[LocalAligner] loading model from: \(dir.path)")
            print("[LocalAligner] contents: \((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])")
            let handle: OpaquePointer? = dir.path.withCString { cPath in
                qwen_asr_load_model(cPath, 0, 2) // verbosity=2 → loader logs to stderr
            }
            guard let h = handle else { throw AlignerError.modelMissing }
            engineHandle = h
            return h
        }
    }

    /// The qwen3-aligner-0.6b model directory inside the app bundle.
    /// Located via vocab.json's parent — works whether the model was added as a
    /// folder reference (subdir preserved) or a yellow group (files flattened).
    private static var modelDirectoryURL: URL {
        Bundle.main.url(forResource: "vocab", withExtension: "json")!
            .deletingLastPathComponent()
    }

    // MARK: - Alignment

    /// Force-align `lyrics` against the audio at `audioURL`.
    /// Returns word-level timings in milliseconds.
    static func align(
        audioURL: URL,
        lyrics: String,
        language: String = "English"
    ) async throws -> [Aligned] {
        let samples = try decodePCM(from: audioURL)
        let engine = try loadEngine()

        return try await Task.detached(priority: .userInitiated) { () throws -> [Aligned] in
            try samples.withUnsafeBufferPointer { buf -> [Aligned] in
                guard let base = buf.baseAddress else { throw AlignerError.alignFailed }
                let raw: UnsafeMutablePointer<CChar>? = lyrics.withCString { textPtr in
                    language.withCString { langPtr in
                        qwen_asr_align_pcm(
                            engine,
                            base,
                            Int32(buf.count),
                            textPtr,
                            langPtr
                        )
                    }
                }
                guard let cString = raw else { throw AlignerError.alignFailed }
                defer { qwen_asr_free_string(cString) }
                let json = String(cString: cString)
                guard let data = json.data(using: .utf8) else { throw AlignerError.alignFailed }
                return try JSONDecoder().decode([Aligned].self, from: data)
            }
        }.value
    }

    // MARK: - Audio decoding

    /// Decode any AVAudioFile-supported source to 16 kHz, mono, f32 PCM —
    /// the format the aligner expects.
    private static func decodePCM(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else { throw AlignerError.audioDecodeFailed }

        let needsConvert = file.processingFormat != targetFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let inBuffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: frameCount
        ) else { throw AlignerError.audioDecodeFailed }
        try file.read(into: inBuffer)

        let outBuffer: AVAudioPCMBuffer
        if needsConvert {
            guard let converter = AVAudioConverter(from: file.processingFormat, to: targetFormat),
                  let buf = AVAudioPCMBuffer(
                    pcmFormat: targetFormat,
                    frameCapacity: AVAudioFrameCount(Double(frameCount) * 16_000 / file.processingFormat.sampleRate) + 1024
                  ) else { throw AlignerError.audioDecodeFailed }
            var error: NSError?
            var supplied = false
            converter.convert(to: buf, error: &error) { _, status in
                if supplied {
                    status.pointee = .endOfStream
                    return nil
                }
                supplied = true
                status.pointee = .haveData
                return inBuffer
            }
            if error != nil { throw AlignerError.audioDecodeFailed }
            outBuffer = buf
        } else {
            outBuffer = inBuffer
        }

        guard let channelData = outBuffer.floatChannelData?[0] else { throw AlignerError.audioDecodeFailed }
        return Array(UnsafeBufferPointer(start: channelData, count: Int(outBuffer.frameLength)))
    }
}
