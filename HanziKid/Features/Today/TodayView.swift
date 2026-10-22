import SwiftUI
import SwiftData

/// 今日任务（默认落地页）
struct TodayView: View {
    let profile: Profile
    var onSwitchProfile: () -> Void

    @Environment(\.modelContext) private var context
    @Query private var allStates: [SRSState]
    @Query private var allCards: [CharacterCard]
    @Query private var decks: [Deck]
    @Query private var logs: [ReviewLog]

    @State private var isStudying = false
    @State private var sessionItems: [StudyItem] = []
    @State private var showingSettings = false
    @State private var showingLibrary = false
    @State private var showingCapture = false

    private var myStates: [SRSState] { allStates.filter { $0.profileID == profile.id } }

    private var currentDeck: Deck? {
        decks.first { $0.name == profile.activeDeckName }
            ?? decks.first { $0.level == profile.level }
    }

    private var plan: TodayPlanner.Plan {
        TodayPlanner.plan(deckHanzi: currentDeck?.hanziList ?? [], states: myStates, profile: profile)
    }

    private var masteredCount: Int { myStates.filter { $0.cardState == .mastered }.count }
    private var learningCount: Int { myStates.filter { $0.cardState == .review || $0.cardState == .learning }.count }
    private var todayLogCount: Int {
        let calendar = Calendar.current
        return logs.filter { $0.profileID == profile.id && calendar.isDateInToday($0.reviewedAt) }.count
    }

    private var recentCards: [CharacterCard] {
        let byHanzi = Dictionary(allCards.map { ($0.hanzi, $0) }, uniquingKeysWith: { a, _ in a })
        let sorted = myStates
            .filter { $0.lastReviewedAt != nil }
            .sorted { ($0.lastReviewedAt ?? .distantPast) > ($1.lastReviewedAt ?? .distantPast) }
        return sorted.prefix(14).compactMap { byHanzi[$0.hanzi] }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    taskCard
                    statsRow
                    if !recentCards.isEmpty { recentSection }
                    footerNote
                }
                .padding(24)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingCapture = true
                    } label: {
                        Label("录新字", systemImage: "camera.viewfinder")
                    }
                    Button {
                        showingLibrary = true
                    } label: {
                        Label("字库", systemImage: "character.book.closed")
                    }
                    Button {
                        showingSettings = true
                    } label: {
                        Label("家长", systemImage: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingLibrary) {
                LibraryView(profile: profile)
            }
            .sheet(isPresented: $showingCapture) {
                CaptureView(profile: profile)
            }
            .sheet(isPresented: $showingSettings) {
                ParentSettingsView()
            }
            .fullScreenCover(isPresented: $isStudying) {
                StudyView(profile: profile, items: sessionItems)
            }
            .onAppear(perform: handleDemoArguments)
            .onChange(of: isStudying) { _, presenting in
                SpeechService.shared.configure()
                if !presenting { sessionItems = [] }
            }
        }
    }

    // MARK: DEBUG 截图辅助

    private func handleDemoArguments() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--demo") else { return }

        if let index = arguments.firstIndex(of: "--demo-char"), index + 1 < arguments.count {
            let hanzi = arguments[index + 1]
            sessionItems = [StudyItem(hanzi: hanzi, kind: .new, schedule: Schedule())]
            // 等 @Query 把字卡查出来再进学习页
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { isStudying = true }
            return
        }
        if arguments.contains("--demo-study"), !plan.items.isEmpty {
            sessionItems = plan.items
            isStudying = true
        }
        if arguments.contains("--demo-library") { showingLibrary = true }
        if arguments.contains("--demo-capture") || arguments.contains("--demo-capture-input") {
            showingCapture = true
        }
        if arguments.contains("--demo-settings") { showingSettings = true }
        #endif
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 16) {
            Text(profile.emoji)
                .font(.system(size: 40))
                .frame(width: 72, height: 72)
                .background(Theme.card, in: Circle())
                .shadow(color: Theme.shadow, radius: 8, y: 3)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(profile.name)，今天也来认字吧")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("\(profile.level.emoji) \(profile.level.title) · 已掌握 \(masteredCount) 个")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkSoft)
            }

            Spacer()

            Button {
                onSwitchProfile()
            } label: {
                Label("换人", systemImage: "person.2.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.card, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 今日任务

    private var taskCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("今天的任务")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.inkFaint)
                    .tracking(1)
                Spacer()
                if profile.hasBonusToday {
                    Text("已加练 \(profile.bonusNew + profile.bonusReview) 个")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.accentSoft, in: Capsule())
                }
            }

            HStack(spacing: 28) {
                numberBlock(value: plan.newCount, label: "个新字", tint: Theme.accent)
                numberBlock(value: plan.reviewCount, label: "个复习", tint: Theme.good)
                Spacer()
            }

            if plan.isEmpty {
                HStack(spacing: 12) {
                    Text(pendingHint)
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.inkSoft)
                    Spacer(minLength: 0)
                }
                Button {
                    showingCapture = true
                } label: {
                    Label("拍照 / 粘贴加新字", systemImage: "camera.viewfinder")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.accentSoft, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                Button {
                    sessionItems = plan.items
                    isStudying = true
                } label: {
                    Text(plan.isEmpty ? "没有要学的字" : "开始学习")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(plan.isEmpty ? Theme.inkFaint : Theme.accent,
                                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(plan.isEmpty)

                Button {
                    profile.addBonus(new: 3)
                    try? context.save()
                } label: {
                    VStack(spacing: 2) {
                        Text("＋3")
                            .font(.system(size: 20, weight: .bold))
                        Text("多学几个")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(Theme.accent)
                    .frame(width: 88)
                    .padding(.vertical, 12)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .kidCard(padding: 24)
    }

    private var pendingHint: String {
        if plan.pendingNewTotal == 0 && plan.dueReviewTotal == 0 {
            return "字表里的字都学过了，拍张照片或者去「字库」加几个新字吧。"
        }
        if plan.isEmpty {
            return "今天的任务已完成，可以休息啦。"
        }
        return ""
    }

    private func numberBlock(value: Int, label: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(value)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 16))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    // MARK: 统计

    private var statsRow: some View {
        HStack(spacing: 14) {
            statChip(title: "学习中", value: learningCount, icon: "book.fill", tint: Theme.accent)
            statChip(title: "已掌握", value: masteredCount, icon: "checkmark.seal.fill", tint: Theme.good)
            statChip(title: "今天练过", value: todayLogCount, icon: "flame.fill", tint: Theme.hard)
        }
    }

    private func statChip(title: String, value: Int, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: 最近学过的字

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近学过的字")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
                .tracking(1)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recentCards, id: \.hanzi) { card in
                        Button {
                            SpeechService.shared.speak(card.hanzi, rate: profile.speechRate)
                        } label: {
                            VStack(spacing: 4) {
                                Text(card.hanzi)
                                    .font(HanziFont.font(size: 34))
                                    .foregroundStyle(Theme.ink)
                                Text(card.pinyin)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.inkFaint)
                            }
                            .frame(width: 74, height: 88)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var footerNote: some View {
        Text("每学完一个字，孩子自己点「会了 / 有点忘 / 不会」，系统会按记忆曲线安排下次复习的时间。")
            .font(.system(size: 13))
            .foregroundStyle(Theme.inkFaint)
            .padding(.top, 4)
    }
}
