import XCTest
import SwiftData
@testable import HanziKid

// MARK: - 调度器纯逻辑

final class SchedulerTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    /// 固定时间点，保证测试可重复
    private var now: Date { Date(timeIntervalSince1970: 1_700_000_000) }

    private func scheduler() -> Scheduler {
        var s = Scheduler()
        s.calendar = calendar
        return s
    }

    private func dayStart(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    func testFirstGoodSchedulesTomorrow() {
        let result = scheduler().next(Schedule(), grade: .good, now: now)
        XCTAssertEqual(result.reps, 1)
        XCTAssertEqual(result.intervalDays, 1)
        XCTAssertEqual(result.state, .review)
        XCTAssertEqual(result.due, dayStart(now.addingTimeInterval(86_400)))
    }

    func testSecondGoodSchedulesThreeDays() {
        let start = Schedule(state: .review, ease: 2.6, intervalDays: 1, reps: 1)
        let result = scheduler().next(start, grade: .good, now: now)
        XCTAssertEqual(result.reps, 2)
        XCTAssertEqual(result.intervalDays, 3)
    }

    func testThirdGoodMultipliesByEase() {
        let start = Schedule(state: .review, ease: 2.6, intervalDays: 3, reps: 2)
        let result = scheduler().next(start, grade: .good, now: now)
        // ease → 2.7，3 × 2.7 = 8.1 → 8
        XCTAssertEqual(result.intervalDays, 8)
        XCTAssertEqual(result.ease, 2.7, accuracy: 0.0001)
    }

    func testEaseStopsAtMaximum() {
        let start = Schedule(state: .review, ease: 2.8, intervalDays: 5, reps: 3)
        let result = scheduler().next(start, grade: .good, now: now)
        XCTAssertEqual(result.ease, 2.8, accuracy: 0.0001)
    }

    func testAgainResetsAndComesBackInTenMinutes() {
        let start = Schedule(state: .review, ease: 2.5, intervalDays: 20, reps: 3)
        let result = scheduler().next(start, grade: .again, now: now)
        XCTAssertEqual(result.state, .learning)
        XCTAssertEqual(result.reps, 0)
        XCTAssertEqual(result.intervalDays, 0)
        XCTAssertEqual(result.lapses, 1)
        XCTAssertEqual(result.due, now.addingTimeInterval(600))
    }

    func testEaseStopsAtMinimum() {
        let start = Schedule(state: .review, ease: 1.4, intervalDays: 5, reps: 2)
        let result = scheduler().next(start, grade: .again, now: now)
        XCTAssertEqual(result.ease, 1.3, accuracy: 0.0001)
    }

    func testHardGrowsIntervalSlowly() {
        let start = Schedule(state: .review, ease: 2.5, intervalDays: 10, reps: 3)
        let result = scheduler().next(start, grade: .hard, now: now)
        XCTAssertEqual(result.intervalDays, 12)
        XCTAssertEqual(result.ease, 2.35, accuracy: 0.0001)
    }

    func testIntervalNeverExceedsSixtyDays() {
        let start = Schedule(state: .review, ease: 2.8, intervalDays: 55, reps: 6)
        let result = scheduler().next(start, grade: .good, now: now)
        XCTAssertEqual(result.intervalDays, 60)
    }

    func testGraduatesToMastered() {
        let start = Schedule(state: .review, ease: 2.5, intervalDays: 21, reps: 3)
        let result = scheduler().next(start, grade: .good, now: now)
        XCTAssertEqual(result.state, .mastered)
        // 已掌握的字不再出现在每日复习里
        XCTAssertFalse(result.isDue(on: now.addingTimeInterval(86_400 * 365)))
    }

    func testLeechDetectedAfterRepeatedFailures() {
        var schedule = Schedule()
        var current = schedule
        for _ in 0..<4 {
            current = scheduler().next(current, grade: .again, now: now)
        }
        schedule = current
        XCTAssertEqual(schedule.lapses, 4)
        XCTAssertTrue(schedule.isLeech)
    }

    func testNewCardIsNotDue() {
        XCTAssertFalse(Schedule().isDue(on: now))
    }

    func testMasteredCardIsNotDue() {
        let schedule = Schedule(state: .mastered, intervalDays: 30, due: now.addingTimeInterval(-86_400))
        XCTAssertFalse(schedule.isDue(on: now))
    }
}

// MARK: - 今日任务排程

@MainActor
final class TodayPlannerTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Profile.self, CharacterCard.self, Deck.self, SRSState.self, ReviewLog.self])
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    func testPlanRespectsDailyLimits() throws {
        let context = try makeContext()
        let profile = Profile(name: "测试", level: .preschool, emoji: "🐣", activeDeckName: "d")
        profile.newPerDay = 2
        profile.reviewCap = 1
        context.insert(profile)

        for hanzi in ["一", "二", "三"] {
            context.insert(SRSState(profileID: profile.id,
                                    hanzi: hanzi,
                                    schedule: Schedule(state: .review,
                                                       ease: 2.5,
                                                       intervalDays: 1,
                                                       reps: 1,
                                                       due: Date().addingTimeInterval(-3_600))))
        }

        let states = try context.fetch(FetchDescriptor<SRSState>())
        let plan = TodayPlanner.plan(deckHanzi: ["四", "五", "六", "七"], states: states, profile: profile)

        XCTAssertEqual(plan.dueReviewTotal, 3)
        XCTAssertEqual(plan.reviewCount, 1, "复习上限 1 应该只取 1 个")
        XCTAssertEqual(plan.newCount, 2, "新字上限 2 应该只取 2 个")
        XCTAssertEqual(plan.items.count, 3)
    }

    func testPlanSkipsCharactersAlreadyLearned() throws {
        let context = try makeContext()
        let profile = Profile(name: "测试", level: .primary, emoji: "🦁", activeDeckName: "d")
        context.insert(profile)

        context.insert(SRSState(profileID: profile.id,
                                hanzi: "一",
                                schedule: Schedule(state: .review, ease: 2.5, intervalDays: 5, reps: 2,
                                                   due: Date().addingTimeInterval(86_400 * 5))))

        let states = try context.fetch(FetchDescriptor<SRSState>())
        let plan = TodayPlanner.plan(deckHanzi: ["一", "二", "三"], states: states, profile: profile)

        XCTAssertEqual(plan.newCount, 2)
        XCTAssertEqual(plan.items.map(\.hanzi), ["二", "三"])
        XCTAssertEqual(plan.reviewCount, 0, "未到期的字不该复习")
    }

    func testBonusRaisesTodaysLimit() {
        let profile = Profile(name: "测试", level: .preschool, emoji: "🐣")
        profile.newPerDay = 3
        XCTAssertEqual(profile.effectiveNewLimit(), 3)

        profile.addBonus(new: 2, review: 5)
        XCTAssertEqual(profile.effectiveNewLimit(), 5)
        XCTAssertEqual(profile.effectiveReviewLimit(), profile.reviewCap + 5)
        XCTAssertTrue(profile.hasBonusToday)
    }

    func testBonusExpiresNextDay() {
        let profile = Profile(name: "测试", level: .preschool, emoji: "🐣")
        profile.newPerDay = 3
        let yesterday = Date().addingTimeInterval(-86_400)
        profile.addBonus(new: 5, on: yesterday)

        XCTAssertEqual(profile.effectiveNewLimit(on: yesterday), 8)
        XCTAssertEqual(profile.effectiveNewLimit(), 3, "跨天后临时加量应失效")
    }

    func testNewCharactersFollowDeckOrder() throws {
        let context = try makeContext()
        let profile = Profile(name: "测试", level: .preschool, emoji: "🐣")
        profile.newPerDay = 3
        context.insert(profile)

        let plan = TodayPlanner.plan(deckHanzi: ["人", "口", "手", "大"], states: [], profile: profile)
        XCTAssertEqual(plan.items.map(\.hanzi), ["人", "口", "手"])
        XCTAssertTrue(plan.items.allSatisfy { $0.kind == .new })
    }

    func testReviewsComeBeforeNewCharacters() throws {
        let context = try makeContext()
        let profile = Profile(name: "测试", level: .primary, emoji: "🦁")
        profile.newPerDay = 5
        profile.reviewCap = 5
        context.insert(profile)

        context.insert(SRSState(profileID: profile.id,
                                hanzi: "一",
                                schedule: Schedule(state: .review, ease: 2.5, intervalDays: 1, reps: 1,
                                                   due: Date().addingTimeInterval(-60))))

        let states = try context.fetch(FetchDescriptor<SRSState>())
        let plan = TodayPlanner.plan(deckHanzi: ["二", "三"], states: states, profile: profile)
        XCTAssertEqual(plan.items.first?.hanzi, "一")
        XCTAssertEqual(plan.items.first?.kind, .review)
    }
}

// MARK: - 会话行为

@MainActor
final class StudySessionTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([Profile.self, CharacterCard.self, Deck.self, SRSState.self, ReviewLog.self])
        let container = try ModelContainer(for: schema,
                                           configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        return ModelContext(container)
    }

    func testAgainReinsertsCardLaterInSession() throws {
        let context = try makeContext()
        let profile = Profile(name: "测试", level: .preschool, emoji: "🐣")
        context.insert(profile)

        let items = ["一", "二", "三"].map { StudyItem(hanzi: $0, kind: .new, schedule: Schedule()) }
        let session = StudySession(items: items)

        session.grade(.again, profile: profile, context: context)

        XCTAssertEqual(session.index, 1)
        XCTAssertEqual(session.items.count, 4, "「不会」的字应该在本轮重现一次")
        XCTAssertEqual(session.items.last?.hanzi, "一")
    }

    func testGradeWritesStateAndLog() throws {
        let context = try makeContext()
        let profile = Profile(name: "测试", level: .preschool, emoji: "🐣")
        context.insert(profile)

        let session = StudySession(items: [StudyItem(hanzi: "水", kind: .new, schedule: Schedule())])
        session.grade(.good, profile: profile, context: context)

        let states = try context.fetch(FetchDescriptor<SRSState>())
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states.first?.hanzi, "水")
        XCTAssertEqual(states.first?.cardState, .review)
        XCTAssertEqual(states.first?.intervalDays, 1)

        let logs = try context.fetch(FetchDescriptor<ReviewLog>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.grade, .good)
        XCTAssertTrue(session.isFinished)
    }

    func testTwoProfilesDoNotShareProgress() throws {
        let context = try makeContext()
        let a = Profile(name: "A", level: .preschool, emoji: "🐣")
        let b = Profile(name: "B", level: .primary, emoji: "🦁")
        context.insert(a)
        context.insert(b)

        let session = StudySession(items: [StudyItem(hanzi: "水", kind: .new, schedule: Schedule())])
        session.grade(.good, profile: a, context: context)

        XCTAssertNotNil(SRSState.find(profileID: a.id, hanzi: "水", in: context))
        XCTAssertNil(SRSState.find(profileID: b.id, hanzi: "水", in: context))
    }
}
