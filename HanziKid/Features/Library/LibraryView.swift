import SwiftUI

/// 字库：浏览内置 800 字，把要学的字加进当前字表
struct LibraryView: View {
    let profile: Profile
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    @State private var searchText = ""
    @State private var selection: Selection?
    @State private var onlyDeck = false
    @State private var showingCapture = false

    private enum SortMode: String, CaseIterable, Identifiable {
        case pinyin = "拼音"
        case strokes = "笔画"
        case deck = "字表顺序"
        var id: String { rawValue }
    }

    @State private var sortMode: SortMode = .pinyin

    private struct Selection: Identifiable {
        let id: String
        let card: CharacterCard
    }

    private var deck: Deck? {
        store.deck(named: profile.activeDeckName)
            ?? store.decks(for: profile.level).first
    }

    private var cards: [CharacterCard] { store.allCards }

    private var deckSet: Set<String> { Set(deck?.hanziList ?? []) }

    private var myStates: [String: SRSState] {
        Dictionary(store.states(for: profile.id).map { ($0.hanzi, $0) },
                   uniquingKeysWith: { a, _ in a })
    }

    private var filtered: [CharacterCard] {
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        var result = cards.filter { card in
            if onlyDeck, !deckSet.contains(card.hanzi) { return false }
            if keyword.isEmpty { return true }
            return card.hanzi.contains(keyword)
                || card.pinyin.lowercased().contains(keyword.lowercased())
                || card.words.contains { $0.contains(keyword) }
        }
        switch sortMode {
        case .pinyin:
            result.sort { $0.pinyin < $1.pinyin }
        case .strokes:
            result.sort { ($0.strokeCount, $0.pinyin) < ($1.strokeCount, $1.pinyin) }
        case .deck:
            let order = Dictionary(uniqueKeysWithValues: (deck?.hanziList ?? []).enumerated().map { ($1, $0) })
            result.sort { (order[$0.hanzi] ?? .max) < (order[$1.hanzi] ?? .max) }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Theme.inkFaint)
                        TextField("搜汉字、拼音或词", text: $searchText)
                            .textFieldStyle(.plain)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.card, in: Capsule())

                    Toggle(isOn: $onlyDeck) {
                        Text("只看字表")
                            .font(.system(size: 15))
                    }
                    .toggleStyle(.button)
                    .tint(Theme.accent)

                    Menu {
                        Picker("排序", selection: $sortMode) {
                            ForEach(SortMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                    } label: {
                        Label(sortMode.rawValue, systemImage: "arrow.up.arrow.down")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.inkSoft)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Theme.card, in: Capsule())
                    }
                }
                .padding(.horizontal, 20)

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 66), spacing: 10)], spacing: 10) {
                        ForEach(filtered) { card in
                            cell(card)
                        }
                    }
                    .padding(20)
                }
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("字库 · \(deck?.name ?? "未选择字表")（\(deckSet.count) 字）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingCapture = true
                    } label: {
                        Label("录新字", systemImage: "camera.viewfinder")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCapture) {
                CaptureView(profile: profile)
            }
            .sheet(item: $selection) { item in
                detailSheet(item.card)
            }
        }
    }

    private func cell(_ card: CharacterCard) -> some View {
        let inDeck = deckSet.contains(card.hanzi)
        let state = myStates[card.hanzi]
        return Button {
            selection = Selection(id: card.hanzi, card: card)
        } label: {
            ZStack(alignment: .topTrailing) {
                Text(card.hanzi)
                    .font(HanziFont.font(size: 32))
                    .foregroundStyle(inDeck ? Theme.ink : Theme.inkFaint)
                    .frame(width: 66, height: 66)
                    .background(inDeck ? Theme.card : Theme.paperDeep.opacity(0.5),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let state, state.cardState == .mastered {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.good)
                        .padding(4)
                } else if let state, state.cardState != .new {
                    Circle()
                        .fill(Theme.accent.opacity(0.7))
                        .frame(width: 7, height: 7)
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func detailSheet(_ card: CharacterCard) -> some View {
        let inDeck = deckSet.contains(card.hanzi)
        let state = myStates[card.hanzi]

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 20) {
                    HanziBoard(hanzi: card.hanzi)
                        .frame(width: 220, height: 220)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(card.pinyin)
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                        Text("部首 \(card.radical) · \(card.strokeCount) 画")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.inkSoft)
                        if let state {
                            Text(state.schedule.humanDescription())
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.inkFaint)
                        }
                        Button {
                            Pronunciation.speak(card.hanzi, profile: profile)
                        } label: {
                            Label("听发音", systemImage: "speaker.wave.2.fill")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.accent)
                    }
                    Spacer()
                }

                if !card.meaning.isEmpty {
                    Text(card.meaning)
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.inkSoft)
                }

                if !card.words.isEmpty {
                    Text("组词：" + card.words.joined(separator: "、"))
                        .font(HanziFont.font(size: 20))
                        .foregroundStyle(Theme.ink)
                }

                Button {
                    toggleDeck(card)
                } label: {
                    Text(inDeck ? "从「\(deck?.name ?? "字表")」移除" : "加入「\(deck?.name ?? "字表")」")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(inDeck ? Theme.again : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(inDeck ? Theme.paperDeep : Theme.accent,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
        .background(Theme.paper.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private func toggleDeck(_ card: CharacterCard) {
        guard let deck else { return }
        if deck.hanziList.contains(card.hanzi) {
            store.remove(card.hanzi, fromDeck: deck.name)
        } else {
            store.add([card.hanzi], toDeck: deck.name)
        }
        selection = Selection(id: card.hanzi, card: card)
    }
}
