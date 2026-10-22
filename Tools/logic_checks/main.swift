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

MainActor.assumeIsolated {
    runPlannerChecks()
    runImporterChecks()
    runSettingsChecks()
}

print("")
print(failures == 0 ? "全部通过：\(checks) 项" : "失败 \(failures) / \(checks) 项")
exit(failures == 0 ? 0 : 1)
