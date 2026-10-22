import AVFoundation
import Foundation
import os

/// 统一的发音入口：优先播预生成音频，没有再退回系统 TTS
enum Pronunciation {
    private static let logger = Logger(subsystem: "com.tangfengjing.hanzikid", category: "audio")

    /// 有预生成音频且用的是女声（预生成是女声）→ 播音频
    private static func canUseBundled(for profile: Profile) -> Bool {
        profile.voiceGender == .female && AudioLibrary.shared.hasAudio
    }

    /// 读完一整句再返回（用于自动朗读的节奏控制）
    static func speakAndWait(_ text: String, profile: Profile) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if canUseBundled(for: profile) {
            let duration = AudioLibrary.shared.duration(for: trimmed) ?? 0
            if await AudioLibrary.shared.play(trimmed) {
                logger.info("bundled audio ok: \(trimmed, privacy: .public) \(duration, privacy: .public)s")
                return
            }
        }
        logger.info("fallback to TTS: \(trimmed, privacy: .public)")
        await SpeechService.shared.speakAndWait(trimmed, rate: profile.speechRate, gender: profile.voiceGender)
    }

    /// 点读用：不等待
    static func speak(_ text: String, profile: Profile) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if canUseBundled(for: profile), AudioLibrary.shared.url(for: trimmed) != nil {
            Task { _ = await AudioLibrary.shared.play(trimmed) }
            return
        }
        SpeechService.shared.speak(trimmed, rate: profile.speechRate, gender: profile.voiceGender)
    }

    /// 立即停止所有发音
    static func stop() {
        AudioLibrary.shared.stop()
        SpeechService.shared.stop()
    }
}
