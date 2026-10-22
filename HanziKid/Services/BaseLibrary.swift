import Foundation

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
    let version: Int?
    let decks: [DeckSeed]
}

enum BaseLibrary {
    private static func characterPayload() -> CharacterPayload? {
        guard let url = Bundle.main.url(forResource: "base_characters", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(CharacterPayload.self, from: data)
    }

    /// 内置字卡（3500 常用字）
    static func loadCharacters() -> [CharacterCard] {
        guard let payload = characterPayload() else { return [] }
        return payload.characters.map { entry in
            CharacterCard(hanzi: entry.hanzi,
                          pinyin: entry.pinyin,
                          pinyinAll: entry.pinyinAll,
                          radical: entry.radical,
                          strokeCount: entry.strokeCount,
                          meaning: entry.meaning,
                          words: entry.words,
                          frequency: entry.frequency,
                          needsContent: false)
        }
    }

    static func contentHash() -> String {
        characterPayload()?.contentHash ?? ""
    }

    static func loadDecks() -> [DeckSeed] {
        guard let url = Bundle.main.url(forResource: "decks", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return [] }
        guard let payload = try? JSONDecoder().decode(DeckPayload.self, from: data) else { return [] }
        return payload.decks
    }
}
