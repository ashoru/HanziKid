import Foundation

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

    var defaultNewPerDay: Int {
        switch self {
        case .preschool: return 3
        case .primary: return 6
        }
    }

    var defaultReviewCap: Int {
        switch self {
        case .preschool: return 12
        case .primary: return 20
        }
    }

    var visibleWordCount: Int {
        switch self {
        case .preschool: return 3
        case .primary: return 6
        }
    }

    var showsMeaning: Bool { true }

    var defaultSpeechRate: Double {
        switch self {
        case .preschool: return 0.38
        case .primary: return 0.48
        }
    }
}

/// 声音性别（只做二选一，具体音色由系统决定）
enum SpeechGender: String, CaseIterable, Identifiable, Codable {
    case female
    case male

    var id: String { rawValue }
    var title: String { self == .female ? "女声" : "男声" }
}

// MARK: - 学习者档案

struct Profile: Identifiable, Codable, Equatable {
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

    // 朗读设置（可选字段，老存档没有也能读出来）
    /// 切到新字后自动朗读
    var autoReadRaw: Bool?
    /// 每一遍之间给孩子的跟读停顿（秒）
    var pauseSecondsRaw: Double?
    /// 声音性别 "female" / "male"
    var voiceGenderRaw: String?
    /// 每个字读几遍
    var repeatCountRaw: Int?
    /// 没有内置音频时，是否联网从百度取发音
    var onlineAudioRaw: Bool?
    /// 每个字要写对几遍才能换下一个（0 = 不要求手写）
    var writesPerCharRaw: Int?
    /// 手写区是否显示淡色范字（描红）
    var handwritingGhostRaw: Bool?

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
        self.autoReadRaw = true
        self.pauseSecondsRaw = level == .preschool ? 1.6 : 1.2
        self.voiceGenderRaw = SpeechGender.female.rawValue
        self.repeatCountRaw = 3
        self.onlineAudioRaw = true
        self.writesPerCharRaw = 2
        self.handwritingGhostRaw = true
    }

    // MARK: 朗读设置

    var autoRead: Bool {
        get { autoReadRaw ?? true }
        set { autoReadRaw = newValue }
    }

    /// 跟读停顿（秒）
    var pauseSeconds: Double {
        get { pauseSecondsRaw ?? (level == .preschool ? 1.6 : 1.2) }
        set { pauseSecondsRaw = newValue }
    }

    var voiceGender: SpeechGender {
        get { SpeechGender(rawValue: voiceGenderRaw ?? "") ?? .female }
        set { voiceGenderRaw = newValue.rawValue }
    }

    var repeatCount: Int {
        get { repeatCountRaw ?? 3 }
        set { repeatCountRaw = newValue }
    }

    /// 联网取发音（安装包里不带音频时用）
    var onlineAudio: Bool {
        get { onlineAudioRaw ?? true }
        set { onlineAudioRaw = newValue }
    }

    /// 每个字要写对几遍才能换下一个字（0 = 不要求手写，1…5）
    var writesPerChar: Int {
        get { min(5, max(0, writesPerCharRaw ?? 2)) }
        set { writesPerCharRaw = min(5, max(0, newValue)) }
    }

    /// 手写区显示淡色范字（关掉就是凭记忆写，更难）
    var handwritingGhost: Bool {
        get { handwritingGhostRaw ?? true }
        set { handwritingGhostRaw = newValue }
    }

    var level: LearnerLevel {
        get { LearnerLevel(rawValue: levelRaw) ?? .preschool }
        set { levelRaw = newValue.rawValue }
    }

    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }

    func effectiveNewLimit(on date: Date = Date()) -> Int {
        let bonus = bonusDateKey == Self.dayKey(for: date) ? bonusNew : 0
        return max(0, newPerDay + bonus)
    }

    func effectiveReviewLimit(on date: Date = Date()) -> Int {
        let bonus = bonusDateKey == Self.dayKey(for: date) ? bonusReview : 0
        return max(0, reviewCap + bonus)
    }

    mutating func addBonus(new: Int = 0, review: Int = 0, on date: Date = Date()) {
        let key = Self.dayKey(for: date)
        if bonusDateKey != key {
            bonusDateKey = key
            bonusNew = 0
            bonusReview = 0
        }
        bonusNew = max(0, bonusNew + new)
        bonusReview = max(0, bonusReview + review)
    }

    var hasBonusToday: Bool {
        bonusDateKey == Self.dayKey(for: Date()) && (bonusNew > 0 || bonusReview > 0)
    }
}

// MARK: - 汉字字卡（全库共享）

struct CharacterCard: Identifiable, Codable, Equatable {
    var id: String { hanzi }
    var hanzi: String
    var pinyin: String
    var pinyinAll: [String]
    var radical: String
    var strokeCount: Int
    var meaning: String
    var words: [String]
    var frequency: Double
    /// 字库外的字（拍照/手动录入的新字）：只有字形和笔顺，内容待补全
    var needsContent: Bool

    init(hanzi: String,
         pinyin: String,
         pinyinAll: [String],
         radical: String,
         strokeCount: Int,
         meaning: String,
         words: [String],
         frequency: Double,
         needsContent: Bool = false) {
        self.hanzi = hanzi
        self.pinyin = pinyin
        self.pinyinAll = pinyinAll
        self.radical = radical
        self.strokeCount = strokeCount
        self.meaning = meaning
        self.words = words
        self.frequency = frequency
        self.needsContent = needsContent
    }

    var isPolyphonic: Bool { pinyinAll.count > 1 }

    func words(for level: LearnerLevel) -> [String] {
        Array(words.prefix(level.visibleWordCount))
    }
}

// MARK: - 字表

struct Deck: Identifiable, Codable, Equatable {
    var id: String { name }
    var name: String
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

struct SRSState: Codable, Equatable {
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
        get {
            Schedule(state: cardState,
                     ease: ease,
                     intervalDays: intervalDays,
                     reps: reps,
                     lapses: lapses,
                     due: due,
                     lastReviewedAt: lastReviewedAt)
        }
        set {
            stateRaw = newValue.state.rawValue
            ease = newValue.ease
            intervalDays = newValue.intervalDays
            reps = newValue.reps
            lapses = newValue.lapses
            due = newValue.due
            lastReviewedAt = newValue.lastReviewedAt
        }
    }
}

// MARK: - 学习记录（只追加）

struct ReviewLog: Identifiable, Codable, Equatable {
    var id: UUID
    var profileID: UUID
    var hanzi: String
    var gradeRaw: Int
    var reviewedAt: Date
    var sessionID: UUID

    init(profileID: UUID, hanzi: String, grade: ReviewGrade, reviewedAt: Date = Date(), sessionID: UUID) {
        self.id = UUID()
        self.profileID = profileID
        self.hanzi = hanzi
        self.gradeRaw = grade.rawValue
        self.reviewedAt = reviewedAt
        self.sessionID = sessionID
    }

    var grade: ReviewGrade { ReviewGrade(rawValue: gradeRaw) ?? .again }
}
