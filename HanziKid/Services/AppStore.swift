import Foundation
import SwiftUI

/// 全部持久化状态。
///
/// 选择用 Codable + JSON 而不是 Core Data / SwiftData：
/// - 数据量小（3500 字卡只读、状态几千条、日志几千条），一次全量写盘不到 1MB
/// - 没有关系查询需求（按 profileID / hanzi 取即可），自己维护字典更快
/// - 值类型 → SwiftUI 更新、单元测试都直接，不需要 context/线程管理
@MainActor
final class AppStore: ObservableObject {

    // MARK: 对外状态

    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var decks: [Deck] = []
    @Published private(set) var states: [SRSState] = []
    @Published private(set) var logs: [ReviewLog] = []
    /// 字库外的字（拍照 / 手动录入的），内容待补全
    @Published private(set) var customCards: [CharacterCard] = []
    @Published var activeProfileID: UUID?

    // MARK: 内部

    enum Storage {
        case disk
        case memory
    }

    private struct Snapshot: Codable {
        var profiles: [Profile]
        var decks: [Deck]
        var states: [SRSState]
        var logs: [ReviewLog]
        var customCards: [CharacterCard]
        var activeProfileID: UUID?
        var libraryHash: String
    }

    private let storage: Storage
    private let storeURL: URL?
    private var libraryIndex: [String: CharacterCard] = [:]
    private var customIndex: [String: CharacterCard] = [:]
    private var stateIndex: [String: Int] = [:]     // "profileID|hanzi" → states 下标
    private var saveTask: Task<Void, Never>?

    /// 内置字库（启动时从 bundle 读一次）
    private(set) var library: [CharacterCard] = []
    private(set) var libraryHash: String = ""

    // MARK: 初始化

    init(storage: Storage = .disk) {
        self.storage = storage
        switch storage {
        case .memory:
            self.storeURL = nil
        case .disk:
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let folder = base.appendingPathComponent("HanziKid", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            self.storeURL = folder.appendingPathComponent("state.json")
        }

        loadLibrary()
        loadSnapshot()
        seedIfNeeded()
        rebuildIndexes()
        syncSeedDecks()
    }

    // MARK: 字库

    private func loadLibrary() {
        let payload = BaseLibrary.loadCharacters()
        library = payload
        libraryHash = BaseLibrary.contentHash()
        libraryIndex = Dictionary(payload.map { ($0.hanzi, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// 取一个字卡：内置字库优先，其次用户录入的
    func card(for hanzi: String) -> CharacterCard? {
        libraryIndex[hanzi] ?? customIndex[hanzi]
    }

    func cardIndex() -> [String: CharacterCard] {
        guard !customIndex.isEmpty else { return libraryIndex }
        return libraryIndex.merging(customIndex) { builtin, _ in builtin }
    }

    /// 所有可查的字卡（内置 + 自建），用于字库浏览
    var allCards: [CharacterCard] {
        library + customCards
    }

    // MARK: 档案

    func profile(id: UUID) -> Profile? {
        profiles.first { $0.id == id }
    }

    func updateProfile(_ id: UUID, _ mutate: (inout Profile) -> Void) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        mutate(&profiles[index])
        scheduleSave()
    }

    func setActiveProfile(_ id: UUID?) {
        activeProfileID = id
        scheduleSave()
    }

    // MARK: 字表

    func deck(named name: String) -> Deck? {
        decks.first { $0.name == name }
    }

    /// 可选字表：本学段的排在前面，其他学段的也列出来（家长可以给任何一个孩子指派任何字表）
    func decks(for level: LearnerLevel) -> [Deck] {
        let matched = decks.filter { $0.level == level }
        let others = decks.filter { $0.level != level }
        return matched + others
    }

    func updateDeck(named name: String, _ mutate: (inout Deck) -> Void) {
        guard let index = decks.firstIndex(where: { $0.name == name }) else { return }
        mutate(&decks[index])
        scheduleSave()
    }

    // MARK: 复习状态

    private func stateKey(_ profileID: UUID, _ hanzi: String) -> String {
        "\(profileID.uuidString)|\(hanzi)"
    }

    func schedule(profileID: UUID, hanzi: String) -> Schedule? {
        guard let index = stateIndex[stateKey(profileID, hanzi)] else { return nil }
        return states[index].schedule
    }

    func states(for profileID: UUID) -> [SRSState] {
        states.filter { $0.profileID == profileID }
    }

    func applySchedule(profileID: UUID, hanzi: String, schedule newValue: Schedule) {
        let key = stateKey(profileID, hanzi)
        if let index = stateIndex[key] {
            states[index].schedule = newValue
        } else {
            var created = SRSState(profileID: profileID, hanzi: hanzi)
            created.schedule = newValue
            states.append(created)
            stateIndex[key] = states.count - 1
        }
        scheduleSave()
    }

    // MARK: 手动调整进度（字库总览里"勾掉 / 拉回"）

    /// 某个字对这个孩子来说是什么状态（没有记录 = 还没学）
    func cardState(profileID: UUID, hanzi: String) -> CardState {
        schedule(profileID: profileID, hanzi: hanzi)?.state ?? .new
    }

    /// 孩子已经会了的字：直接标记为「已掌握」，不再出现在今日任务里
    func markMastered(profileID: UUID, hanziList: [String], on date: Date = Date()) {
        for hanzi in hanziList {
            var schedule = schedule(profileID: profileID, hanzi: hanzi) ?? Schedule()
            schedule.state = .mastered
            schedule.intervalDays = max(schedule.intervalDays, Scheduler().config.graduateMinIntervalDays)
            schedule.reps = max(schedule.reps, Scheduler().config.graduateReps)
            schedule.due = .distantFuture
            schedule.lastReviewedAt = date
            applySchedule(profileID: profileID, hanzi: hanzi, schedule: schedule)
        }
    }

    func markMastered(profileID: UUID, hanzi: String, on date: Date = Date()) {
        markMastered(profileID: profileID, hanziList: [hanzi], on: date)
    }

    /// 之前会了、后来忘了的字：拉回学习范围（今天就开始复习）
    func revive(profileID: UUID, hanziList: [String], on date: Date = Date()) {
        for hanzi in hanziList {
            var schedule = schedule(profileID: profileID, hanzi: hanzi) ?? Schedule()
            schedule.state = .learning
            schedule.reps = 0
            schedule.intervalDays = 0
            schedule.due = date           // 立刻到期 → 今天的任务里就会出现
            schedule.lastReviewedAt = nil
            applySchedule(profileID: profileID, hanzi: hanzi, schedule: schedule)
        }
    }

    func revive(profileID: UUID, hanzi: String, on date: Date = Date()) {
        revive(profileID: profileID, hanziList: [hanzi], on: date)
    }

    func addLog(_ log: ReviewLog) {
        logs.append(log)
        scheduleSave()
    }

    // MARK: 字卡入库（拍照录入）

    /// 字库外的字：建一张"待补全"卡片，保证能学字形和笔顺
    @discardableResult
    func ensureCard(for hanzi: String) -> CharacterCard {
        if let existing = card(for: hanzi) { return existing }
        let card = CharacterCard(hanzi: hanzi,
                                 pinyin: "",
                                 pinyinAll: [],
                                 radical: "",
                                 strokeCount: StrokeLibrary.shared.strokeCount(for: hanzi),
                                 meaning: "",
                                 words: [],
                                 frequency: 0,
                                 needsContent: true)
        customCards.append(card)
        customIndex[hanzi] = card
        scheduleSave()
        return card
    }

    /// 批量加入字表（去重、保持顺序），返回实际新增个数
    @discardableResult
    func add(_ hanziList: [String], toDeck name: String) -> Int {
        guard let index = decks.firstIndex(where: { $0.name == name }) else { return 0 }
        var current = Set(decks[index].hanziList)
        var added = 0
        for hanzi in hanziList {
            _ = ensureCard(for: hanzi)
            if current.insert(hanzi).inserted {
                decks[index].hanziList.append(hanzi)
                added += 1
            }
        }
        scheduleSave()
        return added
    }

    /// 从字表移除（不删字卡）
    func remove(_ hanzi: String, fromDeck name: String) {
        guard let index = decks.firstIndex(where: { $0.name == name }),
              let position = decks[index].hanziList.firstIndex(of: hanzi) else { return }
        decks[index].hanziList.remove(at: position)
        scheduleSave()
    }

    /// 新建字表（重名则自动加序号）
    @discardableResult
    func createDeck(named name: String, level: LearnerLevel, hanziList: [String]) -> Deck {
        var unique = name
        var counter = 2
        while decks.contains(where: { $0.name == unique }) {
            unique = "\(name) \(counter)"
            counter += 1
        }
        for hanzi in hanziList {
            _ = ensureCard(for: hanzi)
        }
        let deck = Deck(name: unique, hanziList: hanziList, level: level)
        decks.append(deck)
        scheduleSave()
        return deck
    }

    /// 清空某个孩子的学习进度
    func resetProgress(profileID: UUID) {
        states.removeAll { $0.profileID == profileID }
        logs.removeAll { $0.profileID == profileID }
        rebuildStateIndex()
        scheduleSave()
    }

    // MARK: 播种

    private func seedIfNeeded() {
        guard profiles.isEmpty, decks.isEmpty else { return }
        let seeds = BaseLibrary.loadDecks()
        for seed in seeds {
            let level = LearnerLevel(rawValue: seed.level) ?? .preschool
            decks.append(Deck(name: seed.name, hanziList: seed.hanzi, level: level))
        }
        let preschoolDeck = seeds.first { $0.level == LearnerLevel.preschool.rawValue }?.name ?? ""
        let primaryDeck = seeds.first { $0.level == LearnerLevel.primary.rawValue }?.name ?? ""
        let first = Profile(name: "豆豆", level: .preschool, emoji: "🐣", activeDeckName: preschoolDeck)
        let second = Profile(name: "果果", level: .primary, emoji: "🦁", activeDeckName: primaryDeck)
        profiles = [first, second]
        scheduleSave()
    }

    /// 把 decks.json 里新增的字表补进来（老存档也能拿到新字表），并保证每个字都有字卡
    private func syncSeedDecks() {
        var changed = false
        for seed in BaseLibrary.loadDecks() where !decks.contains(where: { $0.name == seed.name }) {
            let level = LearnerLevel(rawValue: seed.level) ?? .preschool
            decks.append(Deck(name: seed.name, hanziList: seed.hanzi, level: level))
            changed = true
        }
        if changed { scheduleSave() }

        // 课本字表里可能有字库外的字（例如 蜻蜓/掰），补成"待补全"卡片，避免学习页空着
        for deck in decks {
            for hanzi in deck.hanziList where card(for: hanzi) == nil {
                _ = ensureCard(for: hanzi)
            }
        }
    }

    // MARK: 索引

    private func rebuildIndexes() {
        customIndex = Dictionary(customCards.map { ($0.hanzi, $0) }, uniquingKeysWith: { a, _ in a })
        rebuildStateIndex()
    }

    private func rebuildStateIndex() {
        var index: [String: Int] = [:]
        index.reserveCapacity(states.count)
        for (position, state) in states.enumerated() {
            index[stateKey(state.profileID, state.hanzi)] = position
        }
        stateIndex = index
    }

    // MARK: 落盘

    private var snapshot: Snapshot {
        Snapshot(profiles: profiles,
                 decks: decks,
                 states: states,
                 logs: logs,
                 customCards: customCards,
                 activeProfileID: activeProfileID,
                 libraryHash: libraryHash)
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard let url = storeURL else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            print("保存失败：\(error)")
        }
    }

    /// 合并短时间内的多次改动，避免每次评分都写盘
    private func scheduleSave() {
        guard storage == .disk else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func loadSnapshot() {
        guard let url = storeURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }
        profiles = decoded.profiles
        decks = decoded.decks
        states = decoded.states
        logs = decoded.logs
        customCards = decoded.customCards
        activeProfileID = decoded.activeProfileID
    }
}
