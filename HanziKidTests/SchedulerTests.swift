import XCTest
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
        XCTAssertEqual(scheduler().next(start, grade: .good, now: now).intervalDays, 3)
    }

    func testThirdGoodMultipliesByEase() {
        let start = Schedule(state: .review, ease: 2.6, intervalDays: 3, reps: 2)
        let result = scheduler().next(start, grade: .good, now: now)
        XCTAssertEqual(result.intervalDays, 8)          // 3 × 2.7 = 8.1 → 8
        XCTAssertEqual(result.ease, 2.7, accuracy: 0.0001)
    }

    func testEaseStopsAtMaximum() {
        let start = Schedule(state: .review, ease: 2.8, intervalDays: 5, reps: 3)
        XCTAssertEqual(scheduler().next(start, grade: .good, now: now).ease, 2.8, accuracy: 0.0001)
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
        XCTAssertEqual(scheduler().next(start, grade: .again, now: now).ease, 1.3, accuracy: 0.0001)
    }

    func testHardGrowsIntervalSlowly() {
        let start = Schedule(state: .review, ease: 2.5, intervalDays: 10, reps: 3)
        let result = scheduler().next(start, grade: .hard, now: now)
        XCTAssertEqual(result.intervalDays, 12)
        XCTAssertEqual(result.ease, 2.35, accuracy: 0.0001)
    }

    func testIntervalNeverExceedsSixtyDays() {
        let start = Schedule(state: .review, ease: 2.8, intervalDays: 55, reps: 6)
        XCTAssertEqual(scheduler().next(start, grade: .good, now: now).intervalDays, 60)
    }

    func testGraduatesToMastered() {
        let start = Schedule(state: .review, ease: 2.5, intervalDays: 21, reps: 3)
        let result = scheduler().next(start, grade: .good, now: now)
        XCTAssertEqual(result.state, .mastered)
        XCTAssertFalse(result.isDue(on: now.addingTimeInterval(86_400 * 365)))
    }

    func testLeechDetectedAfterRepeatedFailures() {
        var current = Schedule()
        for _ in 0..<4 {
            current = scheduler().next(current, grade: .again, now: now)
        }
        XCTAssertEqual(current.lapses, 4)
        XCTAssertTrue(current.isLeech)
    }

    func testNewAndMasteredCardsAreNotDue() {
        XCTAssertFalse(Schedule().isDue(on: now))
        let mastered = Schedule(state: .mastered, intervalDays: 30, due: now.addingTimeInterval(-86_400))
        XCTAssertFalse(mastered.isDue(on: now))
    }
}

// MARK: - 今日任务排程

@MainActor
final class TodayPlannerTests: XCTestCase {
    private func dueState(_ profile: Profile, _ hanzi: String) -> SRSState {
        SRSState(profileID: profile.id, hanzi: hanzi,
                 schedule: Schedule(state: .review, ease: 2.5, intervalDays: 1, reps: 1,
                                    due: Date().addingTimeInterval(-3_600)))
    }

    func testPlanRespectsDailyLimits() {
        let profile = Profile(name: "测试", level: .preschool, emoji: "🐣", newPerDay: 2, reviewCap: 1)
        let plan = TodayPlanner.plan(deckHanzi: ["四", "五", "六", "七"],
                                     states: [dueState(profile, "一"),
                                              dueState(profile, "二"),
                                              dueState(profile, "三")],
                                     profile: profile)
        XCTAssertEqual(plan.dueReviewTotal, 3)
        XCTAssertEqual(plan.reviewCount, 1)
        XCTAssertEqual(plan.newCount, 2)
        XCTAssertEqual(plan.items.count, 3)
    }

    func testPlanSkipsCharactersAlreadyLearned() {
        let profile = Profile(name: "测试", level: .primary, emoji: "🦁")
        let future = SRSState(profileID: profile.id, hanzi: "一",
                              schedule: Schedule(state: .review, ease: 2.5, intervalDays: 5, reps: 2,
                                                 due: Date().addingTimeInterval(86_400 * 5)))
        let plan = TodayPlanner.plan(deckHanzi: ["一", "二", "三"], states: [future], profile: profile)
        XCTAssertEqual(plan.reviewCount, 0)
        XCTAssertEqual(plan.items.map(\.hanzi), ["二", "三"])
    }

    func testBonusRaisesTodaysLimit() {
        var profile = Profile(name: "测试", level: .preschool, emoji: "🐣")
        profile.newPerDay = 3
        XCTAssertEqual(profile.effectiveNewLimit(), 3)
        profile.addBonus(new: 2, review: 5)
        XCTAssertEqual(profile.effectiveNewLimit(), 5)
        XCTAssertEqual(profile.effectiveReviewLimit(), profile.reviewCap + 5)
        XCTAssertTrue(profile.hasBonusToday)
    }

    func testBonusExpiresNextDay() {
        var profile = Profile(name: "测试", level: .preschool, emoji: "🐣")
        profile.newPerDay = 3
        let yesterday = Date().addingTimeInterval(-86_400)
        profile.addBonus(new: 5, on: yesterday)
        XCTAssertEqual(profile.effectiveNewLimit(on: yesterday), 8)
        XCTAssertEqual(profile.effectiveNewLimit(), 3)
    }

    func testNewCharactersFollowDeckOrder() {
        let profile = Profile(name: "测试", level: .preschool, emoji: "🐣", newPerDay: 3)
        let plan = TodayPlanner.plan(deckHanzi: ["人", "口", "手", "大"], states: [], profile: profile)
        XCTAssertEqual(plan.items.map(\.hanzi), ["人", "口", "手"])
        XCTAssertTrue(plan.items.allSatisfy { $0.kind == .new })
    }

    func testReviewsComeBeforeNewCharacters() {
        let profile = Profile(name: "测试", level: .primary, emoji: "🦁", newPerDay: 5, reviewCap: 5)
        let plan = TodayPlanner.plan(deckHanzi: ["二", "三"], states: [dueState(profile, "一")], profile: profile)
        XCTAssertEqual(plan.items.first?.hanzi, "一")
        XCTAssertEqual(plan.items.first?.kind, .review)
    }
}

// MARK: - 学习会话

@MainActor
final class StudySessionTests: XCTestCase {
    func testAgainReinsertsCardLaterInSession() {
        let store = AppStore(storage: .memory)
        let profile = Profile(name: "测试", level: .preschool, emoji: "🐣")
        let session = StudySession(items: ["一", "二", "三"].map {
            StudyItem(hanzi: $0, kind: .new, schedule: Schedule())
        })

        session.grade(.again, profile: profile, store: store)

        XCTAssertEqual(session.index, 1)
        XCTAssertEqual(session.items.count, 4)
        XCTAssertEqual(session.items.last?.hanzi, "一")
    }

    func testGradeWritesStateAndLog() {
        let store = AppStore(storage: .memory)
        let profile = Profile(name: "测试", level: .preschool, emoji: "🐣")
        let session = StudySession(items: [StudyItem(hanzi: "水", kind: .new, schedule: Schedule())])

        session.grade(.good, profile: profile, store: store)

        XCTAssertEqual(store.schedule(profileID: profile.id, hanzi: "水")?.intervalDays, 1)
        XCTAssertEqual(store.logs.count, 1)
        XCTAssertEqual(store.logs.first?.grade, .good)
        XCTAssertTrue(session.isFinished)
    }

    func testTwoProfilesDoNotShareProgress() {
        let store = AppStore(storage: .memory)
        let a = Profile(name: "A", level: .preschool, emoji: "🐣")
        let b = Profile(name: "B", level: .primary, emoji: "🦁")

        StudySession(items: [StudyItem(hanzi: "水", kind: .new, schedule: Schedule())])
            .grade(.good, profile: a, store: store)

        XCTAssertNotNil(store.schedule(profileID: a.id, hanzi: "水"))
        XCTAssertNil(store.schedule(profileID: b.id, hanzi: "水"))
    }
}

// MARK: - 拍照录入入库

@MainActor
final class CardImporterTests: XCTestCase {
    func testUnknownCharacterBecomesPendingCard() {
        let store = AppStore(storage: .memory)
        let card = store.ensureCard(for: "龘")
        XCTAssertTrue(card.needsContent)
        XCTAssertTrue(card.pinyin.isEmpty)
        XCTAssertEqual(store.customCards.count, 1)

        _ = store.ensureCard(for: "龘")
        XCTAssertEqual(store.customCards.count, 1)
    }

    func testAddToDeckDeduplicates() {
        let store = AppStore(storage: .memory)
        let deck = store.createDeck(named: "第 1 课", level: .preschool, hanziList: [])

        XCTAssertEqual(store.add(["水", "龘", "水"], toDeck: deck.name), 2)
        XCTAssertEqual(store.deck(named: deck.name)?.hanziList, ["水", "龘"])
        XCTAssertEqual(store.add(["水"], toDeck: deck.name), 0)

        store.remove("水", fromDeck: deck.name)
        XCTAssertEqual(store.deck(named: deck.name)?.hanziList, ["龘"])
    }

    func testDeckNamesStayUnique() {
        let store = AppStore(storage: .memory)
        _ = store.createDeck(named: "第 2 课", level: .preschool, hanziList: ["天"])
        let second = store.createDeck(named: "第 2 课", level: .preschool, hanziList: [])
        XCTAssertEqual(second.name, "第 2 课 2")
    }
}

// MARK: - 抽字

final class HanziTextTests: XCTestCase {
    func testExtractSkipsPunctuationAndPinyin() {
        XCTAssertEqual(HanziText.extract("春天来了，小草绿了。chūn tiān"),
                       ["春", "天", "来", "了", "小", "草", "绿"])
        XCTAssertTrue(HanziText.extract("shuǐ tiān").isEmpty)
        XCTAssertTrue(HanziText.extract("").isEmpty)
    }

    func testExtractSupportsExtensionA() {
        XCTAssertEqual(HanziText.extract("a1 龘㐀！"), ["龘", "㐀"])
    }
}
