import Foundation
import SwiftData

// 与 HanziKidTests/SchedulerTests.swift 一致的断言，用于在无 PTY 环境下验证纯逻辑
var failures = 0
var checks = 0

func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    checks += 1
    if condition() {
        print("  ✓ \(name)")
    } else {
        failures += 1
        print("  ✗ \(name)")
    }
}

let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(secondsFromGMT: 0)!
    return c
}()
let now = Date(timeIntervalSince1970: 1_700_000_000)
var scheduler = Scheduler()
scheduler.calendar = calendar
func dayStart(_ d: Date) -> Date { calendar.startOfDay(for: d) }

print("SM-2 调度器")
let first = scheduler.next(Schedule(), grade: .good, now: now)
check("首次「会了」→ 1 天后再复习", first.intervalDays == 1 && first.reps == 1 && first.state == .review)
check("到期时间落在明天零点", first.due == dayStart(now.addingTimeInterval(86_400)))

let second = scheduler.next(Schedule(state: .review, ease: 2.6, intervalDays: 1, reps: 1), grade: .good, now: now)
check("第二次「会了」→ 3 天", second.intervalDays == 3 && second.reps == 2)

let third = scheduler.next(Schedule(state: .review, ease: 2.6, intervalDays: 3, reps: 2), grade: .good, now: now)
check("第三次「会了」→ 3×2.7≈8 天", third.intervalDays == 8)

let capped = scheduler.next(Schedule(state: .review, ease: 2.8, intervalDays: 5, reps: 3), grade: .good, now: now)
check("难度系数上限 2.8", abs(capped.ease - 2.8) < 0.0001)

let again = scheduler.next(Schedule(state: .review, ease: 2.5, intervalDays: 20, reps: 3), grade: .again, now: now)
check("「不会」→ 10 分钟后重现、连对归零",
      again.state == .learning && again.reps == 0 && again.intervalDays == 0
      && again.due == now.addingTimeInterval(600) && again.lapses == 1)

let floor = scheduler.next(Schedule(state: .review, ease: 1.4, intervalDays: 5, reps: 2), grade: .again, now: now)
check("难度系数下限 1.3", abs(floor.ease - 1.3) < 0.0001)

let hard = scheduler.next(Schedule(state: .review, ease: 2.5, intervalDays: 10, reps: 3), grade: .hard, now: now)
check("「有点忘」→ 间隔只涨 1.2 倍（10→12）", hard.intervalDays == 12 && abs(hard.ease - 2.35) < 0.0001)

let long = scheduler.next(Schedule(state: .review, ease: 2.8, intervalDays: 55, reps: 6), grade: .good, now: now)
check("间隔上限 60 天", long.intervalDays == 60)

let graduated = scheduler.next(Schedule(state: .review, ease: 2.5, intervalDays: 21, reps: 3), grade: .good, now: now)
check("连对 4 次且间隔≥21 天 → 已掌握", graduated.state == .mastered)
check("已掌握的字不再每天出现", graduated.isDue(on: now.addingTimeInterval(86_400 * 365)) == false)
check("新字不算到期", Schedule().isDue(on: now) == false)

var leech = Schedule()
for _ in 0..<4 { leech = scheduler.next(leech, grade: .again, now: now) }
check("错 4 次标记为重点字（leech）", leech.lapses == 4 && leech.isLeech)

print("今日任务排程")

@MainActor
func runPlannerChecks() throws {
    let schema = Schema([Profile.self, CharacterCard.self, Deck.self, SRSState.self, ReviewLog.self])
    let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])

    func freshContext() throws -> ModelContext {
        let context = ModelContext(container)
        try context.delete(model: Profile.self)
        try context.delete(model: SRSState.self)
        try context.delete(model: ReviewLog.self)
        return context
    }

    // 1) 每日上限
    let context = try freshContext()
    let profile = Profile(name: "测试", level: .preschool, emoji: "🐣", activeDeckName: "d")
    profile.newPerDay = 2
    profile.reviewCap = 1
    context.insert(profile)
    for hanzi in ["一", "二", "三"] {
        context.insert(SRSState(profileID: profile.id, hanzi: hanzi,
                                schedule: Schedule(state: .review, ease: 2.5, intervalDays: 1, reps: 1,
                                                   due: Date().addingTimeInterval(-3_600))))
    }
    let states = try context.fetch(FetchDescriptor<SRSState>())
    let plan = TodayPlanner.plan(deckHanzi: ["四", "五", "六", "七"], states: states, profile: profile)
    check("到期复习 3 个，按上限只取 1 个", plan.dueReviewTotal == 3 && plan.reviewCount == 1)
    check("新字按上限只取 2 个", plan.newCount == 2)
    check("任务总数 = 1 复习 + 2 新字", plan.items.count == 3)

    // 2) 已学过的字不该再当新字
    let context2 = try freshContext()
    let profile2 = Profile(name: "测试2", level: .primary, emoji: "🦁", activeDeckName: "d")
    context2.insert(profile2)
    context2.insert(SRSState(profileID: profile2.id, hanzi: "一",
                             schedule: Schedule(state: .review, ease: 2.5, intervalDays: 5, reps: 2,
                                                due: Date().addingTimeInterval(86_400 * 5))))
    let states2 = try context2.fetch(FetchDescriptor<SRSState>())
    let plan2 = TodayPlanner.plan(deckHanzi: ["一", "二", "三"], states: states2, profile: profile2)
    check("未到期的字不出现", plan2.reviewCount == 0)
    check("已学过的字不算新字", plan2.items.map(\.hanzi) == ["二", "三"])

    // 3) 临时加量
    let profile3 = Profile(name: "测试3", level: .preschool, emoji: "🐣")
    profile3.newPerDay = 3
    check("默认新字 3 个", profile3.effectiveNewLimit() == 3)
    profile3.addBonus(new: 2, review: 5)
    check("「今天多学几个」生效", profile3.effectiveNewLimit() == 5 && profile3.effectiveReviewLimit() == profile3.reviewCap + 5)
    let yesterday = Date().addingTimeInterval(-86_400)
    let profile4 = Profile(name: "测试4", level: .preschool, emoji: "🐣")
    profile4.newPerDay = 3
    profile4.addBonus(new: 5, on: yesterday)
    check("跨天后临时加量失效", profile4.effectiveNewLimit(on: yesterday) == 8 && profile4.effectiveNewLimit() == 3)

    // 4) 字表顺序 + 复习优先
    let context3 = try freshContext()
    let profile5 = Profile(name: "测试5", level: .preschool, emoji: "🐣")
    profile5.newPerDay = 3
    context3.insert(profile5)
    let plan3 = TodayPlanner.plan(deckHanzi: ["人", "口", "手", "大"], states: [], profile: profile5)
    check("新字按字表顺序取前 3 个", plan3.items.map(\.hanzi) == ["人", "口", "手"])

    let context4 = try freshContext()
    let profile6 = Profile(name: "测试6", level: .primary, emoji: "🦁")
    profile6.newPerDay = 5
    profile6.reviewCap = 5
    context4.insert(profile6)
    context4.insert(SRSState(profileID: profile6.id, hanzi: "一",
                             schedule: Schedule(state: .review, ease: 2.5, intervalDays: 1, reps: 1,
                                                due: Date().addingTimeInterval(-60))))
    let states4 = try context4.fetch(FetchDescriptor<SRSState>())
    let plan4 = TodayPlanner.plan(deckHanzi: ["二", "三"], states: states4, profile: profile6)
    check("复习排在前面", plan4.items.first?.hanzi == "一" && plan4.items.first?.kind == .review)

    // 5) 学习会话
    let context5 = try freshContext()
    let profile7 = Profile(name: "豆豆", level: .preschool, emoji: "🐣")
    let profile8 = Profile(name: "果果", level: .primary, emoji: "🦁")
    context5.insert(profile7)
    context5.insert(profile8)

    let items = ["一", "二", "三"].map { StudyItem(hanzi: $0, kind: .new, schedule: Schedule()) }
    let session = StudySession(items: items)
    session.grade(.again, profile: profile7, context: context5)
    check("「不会」的字本轮重现一次", session.items.count == 4 && session.items.last?.hanzi == "一")

    let session2 = StudySession(items: [StudyItem(hanzi: "水", kind: .new, schedule: Schedule())])
    session2.grade(.good, profile: profile7, context: context5)
    let waterState = SRSState.find(profileID: profile7.id, hanzi: "水", in: context5)
    check("评分写入复习状态（明天复习）", waterState?.cardState == .review && waterState?.intervalDays == 1)
    let logs = try context5.fetch(FetchDescriptor<ReviewLog>())
    check("评分写入学习记录", logs.contains { $0.hanzi == "水" && $0.grade == .good })
    check("另一个孩子不受影响", SRSState.find(profileID: profile8.id, hanzi: "水", in: context5) == nil)
    check("会话推进到结束", session2.isFinished)
}

MainActor.assumeIsolated {
    do {
        try runPlannerChecks()
    } catch {
        failures += 1
        print("  ✗ 数据库用例异常：\(error)")
    }
}

print("")
print(failures == 0 ? "全部通过：\(checks) 项" : "失败 \(failures) / \(checks) 项")
exit(failures == 0 ? 0 : 1)
