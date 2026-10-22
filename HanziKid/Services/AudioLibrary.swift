import AVFoundation
import Foundation

/// 预生成的离线发音（百度 TTS 预生成，打包在 App 里）
///
/// 为什么不直接用系统 TTS：系统读单字只有 0.5 秒左右，又短又急；
/// 预生成的单字约 1.2–1.3 秒，尾音自然，而且整词也一起录好了。
final class AudioLibrary: NSObject, AVAudioPlayerDelegate {
    static let shared = AudioLibrary()

    private var index: [String: URL]?
    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<Bool, Never>?

    private override init() { super.init() }

    /// 全部音频按文件名建索引（打平存放，文件名就是字/词本身）
    private func buildIndex() -> [String: URL] {
        var map: [String: URL] = [:]
        // 打包后可能被拍平到根目录，也可能保留 chars/ words/ 子目录，两种都找一遍
        for subdirectory in [nil, "chars", "words", "audio/chars", "audio/words"] as [String?] {
            for url in Bundle.main.urls(forResourcesWithExtension: "mp3", subdirectory: subdirectory) ?? [] {
                map[url.deletingPathExtension().lastPathComponent] = url
            }
        }
        return map
    }

    var hasAudio: Bool {
        if index == nil { index = buildIndex() }
        return !(index?.isEmpty ?? true)
    }

    func url(for text: String) -> URL? {
        if index == nil { index = buildIndex() }
        return index?[text]
    }

    func duration(for text: String) -> TimeInterval? {
        guard let url = url(for: text), let audio = try? AVAudioPlayer(contentsOf: url) else { return nil }
        return audio.duration
    }

    /// 播放并等到播完；没有对应音频返回 false（调用方回退系统 TTS）
    @discardableResult
    func play(_ text: String) async -> Bool {
        guard let url = url(for: text) else { return false }
        stop()

        let audio: AVAudioPlayer
        do {
            audio = try AVAudioPlayer(contentsOf: url)
        } catch {
            return false
        }
        audio.delegate = self
        audio.prepareToPlay()
        player = audio

        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            self.continuation = continuation
            if !audio.play() {
                self.continuation = nil
                continuation.resume(returning: false)
            }
        }
    }

    func stop() {
        if let player, player.isPlaying {
            player.stop()
        }
        player = nil
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: false)
        }
    }

    // MARK: AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: true)
        }
        self.player = nil
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        if let continuation {
            self.continuation = nil
            continuation.resume(returning: false)
        }
        self.player = nil
    }
}
