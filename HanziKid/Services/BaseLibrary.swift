import Foundation
import SwiftData

// MARK: - 内置字库数据

struct LibraryEntry: Decodable {
    let hanzi: String
    let pinyin: String
    let pinyinAll: [String]
    let radical: String
    let strokeCount: Int
    let meaning: String
    let words: [String]
    let frequency: Double
}

private struct CharacterPayload: Decodable {
    let version: Int?
    let contentHash: String?
    let count: Int?
    let characters: [LibraryEntry]
}

struct DeckSeed: Decodable {
    let name: String
    let level: Int
    let hanzi: [String]
}

private struct DeckPayload: Decodable {
    let version: Int
    let decks: [DeckSeed]
}

enum BaseLibrary {
    private static func characterPayload() -> CharacterPayload? {
        guard let url = Bundle.main.url(forResource: "base_characters", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(CharacterPayload.self, from: data)
    }

    static func loadCharacters() -> [LibraryEntry] {
        characterPayload()?.characters ?? []
    }

    /// 字库内容指纹：变了就要重新导入，避免旧数据盖住新内容
    static func contentHash() -> String {
        characterPayload()?.contentHash ?? ""
    }

    static func loadDecks() -> [DeckSeed] {
        guard let url = Bundle.main.url(forResource: "decks", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(DeckPayload.self, from: data)
        else { return [] }
        return payload.decks
    }
}

// MARK: - 首次启动播种

enum LibrarySeeder {
    private static let hashKey = "libraryContentHash"

    /// 幂等：字库内容没变就跳过；内容变了（或首次启动）则重新导入字卡。
    static func seedIfNeeded(_ context: ModelContext) {
        let cardCount = (try? context.fetchCount(FetchDescriptor<CharacterCard>())) ?? 0
        let deckCount = (try? context.fetchCount(FetchDescriptor<Deck>())) ?? 0
        let profileCount = (try? context.fetchCount(FetchDescriptor<Profile>())) ?? 0
        let hash = BaseLibrary.contentHash()
        let storedHash = UserDefaults.standard.string(forKey: hashKey) ?? ""
        let contentChanged = !hash.isEmpty && hash != storedHash

        if cardCount == 0 || contentChanged {
            // 内容更新：旧字卡整体替换（复习进度按 hanzi 关联，不受影响）
            if let existing = try? context.fetch(FetchDescriptor<CharacterCard>()) {
                existing.forEach { context.delete($0) }
            }
            for entry in BaseLibrary.loadCharacters() {
                context.insert(CharacterCard(hanzi: entry.hanzi,
                                             pinyin: entry.pinyin,
                                             pinyinAll: entry.pinyinAll,
                                             radical: entry.radical,
                                             strokeCount: entry.strokeCount,
                                             meaning: entry.meaning,
                                             words: entry.words,
                                             frequency: entry.frequency))
            }
            UserDefaults.standard.set(hash, forKey: hashKey)
        }

        if deckCount == 0 {
            for seed in BaseLibrary.loadDecks() {
                let level = LearnerLevel(rawValue: seed.level) ?? .preschool
                context.insert(Deck(name: seed.name, hanziList: seed.hanzi, level: level))
            }
        }

        if profileCount == 0 {
            let seeds = BaseLibrary.loadDecks()
            let preschoolDeck = seeds.first(where: { $0.level == LearnerLevel.preschool.rawValue })?.name ?? ""
            let primaryDeck = seeds.first(where: { $0.level == LearnerLevel.primary.rawValue })?.name ?? ""

            context.insert(Profile(name: "豆豆", level: .preschool, emoji: "🐣", activeDeckName: preschoolDeck))
            context.insert(Profile(name: "果果", level: .primary, emoji: "🦁", activeDeckName: primaryDeck))
        }

        try? context.save()
    }
}
