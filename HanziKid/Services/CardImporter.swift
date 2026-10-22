import Foundation
import SwiftData

/// 把识别出来的字收进字库 / 字表
enum CardImporter {
    /// 字库外的字：先建一张"待补全"卡片，保证能学字形和笔顺
    static func ensureCard(for hanzi: String,
                           existing: [String: CharacterCard],
                           context: ModelContext) -> CharacterCard {
        if let card = existing[hanzi] { return card }
        let card = CharacterCard(hanzi: hanzi,
                                 pinyin: "",
                                 pinyinAll: [],
                                 radical: "",
                                 strokeCount: StrokeLibrary.shared.strokeCount(for: hanzi),
                                 meaning: "",
                                 words: [],
                                 frequency: 0,
                                 needsContent: true)
        context.insert(card)
        return card
    }

    /// 批量加入字表（去重、保持顺序），返回实际新增个数
    @discardableResult
    static func add(_ hanziList: [String],
                    to deck: Deck,
                    existing: [String: CharacterCard],
                    context: ModelContext) -> Int {
        var added = 0
        var current = Set(deck.hanziList)
        for hanzi in hanziList {
            _ = ensureCard(for: hanzi, existing: existing, context: context)
            if current.insert(hanzi).inserted {
                deck.hanziList.append(hanzi)
                added += 1
            }
        }
        try? context.save()
        return added
    }

    /// 新建字表并写入
    static func createDeck(named name: String,
                           level: LearnerLevel,
                           hanziList: [String],
                           existing: [String: CharacterCard],
                           context: ModelContext) -> Deck {
        for hanzi in hanziList {
            _ = ensureCard(for: hanzi, existing: existing, context: context)
        }
        let deck = Deck(name: name, hanziList: hanziList, level: level)
        context.insert(deck)
        try? context.save()
        return deck
    }
}
