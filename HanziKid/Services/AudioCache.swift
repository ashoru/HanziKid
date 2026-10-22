import CryptoKit
import Foundation
import os

/// 在线发音缓存：从百度 TTS 现取现播，落盘缓存，下次直接用
///
/// 和「预生成音频打包」相比：安装包小很多（不用背 83MB），
/// 而且拍照新录入的字、新加的组词也能自动有声音。
final class AudioCache {
    static let shared = AudioCache()
    private static let logger = Logger(subsystem: "com.tangfengjing.hanzikid", category: "audio")

    private let folder: URL
    private let session: URLSession
    private var pending: Set<String> = []
    private let lock = NSLock()

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        folder = caches.appendingPathComponent("tts", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 6
        configuration.timeoutIntervalForResource = 12
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    /// 单字读慢一点（spd=2），组词用正常语速（spd=3）
    static func speed(for text: String) -> Int {
        text.count <= 1 ? 2 : 3
    }

    // MARK: 缓存路径

    private func cacheKey(for text: String) -> String {
        let digest = SHA256.hash(data: Data("\(Self.speed(for: text))|\(text)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func fileURL(for text: String) -> URL {
        folder.appendingPathComponent(cacheKey(for: text) + ".mp3")
    }

    /// 已缓存的本地文件（没有则 nil）
    func cachedFile(for text: String) -> URL? {
        let url = fileURL(for: text)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: 取音频

    /// 命中缓存直接返回；否则下载后返回；失败返回 nil（调用方回退系统 TTS）
    func file(for text: String) async -> URL? {
        if let cached = cachedFile(for: text) { return cached }
        return await download(text)
    }

    private func download(_ text: String) async -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let key = cacheKey(for: trimmed)
        lock.lock()
        let duplicate = !pending.insert(key).inserted
        lock.unlock()
        if duplicate {
            // 已经在下了，等一下再看缓存
            try? await Task.sleep(nanoseconds: 300_000_000)
            return cachedFile(for: trimmed)
        }
        defer {
            lock.lock()
            pending.remove(key)
            lock.unlock()
        }

        var components = URLComponents(string: "https://fanyi.baidu.com/gettts")
        components?.queryItems = [
            URLQueryItem(name: "lan", value: "zh"),
            URLQueryItem(name: "text", value: trimmed),
            URLQueryItem(name: "spd", value: String(Self.speed(for: trimmed))),
            URLQueryItem(name: "source", value: "web"),
        ]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPad; CPU OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
                         forHTTPHeaderField: "User-Agent")
        request.setValue("https://fanyi.baidu.com/", forHTTPHeaderField: "Referer")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count > 1500 else {
                return nil
            }
            let target = fileURL(for: trimmed)
            try data.write(to: target, options: .atomic)
            return target
        } catch {
            return nil
        }
    }

    // MARK: 预取

    /// 后台把这些字/词的音频提前下好（不阻塞当前播放）
    func prefetch(_ texts: [String]) {
        let unique = Array(Set(texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            .filter { !$0.isEmpty }
        guard !unique.isEmpty else { return }
        Self.logger.info("prefetch: \(unique.joined(separator: ","), privacy: .public)")
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            for text in unique {
                if Task.isCancelled { return }
                if self.cachedFile(for: text) != nil { continue }
                _ = await self.file(for: text)
            }
        }
    }

    var cachedCount: Int {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path).count) ?? 0
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
}
