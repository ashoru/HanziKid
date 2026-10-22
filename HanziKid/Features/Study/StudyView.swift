import SwiftUI

/// 一页一字（核心学习页）
struct StudyView: View {
    let profile: Profile
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    @StateObject private var session: StudySession
    @State private var boardToken = 0
    @State private var readTask: Task<Void, Never>?
    @State private var isReading = false
    /// 当前字已经写对了几遍（换一张卡就归零）
    @State private var writesDone = 0

    init(profile: Profile, items: [StudyItem]) {
        self.profile = profile
        _session = StateObject(wrappedValue: StudySession(items: items))
    }

    private func lookupCard(_ hanzi: String) -> CharacterCard? {
        store.card(for: hanzi)
    }

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                if session.isFinished {
                    finishedView
                } else if let item = session.current, lookupCard(item.hanzi) == nil {
                    // 字库还在加载（首次启动 / 导入新内容时）
                    ProgressView("正在准备字卡…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let item = session.current, let card = lookupCard(item.hanzi) {
                    GeometryReader { geo in
                        // 左：字形（米字格 + 笔顺）；右：字形信息 + 手写区（右下角）
                        // 横屏右栏宽一点，竖屏窄一点，结构一致
                        let isWide = geo.size.width > 1000
                        let rightWidth = min(isWide ? 440 : 330, geo.size.width * 0.46)
                        VStack(spacing: 0) {
                            HStack(alignment: .top, spacing: isWide ? 28 : 16) {
                                characterPanel(card: card)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                VStack(spacing: 12) {
                                    infoPanel(card: card)
                                    handwritingPanel(card: card)
                                }
                                .frame(width: rightWidth)
                                .frame(maxHeight: .infinity)
                            }
                            .frame(maxHeight: .infinity)

                            Spacer(minLength: 14)
                            gradeBar(item: item)
                        }
                        .padding(.horizontal, isWide ? 32 : 18)
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear { autoRead() }
        .onChange(of: session.index) { _ in
            writesDone = 0
            autoRead()
        }
        .onDisappear {
            readTask?.cancel()
            readTask = nil
            Pronunciation.stop()
        }
    }

    // MARK: 自动朗读（读 3 遍字 + 3 个组词，中间留跟读停顿）

    private var currentCard: CharacterCard? {
        guard let item = session.current else { return nil }
        return lookupCard(item.hanzi)
    }

    private func autoRead() {
        readTask?.cancel()
        Pronunciation.stop()
        guard profile.autoRead, let card = currentCard else {
            isReading = false
            return
        }
        let hanzi = card.hanzi
        let words = Array(card.words(for: profile.level).prefix(3))
        let repeatCount = max(1, min(5, profile.repeatCount))
        let pause = UInt64(max(0.2, profile.pauseSeconds) * 1_000_000_000)

        prefetchUpcoming()
        isReading = true
        readTask = Task { @MainActor in
            for _ in 0..<repeatCount {
                if Task.isCancelled { return }
                await Pronunciation.speakAndWait(hanzi, profile: profile)
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: pause)
            }
            for word in words {
                if Task.isCancelled { return }
                await Pronunciation.speakAndWait(word, profile: profile)
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: pause)
            }
            isReading = false
        }
    }

    /// 把当前字的组词、以及后面两张卡的音频提前下好（联网时才有意义，命中缓存就是空操作）
    private func prefetchUpcoming() {
        guard profile.onlineAudio, !AudioLibrary.shared.hasAudio else { return }
        var texts: [String] = []
        if let card = currentCard {
            texts.append(card.hanzi)
            texts.append(contentsOf: card.words(for: profile.level).prefix(3))
        }
        for item in session.items.dropFirst(session.index + 1).prefix(2) {
            texts.append(item.hanzi)
            if let card = lookupCard(item.hanzi) {
                texts.append(contentsOf: card.words(for: profile.level).prefix(3))
            }
        }
        AudioCache.shared.prefetch(texts)
    }

    // MARK: 右下方手写区

    @ViewBuilder
    private func handwritingPanel(card: CharacterCard) -> some View {
        HandwritingPad(hanzi: card.hanzi,
                       required: profile.writesPerChar,
                       done: writesDone,
                       isLocked: isReading,
                       showsGhost: profile.handwritingGhost) {
            writesDone += 1
        }
    }

    /// 手写要求满足了没有（0 遍 = 不要求）
    private var writesRequirementMet: Bool {
        writesDone >= profile.writesPerChar
    }

    // MARK: 顶部进度

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 44, height: 44)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.paperDeep)
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: max(8, geo.size.width * session.progress))
                            .animation(.easeInOut, value: session.progress)
                    }
                }
                .frame(height: 12)

                Text("还剩 \(session.remaining) 个")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                    .monospacedDigit()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
    }

    // MARK: 左侧：拼音 + 米字格

    private func characterPanel(card: CharacterCard) -> some View {
        VStack(spacing: 14) {
            Button {
                Pronunciation.speak(card.hanzi, profile: profile)
            } label: {
                HStack(spacing: 10) {
                    Text(card.pinyin.isEmpty ? "听读音" : card.pinyin)
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.accent.opacity(0.8))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Theme.accentSoft, in: Capsule())
            }
            .buttonStyle(.plain)

            HanziBoard(hanzi: card.hanzi, replayTrigger: boardToken)
                .frame(maxWidth: 520, maxHeight: .infinity)
                .onTapGesture {
                    Pronunciation.speak(card.hanzi, profile: profile)
                }

            HStack(spacing: 16) {
                smallAction(title: isReading ? "再读一遍" : "听一听",
                            icon: isReading ? "speaker.wave.3.fill" : "speaker.wave.2.fill") {
                    autoRead()
                }
                smallAction(title: "再看笔顺", icon: "arrow.counterclockwise") {
                    boardToken += 1
                }
            }
        }
    }

    private func smallAction(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(title)
                    .font(.system(size: 22, weight: .medium))
            }
            .foregroundStyle(Theme.inkSoft)
            .padding(.horizontal, 26)
            .padding(.vertical, 16)
            .background(Theme.card, in: Capsule())
            .shadow(color: Theme.shadow, radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: 右侧：字形信息 + 组词 + 意思

    @ViewBuilder
    private func infoPanel(card: CharacterCard, scrollable: Bool = true) -> some View {
        if scrollable {
            // 卡片铺满右栏（内容多时内部滚动），下方留给手写区
            ScrollView {
                infoContent(card: card, cardStyle: false)
                    .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .kidCard(padding: 0)
        } else {
            infoContent(card: card)
        }
    }

    private func infoContent(card: CharacterCard, cardStyle: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                chip("部首 \(card.radical)")
                chip("\(card.strokeCount) 画")
                if card.isPolyphonic, profile.level == .primary {
                    chip("多音字", tint: Theme.hard)
                }
            }

            sectionTitle("组词")
            FlowLayout(spacing: 10) {
                ForEach(card.words(for: profile.level), id: \.self) { word in
                    wordButton(word)
                }
            }

            if profile.level.showsMeaning, !card.meaning.isEmpty {
                sectionTitle("意思")
                Text(card.meaning)
                    .font(.system(size: profile.level == .preschool ? 26 : 24))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if card.needsContent {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                    Text("这个字是新录入的，释义和组词还没补全")
                }
                .font(.system(size: 15))
                .foregroundStyle(Theme.hard)
            }

            if profile.level == .primary, card.pinyinAll.count > 1 {
                sectionTitle("读音")
                Text(card.pinyinAll.joined(separator: " / "))
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .kidCard(padding: cardStyle ? 20 : 0)
    }

    private func wordButton(_ word: String) -> some View {
        Button {
            Pronunciation.speak(word, profile: profile)
        } label: {
            HStack(spacing: 6) {
                Text(word)
                    .font(HanziFont.font(size: 32))
                Image(systemName: "speaker.wave.1.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkFaint)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.paperDeep, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.inkFaint)
            .tracking(1)
    }

    private func chip(_ text: String, tint: Color = Theme.inkSoft) -> some View {
        Text(text)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.paperDeep, in: Capsule())
    }

    // MARK: 底部三档自评

    private func gradeBar(item: StudyItem) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                ForEach(ReviewGrade.allCases) { grade in
                    // "不会"永远能点；"会了 / 有点忘"要先把字写够遍数
                    let blocked = !writesRequirementMet && grade != .again
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            session.grade(grade, profile: profile, store: store)
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text("\(grade.emoji) \(grade.title)")
                                .font(.system(size: 22, weight: .semibold))
                            Text(blocked ? "先写对 \(profile.writesPerChar - writesDone) 遍" : previewHint(grade, for: item.schedule))
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.gradeColor(grade).opacity(blocked ? 0.45 : 1),
                                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(blocked)
                }
            }
        }
        .padding(.top, 8)
    }

    private func previewHint(_ grade: ReviewGrade, for schedule: Schedule) -> String {
        let next = Scheduler().next(schedule, grade: grade)
        return next.humanDescription()
    }

    // MARK: 完成页

    private var finishedView: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("🎉")
                .font(.system(size: 90))
            Text("今天的字都学完啦！")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("学了 \(session.newLearned) 个新字 · 记住 \(session.remembered) 个 · 还要加油 \(session.struggled) 个")
                .font(.system(size: 18))
                .foregroundStyle(Theme.inkSoft)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("完成")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 320)
                    .padding(.vertical, 16)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - 自动换行布局（组词芯片用）

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [CGFloat] = [0]
        var currentRowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width > maxWidth, currentRowWidth > 0 {
                totalHeight += rowHeight + spacing
                maxRowWidth = max(maxRowWidth, currentRowWidth - spacing)
                rows.append(0)
                currentRowWidth = 0
                rowHeight = 0
            }
            currentRowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        maxRowWidth = max(maxRowWidth, currentRowWidth - spacing)
        return CGSize(width: min(maxRowWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
