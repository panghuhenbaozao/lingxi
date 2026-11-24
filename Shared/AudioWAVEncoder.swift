import Foundation

/// 轻量 16kHz 单声道 PCM16 ↔ WAV 编解码工具（纯 Foundation，无第三方依赖，可直接单元测试）：
/// 用于键盘内 `WKWebView` 采集到的 16kHz PCM 音频流打包为标准 RIFF/WAV，供云端多模态音频模型（Gemini / Whisper）兜底转写。
enum AudioWAVEncoder {
    /// 将 16-bit Little-Endian 单声道 PCM 原始字节打包为标准 44 字节头 WAV 数据。
    static func encodePCM16MonoToWAV(pcm16Data: Data, sampleRate: Int = 16_000) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate * Int(numChannels) * Int(bitsPerSample / 8))
        let blockAlign = numChannels * (bitsPerSample / 8)
        let subchunk2Size = UInt32(pcm16Data.count)
        let chunkSize = UInt32(36) + subchunk2Size
        var sr = UInt32(sampleRate)
        var subchunk1Size: UInt32 = 16
        var audioFormat: UInt16 = 1
        var ch = numChannels
        var br = byteRate
        var ba = blockAlign
        var bps = bitsPerSample
        var cs = chunkSize
        var s2 = subchunk2Size

        var wav = Data(capacity: 44 + pcm16Data.count)
        wav.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        withUnsafeBytes(of: &cs) { wav.append(contentsOf: $0) }
        wav.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        wav.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        withUnsafeBytes(of: &subchunk1Size) { wav.append(contentsOf: $0) }
        withUnsafeBytes(of: &audioFormat) { wav.append(contentsOf: $0) }
        withUnsafeBytes(of: &ch) { wav.append(contentsOf: $0) }
        withUnsafeBytes(of: &sr) { wav.append(contentsOf: $0) }
        withUnsafeBytes(of: &br) { wav.append(contentsOf: $0) }
        withUnsafeBytes(of: &ba) { wav.append(contentsOf: $0) }
        withUnsafeBytes(of: &bps) { wav.append(contentsOf: $0) }
        wav.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        withUnsafeBytes(of: &s2) { wav.append(contentsOf: $0) }
        wav.append(pcm16Data)
        return wav
    }

    /// 将 16-bit Little-Endian PCM 转为归一化的 Float32 采样数组（[-1.0, 1.0]），供 `AVAudioPCMBuffer` 喂给 `SFSpeechAudioBufferRecognitionRequest`。
    static func pcm16ToFloat32Samples(_ pcm16Data: Data) -> [Float] {
        let count = pcm16Data.count / 2
        guard count > 0 else { return [] }
        var out = [Float](repeating: 0, count: count)
        pcm16Data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            let int16Ptr = base.assumingMemoryBound(to: Int16.self)
            let scale: Float = 1.0 / 32768.0
            for i in 0..<count {
                let sample = Int16(littleEndian: int16Ptr[i])
                out[i] = Float(sample) * scale
            }
        }
        return out
    }
}
