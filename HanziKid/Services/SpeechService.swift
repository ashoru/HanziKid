import AVFoundation
import Foundation

/// 中文发音（系统离线 TTS）
@MainActor
final class SpeechService {
    static let shared = SpeechService()

    private let synthesizer = AVSpeechSynthesizer()
    private var voice: AVSpeechSynthesisVoice?
    private var configured = false

    private init() {}

    func configure() {
        guard !configured else { return }
        configured = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
        try? session.setActive(true)
        voice = Self.bestChineseVoice()
    }

    /// 优先高质量音色（premium > enhanced > 普通）
    private static func bestChineseVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("zh") }
        if let premium = voices.first(where: { $0.quality == .premium }) { return premium }
        if let enhanced = voices.first(where: { $0.quality == .enhanced }) { return enhanced }
        if let cn = voices.first(where: { $0.language == "zh-CN" }) { return cn }
        return AVSpeechSynthesisVoice(language: "zh-CN")
    }

    /// 朗读一个词或一个字
    func speak(_ text: String, rate: Double = 0.45) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        configure()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = voice
        utterance.rate = Float(max(0.2, min(0.6, rate)))
        utterance.pitchMultiplier = 1.03
        utterance.postUtteranceDelay = 0.02
        synthesizer.speak(utterance)
    }

    /// 慢速重复（长按大字时用）
    func speakSlowly(_ text: String) {
        speak(text, rate: 0.3)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
