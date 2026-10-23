import SwiftUI

/// 字库总览：一眼看到每个字现在到哪一步，直接勾掉"完全会了"的字、把忘掉的字拉回来
struct ProgressOverviewView: View {
    let profile: Profile

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    @State private var scope: Scope = .deck
    @State private var filter: Filter = .all
    @State private var searchText = ""
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var bulkAction: BulkAction?
    @State private var showingBulkConfirm = false

    private enum Scope: String, CaseIterable, Identifiable {
        case deck = "当前字表"
        case library = "全部字库"
        var id: String { rawValue }
    }

    private enum Filter: String, CaseIterable, Identifiable {
        case all = "全部"
        case fresh = "还没学"
        case learning = "在学"
        case mastered = "已掌握"
        var id: String { rawValue }
    }

    private enum BulkAction: String, Identifiable {
        case master = "标为已掌握"
        case revive = "拉回学习"
        var id: String { rawValue }
    }

    // MARK: 数据

    private var deck: Deck? {
        store.deck(named: profile.activeDeckName)
            ?? store.decks(for: profile.level).first
    }

    /// 这个孩子在每个字上的状态（没有记录 = 还没学）
    private var states: [String: CardState] {
        Dictionary(store.states(for: profile.id).map { ($0.hanzi, $0.cardState) },
                   uniquingKeysWith: { a, _ in a })
    }

    private func state(of hanzi: String) -> CardState {
        states[hanzi] ?? .new
    }

    /// 可选的字（按范围）
    private var scopedHanzi: [String] {
        switch scope {
        case .deck:
            return deck?.hanziList ?? []
        case .library:
            return store.allCards.map(\.hanzi)
        }
    }

    private var counts: (total: Int, fresh: Int, learning: Int, mastered: Int) {
        var total = 0, fresh = 0, learning = 0, mastered = 0
        for hanzi in scopedHanzi {
            total += 1
            switch state(of: hanzi) {
            case .new: fresh += 1
            case .mastered, .suspended: mastered += 1
            case .learning, .review: learning += 1
            }
        }
        return (total, fresh, learning, mastered)
    }

    private var filtered: [String] {
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        let order = Dictionary(uniqueKeysWithValues: scopedHanzi.enumerated().map { ($1, $0) })
        return scopedHanzi.filter { hanzi in
            switch filter {
            case .all: break
            case .fresh: if state(of: hanzi) != .new { return false }
            case .learning:
                let cardState = state(of: hanzi)
                if cardState != .learning && cardState != .review { return false }
            case .mastered:
                let cardState = state(of: hanzi)
                if cardState != .mastered && cardState != .suspended { return false }
            }
            guard !keyword.isEmpty else { return true }
            let card = store.card(for: hanzi)
            return hanzi.contains(keyword)
                || (card?.pinyin.lowercased().contains(keyword.lowercased()) ?? false)
                || (card?.words.contains { $0.contains(keyword) } ?? false)
        }
        .sorted { (order[$0] ?? .max) < (order[$1] ?? .max) }
    }

    private func count(of filter: Filter) -> Int {
        switch filter {
        case .all: return counts.total
        case .fresh: return counts.fresh
        case .learning: return counts.learning
        case .mastered: return counts.mastered
        }
    }

    // MARK: 界面

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                summary
                scopePicker
                filterBar
                searchBar

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 10)], spacing: 10) {
                        ForEach(filtered, id: \.self) { hanzi in
                            cell(hanzi)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 90)
                }
                .overlay(alignment: .bottom) {
                    if let toast {
                        Text(toast)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 11)
                            .background(Theme.ink.opacity(0.88), in: Capsule())
                            .padding(.bottom, 18)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("字库总览 · \(deck?.name ?? "未选字表")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            bulkAction = .master
                            showingBulkConfirm = true
                        } label: {
                            Label("把当前筛选的 \(filtered.count) 个字标为已掌握", systemImage: "checkmark.circle")
                        }
                        Button {
                            bulkAction = .revive
                            showingBulkConfirm = true
                        } label: {
                            Label("把当前筛选的 \(filtered.count) 个字拉回学习", systemImage: "arrow.uturn.backward.circle")
                        }
                    } label: {
                        Label("批量", systemImage: "ellipsis.circle")
                    }
                    .disabled(filtered.isEmpty)
                }
            }
            .confirmationDialog(bulkTitle, isPresented: $showingBulkConfirm, titleVisibility: .visible) {
                Button(bulkAction == .revive ? "拉回学习" : "标为已掌握") { runBulk() }
                Button("取消", role: .cancel) {}
            } message: {
                Text(bulkMessage)
            }
        }
    }

    private var bulkTitle: String {
        switch bulkAction {
        case .master: return "把这 \(filtered.count) 个字标为已掌握？"
        case .revive, .none: return "把这 \(filtered.count) 个字拉回学习？"
        }
    }

    private var bulkMessage: String {
        switch bulkAction {
        case .master:
            return "标为已掌握后，这些字不会再出现在今日任务里（之后可以在「已掌握」里拉回来）。"
        case .revive, .none:
            return "拉回后今天就会出现在复习任务里，按记忆曲线重新安排。"
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            statChip("共 \(counts.total)", tint: Theme.inkSoft)
            statChip("还没学 \(counts.fresh)", tint: Theme.inkFaint)
            statChip("在学 \(counts.learning)", tint: Theme.accent)
            statChip("已掌握 \(counts.mastered)", tint: Theme.good)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var scopePicker: some View {
        Picker("范围", selection: $scope) {
            ForEach(Scope.allCases) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases) { item in
                    Button {
                        filter = item
                    } label: {
                        Text("\(item.rawValue) \(count(of: item))")
                            .font(.system(size: 15, weight: filter == item ? .semibold : .regular))
                            .foregroundStyle(filter == item ? .white : Theme.inkSoft)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(filter == item ? Theme.accent : Theme.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.inkFaint)
            TextField("搜汉字、拼音或词", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.inkFaint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.card, in: Capsule())
        .padding(.horizontal, 20)
    }

    private func cell(_ hanzi: String) -> some View {
        let cardState = state(of: hanzi)
        let mastered = cardState == .mastered || cardState == .suspended
        let learning = cardState == .learning || cardState == .review

        return Button {
            toggle(hanzi, currentlyMastered: mastered)
        } label: {
            VStack(spacing: 3) {
                Text(hanzi)
                    .font(HanziFont.font(size: 30))
                    .foregroundStyle(mastered ? Theme.good : (learning ? Theme.ink : Theme.inkFaint))
                    .frame(height: 40)

                HStack(spacing: 3) {
                    if mastered {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.good)
                    } else if learning {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 6, height: 6)
                    }
                    Text(statusText(cardState))
                        .font(.system(size: 10))
                        .foregroundStyle(mastered ? Theme.good : Theme.inkFaint)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(mastered ? Theme.good.opacity(0.10) : Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(mastered ? Theme.good.opacity(0.55) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func statusText(_ state: CardState) -> String {
        switch state {
        case .new: return "还没学"
        case .learning: return "在学"
        case .review: return "复习中"
        case .mastered: return "已掌握"
        case .suspended: return "已暂停"
        }
    }

    private func statChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.card, in: Capsule())
            .monospacedDigit()
    }

    // MARK: 操作

    private func toggle(_ hanzi: String, currentlyMastered: Bool) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if currentlyMastered {
            store.revive(profileID: profile.id, hanzi: hanzi)
            store.saveNow()
            showToast("「\(hanzi)」已拉回学习，今天就会复习")
        } else {
            store.markMastered(profileID: profile.id, hanzi: hanzi)
            store.saveNow()
            showToast("「\(hanzi)」已标为掌握，不再出现在今日任务")
        }
    }

    private func runBulk() {
        let targets = filtered
        guard !targets.isEmpty else { return }
        switch bulkAction {
        case .master:
            store.markMastered(profileID: profile.id, hanziList: targets)
            store.saveNow()
            showToast("已把 \(targets.count) 个字标为掌握")
        case .revive, .none:
            store.revive(profileID: profile.id, hanziList: targets)
            store.saveNow()
            showToast("已把 \(targets.count) 个字拉回学习")
        }
        bulkAction = nil
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { toast = text }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { toast = nil }
        }
    }
}
