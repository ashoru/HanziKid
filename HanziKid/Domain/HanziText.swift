import Foundation

/// 从任意文本里抽汉字（OCR 结果和手动粘贴共用）
///
/// 单独放在 Foundation-only 的文件里，方便在 macOS 上直接跑逻辑测试。
enum HanziText {
    /// 去重、保持出现顺序；标点、拼音、数字、字母全部丢弃
    static func extract(_ text: String) -> [String] {
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
            (0x4E00...0x9FFF).contains(scalar.value)      // CJK 基本区
                || (0x3400...0x4DBF).contains(scalar.value) // 扩展 A
        }
    }
}
