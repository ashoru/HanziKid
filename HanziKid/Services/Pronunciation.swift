import AVFoundation
import Foundation
import os

/// 统一发音入口，优先级：
/// 1. 内置音频（如果这个包带了预生成音频）
/// 2. 在线音频（百度 TTS，落盘缓存）——只对女声生效
/// 3. 系统 TTS（兜底，离线可用）
enum Pronunciation {
    private static let logger = Logger(subsystem: "com.tangfengjing.hanzikid", category: "audio")

    /// 读完一整句再返回（自动朗读的节奏控制靠它）
    static func speakAndWait(_ text: String, profile: Profile) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if profile.voiceGender == .female {
            // 1) 内置音频
            if let bundled = AudioLibrary.shared.url(for: trimmed) {
                if await AudioLibrary.shared.play(fileURL: bundled) {
                    logger.info("bundled: \(trimmed, privacy: .public)")
                    return
                }
            }
            // 2) 在线音频（有缓存直接播，没有就现取）
            if profile.onlineAudio {
                if let file = await AudioCache.shared.file(for: trimmed),
                   await AudioLibrary.shared.play(fileURL: file) {
                    logger.info("online: \(trimmed, privacy: .public)")
                    return
                }
                logger.info("online failed, fallback: \(trimmed, privacy: .public)")
            }
        }

        // 3) 系统 TTS
        await SpeechService.shared.speakAndWait(trimmed, rate: profile.speechRate, gender: profile.voiceGender)
    }

    /// 点读用：不等待
    static func speak(_ text: String, profile: Profile) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if profile.voiceGender == .female {
            if let bundled = AudioLibrary.shared.url(for: trimmed) {
                Task { _ = await AudioLibrary.shared.play(fileURL: bundled) }
                return
            }
            if profile.onlineAudio {
                Task {
                    if let file = await AudioCache.shared.file(for: trimmed) {
                        _ = await AudioLibrary.shared.play(fileURL: file)
                    } else {
                        SpeechService.shared.speak(trimmed, rate: profile.speechRate, gender: .female)
                    }
                }
                return
            }
        }

        SpeechService.shared.speak(trimmed, rate: profile.speechRate, gender: profile.voiceGender)
    }

    static func stop() {
        AudioLibrary.shared.stop()
        SpeechService.shared.stop()
    }
}
