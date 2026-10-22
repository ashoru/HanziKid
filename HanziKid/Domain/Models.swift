import Foundation
import SwiftData

// MARK: - 学段

/// 两种学段：5 岁启蒙 / 四年级拓展。决定学习页显示哪些内容、默认每日量。
enum LearnerLevel: Int, Codable, CaseIterable, Identifiable {
    case preschool = 1   // 幼儿园中班（5 岁）
    case primary = 2     // 小学四年级（10 岁）

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .preschool: return "幼儿园中班"
        case .primary: return "小学四年级"
        }
    }

    var emoji: String {
        switch self {
        case .preschool: return "🐣"
        case .primary: return "🦁"
        }
    }

    /// 每日新字默认值（家长可改）
    var defaultNewPerDay: Int {
        switch self {
        case .preschool: return 3
        case .primary: return 6
        }
    }

    /// 每日复习上限默认值（家长可改）
    var defaultReviewCap: Int {
        switch self {
        case .preschool: return 12
        case .primary: return 20
        }
    }

    /// 学习页最多展示几个组词
    var visibleWordCount: Int {
        switch self {
        case .preschool: return 3
        case .primary: return 6
        }
    }

    /// 是否展示释义
    var showsMeaning: Bool { true }

    /// 默认语速（AVSpeechUtterance 0…1）
    var defaultSpeechRate: Double {
        switch self {
        case .preschool: return 0.38
        case .primary: return 0.48
        }
    }
}

// MARK: - 学习者档案

@Model
final class Profile {
    var id: UUID
    var name: String
    var levelRaw: Int
    var emoji: String
    /// 每日新字上限（家长可随时调整）
    var newPerDay: Int
    /// 每日复习上限（家长可随时调整）
    var reviewCap: Int
    var speechRate: Double
    var activeDeckName: String
    var createdAt: Date
    /// 当日临时加量（"今天多学几个"），跨天自动失效
    var bonusDateKey: String
    var bonusNew: Int
    var bonusReview: Int

    init(name: String,
         level: LearnerLevel,
         emoji: String,
         activeDeckName: String = "",
         newPerDay: Int? = nil,
         reviewCap: Int? = nil) {
        self.id = UUID()
        self.name = name
        self.levelRaw = level.rawValue
        self.emoji = emoji
        self.newPerDay = newPerDay ?? level.defaultNewPerDay
        self.reviewCap = reviewCap ?? level.defaultReviewCap
        self.speechRate = level.defaultSpeechRate
        self.activeDeckName = activeDeckName
        self.createdAt = Date()
        self.bonusDateKey = ""
        self.bonusNew = 0
        self.bonusReview = 0
    }

    var level: LearnerLevel {
        get { LearnerLevel(rawValue: levelRaw) ?? .preschool }
        set { levelRaw = newValue.rawValue }
    }

    // MARK: 当日有效上限（含临时加量）

    static func dayKey(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: date)
    }

    /// 今天实际要学的新字数
    func effectiveNewLimit(on date: Date = Date()) -> Int {
        let bonus = bonusDateKey == Self.dayKey(for: date) ? bonusNew : 0
        return max(0, newPerDay + bonus)
    }

    /// 今天实际要复习的字数上限
    func effectiveReviewLimit(on date: Date = Date()) -> Int {
        let bonus = bonusDateKey == Self.dayKey(for: date) ? bonusReview : 0
        return max(0, reviewCap + bonus)
    }

    /// "今天多学几个"
    func addBonus(new: Int = 0, review: Int = 0, on date: Date = Date()) {
        let key = Self.dayKey(for: date)
        if bonusDateKey != key {
            bonusDateKey = key
            bonusNew = 0
            bonusReview = 0
        }
        bonusNew = max(0, bonusNew + new)
        bonusReview = max(0, bonusReview + review)
    }

    /// 今日临时加量是否生效（用于 UI 显示"已加 2 个"）
    var hasBonusToday: Bool {
        bonusDateKey == Self.dayKey(for: Date()) && (bonusNew > 0 || bonusReview > 0)
    }
}

// MARK: - 汉字字卡（全库唯一，两个孩子共享）

@Model
final class CharacterCard {
    @Attribute(.unique) var hanzi: String
    var pinyin: String
    var pinyinAll: [String]
    var radical: String
    var strokeCount: Int
    var meaning: String
    var words: [String]
    var frequency: Double

    init(hanzi: String,
         pinyin: String,
         pinyinAll: [String],
         radical: String,
         strokeCount: Int,
         meaning: String,
         words: [String],
         frequency: Double) {
        self.hanzi = hanzi
        self.pinyin = pinyin
        self.pinyinAll = pinyinAll
        self.radical = radical
        self.strokeCount = strokeCount
        self.meaning = meaning
        self.words = words
        self.frequency = frequency
    }

    var isPolyphonic: Bool { pinyinAll.count > 1 }

    func words(for level: LearnerLevel) -> [String] {
        Array(words.prefix(level.visibleWordCount))
    }
}

// MARK: - 字表

@Model
final class Deck {
    @Attribute(.unique) var name: String
    var hanziList: [String]
    var levelRaw: Int
    var createdAt: Date

    init(name: String, hanziList: [String], level: LearnerLevel) {
        self.name = name
        self.hanziList = hanziList
        self.levelRaw = level.rawValue
        self.createdAt = Date()
    }

    var level: LearnerLevel {
        get { LearnerLevel(rawValue: levelRaw) ?? .preschool }
        set { levelRaw = newValue.rawValue }
    }
}

// MARK: - 复习状态（每个字 × 每个孩子一份）

@Model
final class SRSState {
    var profileID: UUID
    var hanzi: String
    var stateRaw: String
    var ease: Double
    var intervalDays: Int
    var reps: Int
    var lapses: Int
    var due: Date
    var lastReviewedAt: Date?

    init(profileID: UUID, hanzi: String, schedule: Schedule = Schedule()) {
        self.profileID = profileID
        self.hanzi = hanzi
        self.stateRaw = schedule.state.rawValue
        self.ease = schedule.ease
        self.intervalDays = schedule.intervalDays
        self.reps = schedule.reps
        self.lapses = schedule.lapses
        self.due = schedule.due
        self.lastReviewedAt = schedule.lastReviewedAt
    }

    var cardState: CardState {
        get { CardState(rawValue: stateRaw) ?? .new }
        set { stateRaw = newValue.rawValue }
    }

    var schedule: Schedule {
        Schedule(state: cardState,
                 ease: ease,
                 intervalDays: intervalDays,
                 reps: reps,
                 lapses: lapses,
                 due: due,
                 lastReviewedAt: lastReviewedAt)
    }

    func apply(_ s: Schedule) {
        stateRaw = s.state.rawValue
        ease = s.ease
        intervalDays = s.intervalDays
        reps = s.reps
        lapses = s.lapses
        due = s.due
        lastReviewedAt = s.lastReviewedAt
    }

    static func find(profileID: UUID, hanzi: String, in context: ModelContext) -> SRSState? {
        let pid = profileID
        let hz = hanzi
        let predicate = #Predicate<SRSState> { $0.profileID == pid && $0.hanzi == hz }
        var descriptor = FetchDescriptor<SRSState>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func all(profileID: UUID, in context: ModelContext) -> [SRSState] {
        let pid = profileID
        let predicate = #Predicate<SRSState> { $0.profileID == pid }
        return (try? context.fetch(FetchDescriptor<SRSState>(predicate: predicate))) ?? []
    }
}

// MARK: - 学习记录（只追加，用于统计与日后换算法）

@Model
final class ReviewLog {
    var profileID: UUID
    var hanzi: String
    var gradeRaw: Int
    var reviewedAt: Date
    var sessionID: UUID

    init(profileID: UUID, hanzi: String, grade: ReviewGrade, reviewedAt: Date = Date(), sessionID: UUID) {
        self.profileID = profileID
        self.hanzi = hanzi
        self.gradeRaw = grade.rawValue
        self.reviewedAt = reviewedAt
        self.sessionID = sessionID
    }

    var grade: ReviewGrade { ReviewGrade(rawValue: gradeRaw) ?? .again }
}
