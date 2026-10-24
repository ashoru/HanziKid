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

// MARK: - 年级（幼儿园小班 … 六年级，可自定义 + 按时间自动升）

/// 年级用 0…8 的序号表示，比 LearnerLevel 细一档；
/// 内容层面仍然只分「幼儿园 / 小学」两个学段（LearnerLevel），由年级换算得出。
enum SchoolGrade {
    /// 0 = 幼儿园小班 … 8 = 六年级
    static let all: [Int] = Array(0...8)
    static let minIndex = 0
    static let maxIndex = 8

    private static let kindergarten = ["小班", "中班", "大班"]
    private static let primary = ["一", "二", "三", "四", "五", "六"]

    /// 完整名称：幼儿园中班 / 四年级
    static func title(_ index: Int) -> String {
        let value = clamp(index)
        if value <= 2 { return "幼儿园" + kindergarten[value] }
        return primary[value - 3] + "年级"
    }

    /// 短名称：中班 / 四年级
    static func shortTitle(_ index: Int) -> String {
        let value = clamp(index)
        if value <= 2 { return kindergarten[value] }
        return primary[value - 3] + "年级"
    }

    /// 内容学段：幼儿园（0…2）/ 小学（3…8）
    static func level(for index: Int) -> LearnerLevel {
        clamp(index) <= 2 ? .preschool : .primary
    }

    /// 该学段的默认年级（新建档案用）
    static func defaultIndex(for level: LearnerLevel) -> Int {
        switch level {
        case .preschool: return 1   // 幼儿园中班
        case .primary: return 6     // 四年级（3=一、4=二、5=三、6=四）
        }
    }

    static func clamp(_ index: Int) -> Int {
        min(maxIndex, max(minIndex, index))
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
    /// 每个读音读几个组词（0 = 不读词）
    var wordsPerCardRaw: Int?
    /// 多音字是否也把其他读音的组词读出来
    var readsPolyphonicRaw: Bool?
    /// 每个字要写对几遍才能换下一个（0 = 不要求手写）
    var writesPerCharRaw: Int?
    /// 手写区是否显示淡色范字（描红）
    var handwritingGhostRaw: Bool?

    // 年级（可选字段，老存档按 levelRaw 推断）
    /// 基准年级：0 = 幼儿园小班 … 8 = 六年级（家长设置那一刻的年级）
    var gradeRaw: Int?
    /// 基准年级对应的「升年级日」（yyyy-MM-dd），为空则按"最近一个升年级日"处理
    var gradeAnchorRaw: String?
    /// 每年几月升年级（1…12，默认 9）
    var gradeMonthRaw: Int?
    /// 到时间自动升年级
    var autoGradeRaw: Bool?

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
        self.wordsPerCardRaw = 2
        self.readsPolyphonicRaw = true
        self.gradeRaw = SchoolGrade.defaultIndex(for: level)
        self.gradeAnchorRaw = nil
        self.gradeMonthRaw = 9
        self.autoGradeRaw = true
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

    /// 每个读音读几个组词（0…4）
    var wordsPerCard: Int {
        get { min(4, max(0, wordsPerCardRaw ?? 2)) }
        set { wordsPerCardRaw = min(4, max(0, newValue)) }
    }

    /// 多音字是否也读其他读音的组词
    var readsPolyphonic: Bool {
        get { readsPolyphonicRaw ?? true }
        set { readsPolyphonicRaw = newValue }
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

    /// 内容学段：由当前年级换算（升年级跨入小学后自动变成 .primary）
    var level: LearnerLevel { SchoolGrade.level(for: grade()) }

    // MARK: 年级

    /// 每年几月升年级（中国学年 9 月开学）
    var gradeMonth: Int {
        get { min(12, max(1, gradeMonthRaw ?? 9)) }
        set { gradeMonthRaw = min(12, max(1, newValue)) }
    }

    /// 到时间自动升年级
    var autoGrade: Bool {
        get { autoGradeRaw ?? true }
        set { autoGradeRaw = newValue }
    }

    /// 基准年级（家长设置的那个年级；老存档按学段推断）
    var gradeBase: Int {
        if let raw = gradeRaw { return SchoolGrade.clamp(raw) }
        return SchoolGrade.defaultIndex(for: LearnerLevel(rawValue: levelRaw) ?? .preschool)
    }

    /// 基准年级的起始日（升年级日的那个月 1 号）。只存「年-月」，避免时区把日期挪一天
    private func gradeAnchor(calendar: Calendar) -> Date? {
        guard let text = gradeAnchorRaw else { return nil }
        let parts = text.split(separator: "-")
        guard parts.count >= 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        return calendar.date(from: components)
    }

    /// 当前年级（自动升年级后）；0 = 幼儿园小班 … 8 = 六年级
    func grade(on date: Date = Date(), calendar: Calendar = .current) -> Int {
        let base = gradeBase
        guard autoGrade else { return base }
        let anchor = gradeAnchor(calendar: calendar)
            ?? Profile.gradeBoundary(onOrBefore: date, month: gradeMonth, calendar: calendar)
        let steps = Profile.gradeSteps(after: anchor, until: date, month: gradeMonth, calendar: calendar)
        return SchoolGrade.clamp(base + steps)
    }

    var gradeTitle: String { SchoolGrade.title(grade()) }

    var gradeShortTitle: String { SchoolGrade.shortTitle(grade()) }

    /// 下次升年级是哪天（已到最高年级则为 nil）
    func nextGradeDate(on date: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard grade(on: date, calendar: calendar) < SchoolGrade.maxIndex else { return nil }
        let boundary = Profile.gradeBoundary(onOrBefore: date, month: gradeMonth, calendar: calendar)
        var components = calendar.dateComponents([.year, .month], from: boundary)
        components.year = (components.year ?? 0) + 1
        return calendar.date(from: components)
    }

    /// 下次升到几年级（文案用）
    func nextGradeTitle(on date: Date = Date(), calendar: Calendar = .current) -> String {
        guard let next = nextGradeDate(on: date, calendar: calendar) else { return gradeTitle }
        return SchoolGrade.title(grade(on: next, calendar: calendar))
    }

    /// 家长手动改年级：基准年级改为当前，并从"最近一个升年级日"重新计数
    mutating func setGrade(_ index: Int, on date: Date = Date(), calendar: Calendar = .current) {
        gradeRaw = SchoolGrade.clamp(index)
        let boundary = Profile.gradeBoundary(onOrBefore: date, month: gradeMonth, calendar: calendar)
        let parts = calendar.dateComponents([.year, .month], from: boundary)
        gradeAnchorRaw = String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 1)
    }

    /// 自动升年级是否已经生效（设的是 X 年级，现在算出来更高）
    func didAutoUpgrade(on date: Date = Date(), calendar: Calendar = .current) -> Bool {
        autoGrade && grade(on: date, calendar: calendar) > gradeBase
    }

    /// `date` 当天或之前最近的升年级日（某年 `month` 月 1 日）
    static func gradeBoundary(onOrBefore date: Date, month: Int, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.year, .month], from: date)
        let year = parts.year ?? 2000
        let currentMonth = parts.month ?? 12
        let targetYear = currentMonth >= month ? year : year - 1
        var components = DateComponents()
        components.year = targetYear
        components.month = month
        components.day = 1
        return calendar.date(from: components) ?? date
    }

    /// (after, until] 之间跨过了几个升年级日
    static func gradeSteps(after anchor: Date, until date: Date, month: Int, calendar: Calendar) -> Int {
        guard anchor < date else { return 0 }
        let startYear = calendar.component(.year, from: anchor)
        let endYear = calendar.component(.year, from: date)
        guard startYear <= endYear + 1 else { return 0 }
        var steps = 0
        for year in startYear...(endYear + 1) {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = 1
            guard let boundary = calendar.date(from: components) else { continue }
            if boundary > anchor && boundary <= date { steps += 1 }
        }
        return steps
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

// MARK: - 组词（按读音分组）

struct WordGroup: Codable, Equatable, Identifiable {
    /// 该组词对应的读音（多音字每个读音一组）
    var pinyin: String
    var words: [String]
    var id: String { pinyin }
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
    /// 全部组词（平铺，搜索用；顺序 = 读音组顺序）
    var words: [String]
    /// 按读音分组的组词（多音字每个读音一组，每组 2 个常用词）
    var wordGroups: [WordGroup]
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
         wordGroups: [WordGroup] = [],
         frequency: Double,
         needsContent: Bool = false) {
        self.hanzi = hanzi
        self.pinyin = pinyin
        self.pinyinAll = pinyinAll
        self.radical = radical
        self.strokeCount = strokeCount
        self.meaning = meaning
        self.words = words
        self.wordGroups = wordGroups
        self.frequency = frequency
        self.needsContent = needsContent
    }

    var isPolyphonic: Bool { pinyinAll.count > 1 }

    /// 按读音分组取组词：`limitPerReading` 每个读音几个词；`includeOtherReadings` 是否连其他读音一起给
    func readingGroups(limitPerReading: Int, includeOtherReadings: Bool) -> [WordGroup] {
        let limit = max(0, limitPerReading)
        guard limit > 0 else { return [] }
        guard !wordGroups.isEmpty else {
            let fallback = Array(words.prefix(limit))
            return fallback.isEmpty ? [] : [WordGroup(pinyin: pinyin, words: fallback)]
        }
        let limited = wordGroups.map { WordGroup(pinyin: $0.pinyin, words: Array($0.words.prefix(limit))) }
            .filter { !$0.words.isEmpty }
        return includeOtherReadings ? limited : Array(limited.prefix(1))
    }

    /// 朗读顺序用的词序列（先主读音的词，再多音字其他读音的词）
    func wordsToRead(limitPerReading: Int, includeOtherReadings: Bool) -> [String] {
        readingGroups(limitPerReading: limitPerReading, includeOtherReadings: includeOtherReadings)
            .flatMap { $0.words }
    }

    /// 主读音的组词（老的调用点用）
    func words(for level: LearnerLevel) -> [String] {
        let limit = level.visibleWordCount
        if let first = wordGroups.first {
            return Array(first.words.prefix(limit))
        }
        return Array(words.prefix(limit))
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
