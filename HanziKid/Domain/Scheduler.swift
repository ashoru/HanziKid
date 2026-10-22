import Foundation

// MARK: - 三档自评

/// 孩子只需做三档选择，内部映射到 SM-2 的质量分。
enum ReviewGrade: Int, CaseIterable, Identifiable, Codable {
    case again = 1   // 😕 不会
    case hard = 3    // 🤔 有点忘
    case good = 5    // 😀 会了

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .again: return "不会"
        case .hard: return "有点忘"
        case .good: return "会了"
        }
    }

    var emoji: String {
        switch self {
        case .again: return "😕"
        case .hard: return "🤔"
        case .good: return "😀"
        }
    }
}

// MARK: - 卡片状态

enum CardState: String, Codable {
    case new        // 没学过
    case learning   // 刚学 / 还没记牢
    case review     // 复习中
    case mastered   // 已掌握（不再每日出现）
    case suspended  // 暂停
}

// MARK: - 纯值类型调度状态（便于单元测试）

struct Schedule: Equatable {
    var state: CardState = .new
    var ease: Double = 2.5
    var intervalDays: Int = 0
    var reps: Int = 0
    var lapses: Int = 0
    var due: Date = .distantPast
    var lastReviewedAt: Date?
}

// MARK: - 算法参数

struct SchedulerConfig: Equatable {
    /// 难度系数上下限
    var minEase: Double = 1.3
    var maxEase: Double = 2.8
    /// 间隔天数上限：孩子学字需要保持手感，不做几年级别的大间隔
    var maxIntervalDays: Int = 60
    /// 前两次记住后的间隔
    var firstIntervalDays: Int = 1
    var secondIntervalDays: Int = 3
    /// "有点忘"的间隔增长因子
    var hardFactor: Double = 1.2
    /// "不会"后多久在本轮重新出现
    var relearnMinutes: Int = 10
    /// 连续记住几次且间隔足够长 → 判定已掌握
    var graduateReps: Int = 4
    var graduateMinIntervalDays: Int = 21
    /// 忘记多少次标记为"重点字"（leech）
    var leechThreshold: Int = 4
}

// MARK: - 调度器（SM-2 简化版）

struct Scheduler {
    var config = SchedulerConfig()
    var calendar: Calendar = .current

    /// 输入当前状态与本次评分，输出下一次状态。纯函数，无副作用。
    func next(_ current: Schedule, grade: ReviewGrade, now: Date = Date()) -> Schedule {
        var s = current
        s.lastReviewedAt = now

        switch grade {
        case .good:
            s.ease = min(config.maxEase, s.ease + 0.1)
            s.reps += 1
            let candidate: Int
            if s.reps == 1 {
                candidate = config.firstIntervalDays
            } else if s.reps == 2 {
                candidate = config.secondIntervalDays
            } else {
                let grown = (Double(max(s.intervalDays, 1)) * s.ease).rounded()
                candidate = max(s.intervalDays + 1, Int(grown))
            }
            s.intervalDays = min(config.maxIntervalDays, candidate)
            s.state = .review
            s.due = dueDate(for: now, intervalDays: s.intervalDays)

            if s.reps >= config.graduateReps, s.intervalDays >= config.graduateMinIntervalDays {
                s.state = .mastered
            }

        case .hard:
            s.ease = max(config.minEase, s.ease - 0.15)
            let base = Double(max(s.intervalDays, 1))
            s.intervalDays = min(config.maxIntervalDays,
                                 max(1, Int((base * config.hardFactor).rounded())))
            if s.state == .new { s.state = .learning }
            s.due = dueDate(for: now, intervalDays: s.intervalDays)

        case .again:
            s.ease = max(config.minEase, s.ease - 0.2)
            s.reps = 0
            s.intervalDays = 0
            s.lapses += 1
            s.state = .learning
            s.due = now.addingTimeInterval(TimeInterval(config.relearnMinutes * 60))
        }

        return s
    }

    /// 间隔按"天"对齐到当天零点，避免上午学的字晚上才到期
    private func dueDate(for now: Date, intervalDays: Int) -> Date {
        let target = now.addingTimeInterval(TimeInterval(intervalDays * 86_400))
        return calendar.startOfDay(for: target)
    }
}

// MARK: - 取用判定

extension Schedule {
    /// 今天需要复习吗
    func isDue(on date: Date = Date()) -> Bool {
        switch state {
        case .mastered, .suspended, .new: return false
        case .learning, .review: return due <= date
        }
    }

    var isLeech: Bool { lapses >= SchedulerConfig().leechThreshold }

    /// 给家长看的进度文案
    func humanDescription(scheduler: Scheduler = Scheduler()) -> String {
        switch state {
        case .new: return "还没学"
        case .mastered: return "已掌握"
        case .suspended: return "已暂停"
        case .learning, .review:
            if intervalDays == 0 { return "今天再练" }
            if intervalDays == 1 { return "明天复习" }
            return "\(intervalDays) 天后再复习"
        }
    }
}
