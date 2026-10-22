import Foundation

// MARK: - 学习队列里的一个字

struct StudyItem: Identifiable, Equatable {
    enum Kind: String {
        case new      // 今天的新字
        case review   // 到期复习
    }

    let id = UUID()
    let hanzi: String
    let kind: Kind
    let schedule: Schedule

    var isNew: Bool { kind == .new }
}

// MARK: - 今日任务排程

enum TodayPlanner {
    struct Plan {
        var items: [StudyItem] = []
        /// 本次任务里的新字数
        var newCount: Int = 0
        /// 本次任务里的复习数
        var reviewCount: Int = 0
        /// 今天共到期多少复习（可能大于上面的 reviewCount，因为受上限限制）
        var dueReviewTotal: Int = 0
        /// 字表里还有多少没学的新字
        var pendingNewTotal: Int = 0
        /// 被每日上限挡在门外的数量
        var deferredCount: Int = 0

        var isEmpty: Bool { items.isEmpty }
    }

    /// - Parameters:
    ///   - deckHanzi: 当前字表的字（决定新字顺序）
    ///   - states: 该孩子的全部复习状态
    ///   - profile: 提供每日新字 / 复习上限（含"今天多学几个"的临时加量）
    static func plan(deckHanzi: [String],
                     states: [SRSState],
                     profile: Profile,
                     now: Date = Date()) -> Plan {
        var plan = Plan()
        let stateByHanzi = Dictionary(states.map { ($0.hanzi, $0) }, uniquingKeysWith: { a, _ in a })

        // 1) 到期复习：逾期最久的优先，反复忘的（leech）插队
        let dueStates = states
            .filter { $0.schedule.isDue(on: now) }
            .sorted { a, b in
                if a.schedule.isLeech != b.schedule.isLeech { return a.schedule.isLeech }
                return a.due < b.due
            }
        plan.dueReviewTotal = dueStates.count
        let reviewLimit = profile.effectiveReviewLimit(on: now)
        let reviewStates = Array(dueStates.prefix(reviewLimit))

        // 2) 新字：按字表顺序，跳过已学过的
        let pendingNew = deckHanzi.filter { hanzi in
            guard let state = stateByHanzi[hanzi] else { return true }
            return state.cardState == .new
        }
        plan.pendingNewTotal = pendingNew.count
        let newLimit = profile.effectiveNewLimit(on: now)
        let chosenNew = Array(pendingNew.prefix(newLimit))

        // 3) 交错排：每 3 个复习塞 1 个新字，避免一口气背新字
        var reviewQueue = reviewStates.map {
            StudyItem(hanzi: $0.hanzi, kind: .review, schedule: $0.schedule)
        }
        var newQueue = chosenNew.map {
            StudyItem(hanzi: $0, kind: .new, schedule: Schedule())
        }
        var merged: [StudyItem] = []
        while !reviewQueue.isEmpty || !newQueue.isEmpty {
            var take = 0
            while take < 3, !reviewQueue.isEmpty {
                merged.append(reviewQueue.removeFirst())
                take += 1
            }
            if !newQueue.isEmpty {
                merged.append(newQueue.removeFirst())
            }
        }

        plan.items = merged
        plan.reviewCount = reviewStates.count
        plan.newCount = chosenNew.count
        plan.deferredCount = max(0, dueStates.count - reviewStates.count)
        return plan
    }
}

// MARK: - 一次学习会话

@MainActor
final class StudySession: ObservableObject {
    @Published private(set) var items: [StudyItem]
    @Published private(set) var index: Int = 0
    @Published private(set) var remembered: Int = 0
    @Published private(set) var struggled: Int = 0
    @Published private(set) var newLearned: Int = 0

    let sessionID = UUID()
    let startedAt = Date()

    init(items: [StudyItem]) {
        self.items = items
    }

    var current: StudyItem? { index < items.count ? items[index] : nil }
    var isFinished: Bool { index >= items.count }
    var progress: Double {
        items.isEmpty ? 1 : min(1, Double(index) / Double(items.count))
    }
    var remaining: Int { max(0, items.count - index) }

    /// 记录一次评分并推进；"不会"的字会在本轮稍后再出现一次
    func grade(_ grade: ReviewGrade,
               profile: Profile,
               store: AppStore,
               scheduler: Scheduler = Scheduler()) {
        guard let item = current else { return }

        let currentSchedule = store.schedule(profileID: profile.id, hanzi: item.hanzi) ?? Schedule()
        let next = scheduler.next(currentSchedule, grade: grade)
        store.applySchedule(profileID: profile.id, hanzi: item.hanzi, schedule: next)
        store.addLog(ReviewLog(profileID: profile.id,
                               hanzi: item.hanzi,
                               grade: grade,
                               sessionID: sessionID))

        switch grade {
        case .good: remembered += 1
        case .hard: struggled += 1
        case .again: struggled += 1
        }
        if item.isNew { newLearned += 1 }

        if grade == .again {
            let again = StudyItem(hanzi: item.hanzi, kind: .review, schedule: next)
            let position = min(items.count, index + 4)
            items.insert(again, at: position)
        }

        index += 1
    }
}
