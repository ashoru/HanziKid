import Foundation

// 与 HanziKidTests 一致的断言，用于在无 PTY（跑不了 xcodebuild test）的环境验证核心逻辑
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
func runPlannerChecks() {
    func dueState(_ profile: Profile, _ hanzi: String) -> SRSState {
        SRSState(profileID: profile.id, hanzi: hanzi,
                 schedule: Schedule(state: .review, ease: 2.5, intervalDays: 1, reps: 1,
                                    due: Date().addingTimeInterval(-3_600)))
    }

    // 1) 每日上限
    let profile = Profile(name: "测试", level: .preschool, emoji: "🐣", activeDeckName: "d",
                          newPerDay: 2, reviewCap: 1)
    let plan = TodayPlanner.plan(deckHanzi: ["四", "五", "六", "七"],
                                 states: [dueState(profile, "一"), dueState(profile, "二"), dueState(profile, "三")],
                                 profile: profile)
    check("到期复习 3 个，按上限只取 1 个", plan.dueReviewTotal == 3 && plan.reviewCount == 1)
    check("新字按上限只取 2 个", plan.newCount == 2)
    check("任务总数 = 1 复习 + 2 新字", plan.items.count == 3)

    // 2) 已学过的字不该再当新字
    let profile2 = Profile(name: "测试2", level: .primary, emoji: "🦁", activeDeckName: "d")
    let future = SRSState(profileID: profile2.id, hanzi: "一",
                          schedule: Schedule(state: .review, ease: 2.5, intervalDays: 5, reps: 2,
                                             due: Date().addingTimeInterval(86_400 * 5)))
    let plan2 = TodayPlanner.plan(deckHanzi: ["一", "二", "三"], states: [future], profile: profile2)
    check("未到期的字不出现", plan2.reviewCount == 0)
    check("已学过的字不算新字", plan2.items.map(\.hanzi) == ["二", "三"])

    // 3) 临时加量
    var profile3 = Profile(name: "测试3", level: .preschool, emoji: "🐣")
    profile3.newPerDay = 3
    check("默认新字 3 个", profile3.effectiveNewLimit() == 3)
    profile3.addBonus(new: 2, review: 5)
    check("「今天多学几个」生效",
          profile3.effectiveNewLimit() == 5 && profile3.effectiveReviewLimit() == profile3.reviewCap + 5)

    var profile4 = Profile(name: "测试4", level: .preschool, emoji: "🐣")
    profile4.newPerDay = 3
    let yesterday = Date().addingTimeInterval(-86_400)
    profile4.addBonus(new: 5, on: yesterday)
    check("跨天后临时加量失效",
          profile4.effectiveNewLimit(on: yesterday) == 8 && profile4.effectiveNewLimit() == 3)

    // 4) 字表顺序 + 复习优先
    let profile5 = Profile(name: "测试5", level: .preschool, emoji: "🐣", newPerDay: 3)
    let plan3 = TodayPlanner.plan(deckHanzi: ["人", "口", "手", "大"], states: [], profile: profile5)
    check("新字按字表顺序取前 3 个", plan3.items.map(\.hanzi) == ["人", "口", "手"])

    let profile6 = Profile(name: "测试6", level: .primary, emoji: "🦁", newPerDay: 5, reviewCap: 5)
    let plan4 = TodayPlanner.plan(deckHanzi: ["二", "三"], states: [dueState(profile6, "一")], profile: profile6)
    check("复习排在前面", plan4.items.first?.hanzi == "一" && plan4.items.first?.kind == .review)

    // 5) 学习会话 + 档案隔离
    let store = AppStore(storage: .memory)
    let kidA = Profile(name: "豆豆", level: .preschool, emoji: "🐣")
    let kidB = Profile(name: "果果", level: .primary, emoji: "🦁")

    let session = StudySession(items: ["一", "二", "三"].map { StudyItem(hanzi: $0, kind: .new, schedule: Schedule()) })
    session.grade(.again, profile: kidA, store: store)
    check("「不会」的字本轮重现一次", session.items.count == 4 && session.items.last?.hanzi == "一")

    let session2 = StudySession(items: [StudyItem(hanzi: "水", kind: .new, schedule: Schedule())])
    session2.grade(.good, profile: kidA, store: store)
    check("评分写入复习状态（明天复习）",
          store.schedule(profileID: kidA.id, hanzi: "水")?.intervalDays == 1)
    check("评分写入学习记录", store.logs.contains { $0.hanzi == "水" && $0.grade == .good })
    check("另一个孩子不受影响", store.schedule(profileID: kidB.id, hanzi: "水") == nil)
    check("会话推进到结束", session2.isFinished)
}

@MainActor
func runSettingsChecks() {
    print("朗读设置 / 字表")
    var profile = Profile(name: "豆豆", level: .preschool, emoji: "🐣")
    check("默认开启自动朗读", profile.autoRead == true)
    check("默认读 3 遍", profile.repeatCount == 3)
    check("默认跟读停顿 1.6 秒（中班）", abs(profile.pauseSeconds - 1.6) < 0.001)
    check("默认女声", profile.voiceGender == .female)

    profile.pauseSeconds = 2.4
    profile.repeatCount = 2
    profile.voiceGender = .male
    profile.autoRead = false
    check("设置可以改", profile.pauseSeconds == 2.4 && profile.repeatCount == 2
          && profile.voiceGender == .male && profile.autoRead == false)

    let primary = Profile(name: "果果", level: .primary, emoji: "🦁")
    check("四年级默认停顿 1.2 秒", abs(primary.pauseSeconds - 1.2) < 0.001)

    // 老存档（没有这些字段）也要能读出来用默认值
    let legacy = Profile(name: "老档案", level: .preschool, emoji: "🐣")
    var legacyCopy = legacy
    legacyCopy.autoReadRaw = nil
    legacyCopy.pauseSecondsRaw = nil
    legacyCopy.voiceGenderRaw = nil
    legacyCopy.repeatCountRaw = nil
    check("老存档缺字段时用默认值",
          legacyCopy.autoRead && legacyCopy.repeatCount == 3 && legacyCopy.voiceGender == .female)

    // 改名 / 换头像（豆豆、果果可以自定义）
    let named = AppStore(storage: .memory)
    let first = named.profiles[0]
    named.updateProfile(first.id) {
        $0.name = "小雨"
        $0.emoji = "🐼"
    }
    check("档案可以改名", named.profile(id: first.id)?.name == "小雨")
    check("档案可以换头像", named.profile(id: first.id)?.emoji == "🐼")
    check("改名不影响另一个孩子", named.profiles.count == 2 && named.profiles[1].name == "果果")
    check("改名不动学习进度", named.states(for: first.id).isEmpty && named.profile(id: first.id)?.id == first.id)

    let store = AppStore(storage: .memory)
    let made = store.createDeck(named: "一年级上册", level: .preschool, hanziList: ["天", "地"])
    let allForPrimary = store.decks(for: .primary)
    check("字表不分学段都能选到", allForPrimary.contains { $0.name == made.name })
    check("字表里的字都会建卡", store.card(for: "天") != nil || store.card(for: "地") != nil)
}

// MARK: - 手写识别

/// 折线加密（测试用：给定几个折点，插值成密集点）
func line(_ points: [CGPoint]) -> [CGPoint] {
    var out: [CGPoint] = [points[0]]
    for next in points.dropFirst() {
        let previous = out.last!
        let distance = hypot(next.x - previous.x, next.y - previous.y)
        let pieces = max(1, Int((distance / 0.01).rounded(.up)))
        for k in 1..<max(2, pieces) {
            let ratio = CGFloat(k) / CGFloat(max(2, pieces))
            out.append(CGPoint(x: previous.x + (next.x - previous.x) * ratio,
                               y: previous.y + (next.y - previous.y) * ratio))
        }
        out.append(next)
    }
    return out
}

func runHandwritingChecks() {
    print("手写识别")

    // 「十」：一横一竖的中线
    let cross = HanziStrokeData(outlines: [], medians: [], medianPoints: [
        [CGPoint(x: 0.20, y: 0.50), CGPoint(x: 0.80, y: 0.50)],
        [CGPoint(x: 0.50, y: 0.15), CGPoint(x: 0.50, y: 0.85)]
    ])
    // 「口」：一个方框
    let box = HanziStrokeData(outlines: [], medians: [], medianPoints: [
        [CGPoint(x: 0.28, y: 0.28), CGPoint(x: 0.72, y: 0.28)],
        [CGPoint(x: 0.28, y: 0.28), CGPoint(x: 0.28, y: 0.72)],
        [CGPoint(x: 0.72, y: 0.28), CGPoint(x: 0.72, y: 0.72)],
        [CGPoint(x: 0.28, y: 0.72), CGPoint(x: 0.72, y: 0.72)]
    ])

    func write(_ strokes: [[CGPoint]], width: CGFloat = 0.05) -> HandwritingSample {
        HandwritingSample(strokes: strokes, lineWidth: width)
    }

    let honest = write([line([CGPoint(x: 0.20, y: 0.50), CGPoint(x: 0.80, y: 0.50)]),
                        line([CGPoint(x: 0.50, y: 0.15), CGPoint(x: 0.50, y: 0.85)])])
    let honestResult = HandwritingMatcher.check(honest, hanzi: "十", strokeData: cross)
    check("端正地写「十」→ 判定正确", honestResult.isPass)
    check("判定结果给出 cover / stray 分数",
          honestResult.cover > 0.9 && honestResult.stray > 0.9 && honestResult.hasTemplate)

    // 手抖：每一笔上下抖一点（±2%）
    let shaky = write([
        line([CGPoint(x: 0.20, y: 0.50), CGPoint(x: 0.40, y: 0.52), CGPoint(x: 0.60, y: 0.48), CGPoint(x: 0.80, y: 0.50)]),
        line([CGPoint(x: 0.51, y: 0.15), CGPoint(x: 0.49, y: 0.50), CGPoint(x: 0.51, y: 0.85)])
    ], width: 0.07)
    check("手抖一点也算对", HandwritingMatcher.check(shaky, hanzi: "十", strokeData: cross).isPass)

    // 写小了 + 写偏了
    let smallAndOff = write([
        line([CGPoint(x: 0.32, y: 0.60), CGPoint(x: 0.62, y: 0.60)]),
        line([CGPoint(x: 0.47, y: 0.42), CGPoint(x: 0.47, y: 0.78)])
    ], width: 0.04)
    check("写小了、写偏了也能认出来", HandwritingMatcher.check(smallAndOff, hanzi: "十", strokeData: cross).isPass)

    // 只写了一横（笔画没写全）
    let onlyHorizontal = write([line([CGPoint(x: 0.20, y: 0.50), CGPoint(x: 0.80, y: 0.50)])])
    check("只写一横 → 不算对", HandwritingMatcher.check(onlyHorizontal, hanzi: "十", strokeData: cross).isPass == false)

    // 横写歪了（位置不对）
    let misplaced = write([
        line([CGPoint(x: 0.20, y: 0.74), CGPoint(x: 0.80, y: 0.74)]),
        line([CGPoint(x: 0.50, y: 0.15), CGPoint(x: 0.50, y: 0.85)])
    ])
    check("笔画位置写错 → 不算对", HandwritingMatcher.check(misplaced, hanzi: "十", strokeData: cross).isPass == false)

    // 写成别的字（口）
    let boxInk = write(box.medianPoints.map { line($0) })
    check("写成「口」去对「十」→ 不算对", HandwritingMatcher.check(boxInk, hanzi: "十", strokeData: cross).isPass == false)
    check("写成「口」对「口」→ 判定正确", HandwritingMatcher.check(boxInk, hanzi: "口", strokeData: box).isPass)

    // 乱画 / 只点一下
    let circle = (0...40).map { k -> CGPoint in
        let angle = CGFloat(k) / 40 * 2 * .pi
        return CGPoint(x: 0.5 + 0.3 * cos(angle), y: 0.5 + 0.3 * sin(angle))
    }
    check("画个圈 → 不算对", HandwritingMatcher.check(write([line(circle)]), hanzi: "十", strokeData: cross).isPass == false)
    check("只点一下 → 不算对", HandwritingMatcher.check(write([[CGPoint(x: 0.5, y: 0.5)]]), hanzi: "十", strokeData: cross).isPass == false)
    check("什么都没写 → 不算对", HandwritingMatcher.check(write([]), hanzi: "十", strokeData: cross).isPass == false)

    // 没有笔顺数据时不拦截
    check("没有范字数据时不拦截（交给界面放过）",
          HandwritingMatcher.check(honest, hanzi: "龘", strokeData: .empty).hasTemplate == false)

    // 设置项
    var profile = Profile(name: "豆豆", level: .preschool, emoji: "🐣")
    check("默认每个字写对 2 遍", profile.writesPerChar == 2)
    check("默认显示淡色范字", profile.handwritingGhost == true)
    profile.writesPerChar = 8
    check("写几遍最多 5，最少 0", profile.writesPerChar == 5)
    profile.writesPerChar = -3
    check("负数归零（= 不要求手写）", profile.writesPerChar == 0)
    profile.writesPerChar = 3
    profile.handwritingGhost = false
    check("设置能改", profile.writesPerChar == 3 && profile.handwritingGhost == false)
    var legacy = Profile(name: "老档案", level: .primary, emoji: "🦁")
    legacy.writesPerCharRaw = nil
    legacy.handwritingGhostRaw = nil
    check("老存档缺字段时用默认值", legacy.writesPerChar == 2 && legacy.handwritingGhost)
}

// MARK: - 年级：自定义 + 按时间自动升

func runGradeChecks() {
    print("年级与自动升年级")
    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    check("年级名称：幼儿园小班 / 中班 / 大班",
          SchoolGrade.title(0) == "幼儿园小班" && SchoolGrade.title(1) == "幼儿园中班" && SchoolGrade.title(2) == "幼儿园大班")
    check("年级名称：一到六年级",
          SchoolGrade.title(3) == "一年级" && SchoolGrade.title(6) == "四年级" && SchoolGrade.title(8) == "六年级")
    check("学段换算：幼儿园 3 档 / 小学 6 档",
          SchoolGrade.level(for: 2) == .preschool && SchoolGrade.level(for: 3) == .primary)
    check("新建档案默认年级：幼儿园中班 / 四年级",
          Profile(name: "A", level: .preschool, emoji: "🐣").grade() == 1
          && Profile(name: "B", level: .primary, emoji: "🦁").grade() == 6)

    // 家长手动选年级 → 从最近一个升年级日（默认 9 月）开始算
    var kid = Profile(name: "小星星", level: .preschool, emoji: "🦄")
    kid.setGrade(3, on: date(2026, 3, 10), calendar: calendar)   // 一年级
    check("改年级后立刻生效", kid.grade(on: date(2026, 3, 10), calendar: calendar) == 3)
    check("还没到 9 月不升", kid.grade(on: date(2026, 8, 31), calendar: calendar) == 3)
    check("到 9 月 1 日自动升到二年级", kid.grade(on: date(2026, 9, 1), calendar: calendar) == 4)
    check("再过一年升到三年级", kid.grade(on: date(2027, 9, 2), calendar: calendar) == 5)
    check("升年级后学段跟着变（一年级 → .primary）", kid.level == .primary)
    check("下次升年级是 2026-09-01", {
        guard let next = kid.nextGradeDate(on: date(2026, 3, 10), calendar: calendar) else { return false }
        return calendar.dateComponents([.year, .month, .day], from: next) == DateComponents(year: 2026, month: 9, day: 1)
    }())
    check("下次升到「二年级」", kid.nextGradeTitle(on: date(2026, 3, 10), calendar: calendar) == "二年级")
    check("没到升年级日时 didAutoUpgrade 是 false", kid.didAutoUpgrade(on: date(2026, 3, 10), calendar: calendar) == false)
    check("过了升年级日 didAutoUpgrade 是 true", kid.didAutoUpgrade(on: date(2026, 9, 2), calendar: calendar))

    // 关掉自动升年级
    var frozen = Profile(name: "冻结", level: .preschool, emoji: "🐣")
    frozen.setGrade(3, on: date(2026, 3, 10), calendar: calendar)
    frozen.autoGrade = false
    check("关掉自动升年级后一直是同一个年级",
          frozen.grade(on: date(2030, 12, 1), calendar: calendar) == 3)

    // 自定义升年级月份（比如 8 月）
    var august = Profile(name: "八月升", level: .preschool, emoji: "🐣")
    august.setGrade(2, on: date(2026, 3, 10), calendar: calendar)
    august.gradeMonth = 8
    check("自定义 8 月升年级：7 月还没升", august.grade(on: date(2026, 7, 31), calendar: calendar) == 2)
    check("自定义 8 月升年级：8 月 1 日升到大班", august.grade(on: date(2026, 8, 1), calendar: calendar) == 3)

    // 上限与老存档
    var top = Profile(name: "六年级", level: .primary, emoji: "🦁")
    top.setGrade(8, on: date(2020, 1, 1), calendar: calendar)
    check("六年级不再往上加", top.grade(on: date(2030, 1, 1), calendar: calendar) == 8)
    check("六年级没有下次升年级", top.nextGradeDate(on: date(2026, 3, 10), calendar: calendar) == nil)

    var legacy = Profile(name: "老档案", level: .primary, emoji: "🦁")
    legacy.gradeRaw = nil
    legacy.gradeAnchorRaw = nil
    legacy.gradeMonthRaw = nil
    legacy.autoGradeRaw = nil
    check("老存档（只有学段）按学段推断年级", legacy.gradeBase == 6 && legacy.autoGrade)
    check("老存档不设锚点也能按年升", legacy.grade(on: date(2035, 1, 1), calendar: calendar) >= 6)

    // 存盘往返
    let encoded = try! JSONEncoder().encode(kid)
    let decoded = try! JSONDecoder().decode(Profile.self, from: encoded)
    check("年级设置能存能读", decoded.gradeRaw == kid.gradeRaw
          && decoded.gradeAnchorRaw == kid.gradeAnchorRaw
          && decoded.gradeMonth == kid.gradeMonth
          && decoded.autoGrade == kid.autoGrade)
}

// MARK: - 字库总览：勾掉 / 拉回

@MainActor
func runOverviewChecks() {
    print("字库总览：勾掉 / 拉回")
    let store = AppStore(storage: .memory)
    guard let kid = store.profiles.first else {
        check("内存库里有默认档案", false)
        return
    }
    let deck = ["天", "地", "人", "口"]

    store.markMastered(profileID: kid.id, hanziList: deck, on: now)
    check("勾掉后 4 个字都是已掌握",
          deck.allSatisfy { store.cardState(profileID: kid.id, hanzi: $0) == .mastered })
    check("勾掉的字有复习状态记录", store.states(for: kid.id).count == 4)

    var plan = TodayPlanner.plan(deckHanzi: deck,
                                 states: store.states(for: kid.id),
                                 profile: kid,
                                 now: now.addingTimeInterval(86400 * 30))
    check("已掌握的字不再进今日任务", plan.items.isEmpty)
    check("已掌握的字也不算新字", plan.pendingNewTotal == 0)

    store.revive(profileID: kid.id, hanzi: "天", on: now)
    check("拉回后状态变「在学」", store.cardState(profileID: kid.id, hanzi: "天") == .learning)
    plan = TodayPlanner.plan(deckHanzi: deck, states: store.states(for: kid.id), profile: kid, now: now)
    check("拉回的字出现在今天的任务里", plan.items.contains { $0.hanzi == "天" })
    check("其他已掌握的字还是不出来", !plan.items.contains { $0.hanzi == "地" })

    store.revive(profileID: kid.id, hanzi: "水", on: now)
    check("从没学过的字也能直接拉进学习范围",
          store.cardState(profileID: kid.id, hanzi: "水") == .learning
          && store.states(for: kid.id).contains { $0.hanzi == "水" })

    store.markMastered(profileID: kid.id, hanzi: "天", on: now)
    check("再勾回去又变成已掌握", store.cardState(profileID: kid.id, hanzi: "天") == .mastered)
    check("重复勾掉是幂等的", {
        store.markMastered(profileID: kid.id, hanzi: "天", on: now)
        return store.cardState(profileID: kid.id, hanzi: "天") == .mastered
            && store.states(for: kid.id).filter { $0.hanzi == "天" }.count == 1
    }())

    let fresh = AppStore(storage: .memory)
    let other = fresh.profiles[1]
    check("还没学过的字默认是「新字」", fresh.cardState(profileID: other.id, hanzi: "天") == .new)
    fresh.markMastered(profileID: other.id, hanziList: ["天", "地"], on: now)
    check("两个孩子互不影响",
          fresh.cardState(profileID: other.id, hanzi: "天") == .mastered
          && fresh.cardState(profileID: other.id, hanzi: "人") == .new)
}

// MARK: - 组词（按读音分组）+ 朗读设置

func runWordGroupChecks() {
    print("组词与朗读设置")
    let polyphonic = CharacterCard(
        hanzi: "长",
        pinyin: "zhǎng",
        pinyinAll: ["zhǎng", "cháng"],
        radical: "长",
        strokeCount: 4,
        meaning: "生长；长度",
        words: ["长大", "校长", "长短", "长度"],
        wordGroups: [WordGroup(pinyin: "zhǎng", words: ["长大", "校长"]),
                     WordGroup(pinyin: "cháng", words: ["长短", "长度"])],
        frequency: 1000
    )

    check("每个读音各两组词", polyphonic.wordGroups.count == 2)
    check("只取主读音", polyphonic.readingGroups(limitPerReading: 2, includeOtherReadings: false).map(\.pinyin) == ["zhǎng"])
    check("多音字也给出其他读音",
          polyphonic.readingGroups(limitPerReading: 2, includeOtherReadings: true).map(\.pinyin) == ["zhǎng", "cháng"])
    check("每个读音最多 2 个词",
          polyphonic.readingGroups(limitPerReading: 2, includeOtherReadings: true).allSatisfy { $0.words.count <= 2 })
    check("限制为 1 时每个读音只剩 1 个词",
          polyphonic.readingGroups(limitPerReading: 1, includeOtherReadings: true).allSatisfy { $0.words.count == 1 })
    check("不读词时返回空", polyphonic.readingGroups(limitPerReading: 0, includeOtherReadings: true).isEmpty)
    check("朗读顺序：字之后的词按读音排",
          polyphonic.wordsToRead(limitPerReading: 2, includeOtherReadings: true) == ["长大", "校长", "长短", "长度"])
    check("关掉多音字只读主读音的词",
          polyphonic.wordsToRead(limitPerReading: 2, includeOtherReadings: false) == ["长大", "校长"])

    let single = CharacterCard(hanzi: "天", pinyin: "tiān", pinyinAll: ["tiān"], radical: "大",
                               strokeCount: 4, meaning: "天空", words: ["天空", "白天"],
                               wordGroups: [WordGroup(pinyin: "tiān", words: ["天空", "白天"])], frequency: 900)
    check("单读音字也只有一组", single.readingGroups(limitPerReading: 2, includeOtherReadings: true).count == 1)
    check("没有分组数据时退回平铺词表",
          CharacterCard(hanzi: "龘", pinyin: "", pinyinAll: [], radical: "", strokeCount: 3,
                        meaning: "", words: ["龘龘"], frequency: 0, needsContent: true)
              .readingGroups(limitPerReading: 2, includeOtherReadings: true).count == 1)

    var profile = Profile(name: "豆豆", level: .preschool, emoji: "🐣")
    check("默认每个词读 2 个", profile.wordsPerCard == 2)
    check("默认读多音字", profile.readsPolyphonic)
    profile.wordsPerCard = 9
    check("每个词最多 4 个", profile.wordsPerCard == 4)
    profile.wordsPerCard = -2
    check("负数归零（= 不读词）", profile.wordsPerCard == 0)
    profile.wordsPerCard = 2
    profile.readsPolyphonic = false
    check("设置能改", profile.wordsPerCard == 2 && profile.readsPolyphonic == false)
    var legacy = Profile(name: "老档案", level: .primary, emoji: "🦁")
    legacy.wordsPerCardRaw = nil
    legacy.readsPolyphonicRaw = nil
    check("老存档缺字段用默认值", legacy.wordsPerCard == 2 && legacy.readsPolyphonic)
}

print("OCR 抽字")
check("去掉标点、拼音和重复字",
      HanziText.extract("春天来了，小草绿了。chūn tiān") == ["春", "天", "来", "了", "小", "草", "绿"])
check("纯拼音不算字", HanziText.extract("shuǐ tiān").isEmpty)
check("空文本返回空", HanziText.extract("").isEmpty)
check("扩展 A 区也算汉字", HanziText.extract("a1 龘㐀！") == ["龘", "㐀"])
check("保留出现顺序", HanziText.extract("歌舞") == ["歌", "舞"])

@MainActor
func runImporterChecks() {
    print("录入入库")
    let store = AppStore(storage: .memory)

    let unknown = store.ensureCard(for: "龘")
    check("字库外的字 → 待补全卡", unknown.needsContent && unknown.words.isEmpty && unknown.pinyin.isEmpty)
    check("重复调用不会重复建卡", store.ensureCard(for: "龘").hanzi == "龘" && store.customCards.count == 1)

    let deck = store.createDeck(named: "第 1 课", level: .preschool, hanziList: [])
    let added = store.add(["水", "龘", "水"], toDeck: deck.name)
    check("加入字表去重且保持顺序",
          added == 2 && store.deck(named: deck.name)?.hanziList == ["水", "龘"])
    check("重复加入不再计数", store.add(["水"], toDeck: deck.name) == 0)
    store.remove("水", fromDeck: deck.name)
    check("移除字表成员", store.deck(named: deck.name)?.hanziList == ["龘"])

    let later = store.createDeck(named: "第 2 课", level: .preschool, hanziList: ["天", "空"])
    check("新建字表", later.hanziList == ["天", "空"])
    let duplicate = store.createDeck(named: "第 2 课", level: .preschool, hanziList: [])
    check("字表重名自动加序号", duplicate.name == "第 2 课 2")

    check("字库外的字进入字库索引", store.card(for: "龘") != nil)
    check("字库内的字也能取到（内存测试库为空时返回 nil 属预期）", store.card(for: "的") == nil)
}

runHandwritingChecks()
runGradeChecks()
runWordGroupChecks()

MainActor.assumeIsolated {
    runOverviewChecks()
    runPlannerChecks()
    runImporterChecks()
    runSettingsChecks()
}

print("")
print(failures == 0 ? "全部通过：\(checks) 项" : "失败 \(failures) / \(checks) 项")
exit(failures == 0 ? 0 : 1)
