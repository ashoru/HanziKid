import AVFoundation
import Foundation

/// 中文发音（系统离线 TTS）
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechService()

    private let synthesizer = AVSpeechSynthesizer()
    private var configured = false
    private var finishContinuation: CheckedContinuation<Void, Never>?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: 会话配置

    func configure() {
        guard !configured else { return }
        configured = true
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
        try? session.setActive(true)
    }

    // MARK: 音色

    /// 普通话（zh-CN）音色列表，按质量排序
    func mandarinVoices() -> [AVSpeechSynthesisVoice] {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "zh-CN" || $0.language.hasPrefix("zh-CN") }
        return voices.sorted { lhs, rhs in
            if lhs.quality.rawValue != rhs.quality.rawValue {
                return lhs.quality.rawValue > rhs.quality.rawValue
            }
            return lhs.name < rhs.name
        }
    }

    /// 猜音色性别：系统没有提供性别字段，只能按音色名判断
    static func gender(of voice: AVSpeechSynthesisVoice) -> SpeechGender {
        let name = voice.name.lowercased()
        let maleHints = ["li-mu", "limu", "li mu", "bo-yang", "boyang", "yunxi", "yunyang", "male"]
        if maleHints.contains(where: { name.contains($0) }) { return .male }
        return .female
    }

    /// 取该性别里质量最高的普通话音色；没有对应性别则返回 nil
    func voice(for gender: SpeechGender, chineseOnly: Bool = true) -> AVSpeechSynthesisVoice? {
        let voices = chineseOnly
            ? mandarinVoices()
            : AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("zh") }
        if let matched = voices.first(where: { Self.gender(of: $0) == gender }) {
            return matched
        }
        return nil
    }

    func hasVoice(for gender: SpeechGender) -> Bool {
        voice(for: gender, chineseOnly: false) != nil
    }

    /// 某个性别实际会用的音色描述（给设置页显示）
    func voiceDescription(for gender: SpeechGender) -> String {
        guard let voice = voice(for: gender, chineseOnly: false) else {
            return "系统未安装\(gender.title)"
        }
        let quality: String
        switch voice.quality {
        case .premium: quality = "高级"
        case .enhanced: quality = "增强"
        default: quality = "标准"
        }
        return "\(voice.name)（\(quality)）"
    }

    // MARK: 朗读

    /// 点读用：打断上一句，直接读
    func speak(_ text: String, rate: Double = 0.45, gender: SpeechGender = .female) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        configure()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        synthesizer.speak(makeUtterance(trimmed, rate: rate, voice: voice(for: gender, chineseOnly: false)))
    }

    /// 连续朗读用：等这一句读完再返回（便于插入跟读停顿）
    func speakAndWait(_ text: String, rate: Double, gender: SpeechGender) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        configure()
        let utterance = makeUtterance(trimmed, rate: rate, voice: voice(for: gender, chineseOnly: false))
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            finishContinuation = continuation
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        finishContinuation?.resume()
        finishContinuation = nil
    }

    private func makeUtterance(_ text: String, rate: Double, voice: AVSpeechSynthesisVoice?) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = Float(max(0.2, min(0.6, rate)))
        utterance.pitchMultiplier = 1.03
        utterance.postUtteranceDelay = 0.02
        return utterance
    }

    // MARK: AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finishContinuation?.resume()
        finishContinuation = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finishContinuation?.resume()
        finishContinuation = nil
    }
}
