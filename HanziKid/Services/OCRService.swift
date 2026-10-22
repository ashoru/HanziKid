import Foundation
import UIKit
import Vision

/// 离线中文识别（Vision 框架，不需要联网）
enum OCRService {
    enum OCRError: LocalizedError {
        case invalidImage
        case empty

        var errorDescription: String? {
            switch self {
            case .invalidImage: return "这张照片读不出来，换一张试试"
            case .empty: return "没认到汉字，可能要拍得正一点、清楚一点"
            }
        }
    }

    struct Outcome {
        /// 识别出的整段文字（按行）
        let text: String
        /// 去重后的汉字，保持出现顺序
        let hanzi: [String]
    }

    /// 识别图片里的中文文字
    static func recognize(in image: UIImage) async throws -> Outcome {
        guard let cgImage = image.cgImage else { throw OCRError.invalidImage }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage,
                                            orientation: cgOrientation(from: image.imageOrientation),
                                            options: [:])

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        let observations = request.results ?? []
        let text = observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")

        let hanzi = extractHanzi(from: text)
        guard !hanzi.isEmpty else { throw OCRError.empty }
        return Outcome(text: text, hanzi: hanzi)
    }

    /// 从任意文本里抽出汉字（去重、保持顺序）
    static func extractHanzi(from text: String) -> [String] {
        var seen = Set<Character>()
        var result: [String] = []
        for character in text where isHanzi(character) {
            if seen.insert(character).inserted {
                result.append(String(character))
            }
        }
        return result
    }

    static func isHanzi(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)      // 基本区
                || (0x3400...0x4DBF).contains(scalar.value) // 扩展 A
        }
    }

    private static func cgOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
