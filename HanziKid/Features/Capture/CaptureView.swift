import SwiftUI
import SwiftData
import UIKit

/// 拍照 / 粘贴 → 识别汉字 → 勾选 → 加入字表
struct CaptureView: View {
    let profile: Profile

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var decks: [Deck]
    @Query private var allCards: [CharacterCard]

    private enum Stage {
        case input       // 选图 / 粘贴
        case reviewing   // 勾选确认
        case finished    // 完成
    }

    struct Candidate: Identifiable {
        let id: String          // 汉字
        var selected: Bool
        let known: Bool         // 字库里有内容
        let inDeck: Bool        // 已在目标字表
    }

    @State private var stage: Stage = .input
    @State private var pickedImage: UIImage?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var candidates: [Candidate] = []
    @State private var typedText = ""
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var targetDeckName = ""
    @State private var creatingDeck = false
    @State private var newDeckName = ""
    @State private var addedCount = 0
    @State private var addedDeckName = ""

    private var cardsByHanzi: [String: CharacterCard] {
        Dictionary(allCards.map { ($0.hanzi, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private var myDecks: [Deck] {
        let matched = decks.filter { $0.level == profile.level }
        return matched.isEmpty ? decks : matched
    }

    private var targetDeck: Deck? {
        myDecks.first { $0.name == targetDeckName } ?? myDecks.first
    }

    private var selectedHanzi: [String] {
        candidates.filter(\.selected).map(\.id)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.paper.ignoresSafeArea()
                switch stage {
                case .input: inputStage
                case .reviewing: reviewingStage
                case .finished: finishedStage
                }
                if isWorking { workingOverlay }
            }
            .navigationTitle("录新字")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if stage != .input {
                        Button("重来") { reset() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                ImagePicker(source: .camera) { image in handle(image) }
                    .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showLibrary) {
                ImagePicker(source: .photoLibrary) { image in handle(image) }
                    .ignoresSafeArea()
            }
            .task {
                if targetDeckName.isEmpty {
                    targetDeckName = profile.activeDeckName.isEmpty
                        ? (myDecks.first?.name ?? "")
                        : profile.activeDeckName
                }
                #if DEBUG
                let arguments = ProcessInfo.processInfo.arguments
                if let index = arguments.firstIndex(of: "--demo-text"), index + 1 < arguments.count {
                    prepare(hanzi: HanziText.extract(arguments[index + 1]))
                } else if arguments.contains("--demo-capture") {
                    await runOCR(on: SamplePage.render())
                }
                if arguments.contains("--demo-picker") {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    showLibrary = true
                }
                if arguments.contains("--demo-confirm"), stage == .reviewing {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    confirm()
                }
                #endif
            }
        }
    }

    // MARK: 第一步：选图 / 粘贴

    private var inputStage: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("拍一张孩子课本、作业本或者绘本的照片，我来自动挑出要学的字。")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)

                bigAction(title: "拍照识字",
                          subtitle: ImagePicker.isCameraAvailable ? "用 iPad 拍一页书" : "模拟器没有相机，用相册选图",
                          icon: "camera.fill",
                          tint: Theme.accent,
                          enabled: ImagePicker.isCameraAvailable) {
                    showCamera = true
                }

                bigAction(title: "从相册选一张",
                          subtitle: "相册里的照片或截图",
                          icon: "photo.on.rectangle",
                          tint: Theme.good,
                          enabled: true) {
                    showLibrary = true
                }

                HStack(spacing: 12) {
                    Rectangle().fill(Theme.inkFaint.opacity(0.3)).frame(height: 1)
                    Text("或者直接输入").font(.system(size: 13)).foregroundStyle(Theme.inkFaint)
                    Rectangle().fill(Theme.inkFaint.opacity(0.3)).frame(height: 1)
                }
                .padding(.vertical, 6)

                VStack(alignment: .leading, spacing: 10) {
                    Text("把要学的字粘贴在这里（标点、拼音会自动忽略）")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.inkFaint)
                    TextEditor(text: $typedText)
                        .font(.system(size: 24))
                        .frame(height: 120)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Theme.paperDeep, lineWidth: 1)
                        )

                    Button {
                        prepare(hanzi: HanziText.extract(typedText))
                    } label: {
                        Text("用这些字")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(iconDisabled ? Theme.inkFaint : Theme.accent,
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(iconDisabled)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.again)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    private var iconDisabled: Bool {
        HanziText.extract(typedText).isEmpty
    }

    private func bigAction(title: String,
                           subtitle: String,
                           icon: String,
                           tint: Color,
                           enabled: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(enabled ? tint : Theme.inkFaint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Theme.inkFaint)
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .opacity(enabled ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var workingOverlay: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("正在认字…")
                .font(.system(size: 16))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(30)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Theme.shadow, radius: 16, y: 6)
    }

    // MARK: 第二步：勾选确认

    private var reviewingStage: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if let pickedImage {
                    Image(uiImage: pickedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 74, height: 74)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("认出 \(candidates.count) 个不同的字")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("点一下取消不想学的字，默认只选字表里没有的")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.inkFaint)
                }
                Spacer()
                Button("全选") { setAll(true) }
                    .font(.system(size: 15))
                Button("清空") { setAll(false) }
                    .font(.system(size: 15))
            }
            .padding(20)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 12) {
                    ForEach(candidates) { candidate in
                        candidateCell(candidate)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            deckChooser
        }
    }

    private func candidateCell(_ candidate: Candidate) -> some View {
        Button {
            guard let index = candidates.firstIndex(where: { $0.id == candidate.id }) else { return }
            candidates[index].selected.toggle()
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 2) {
                    Text(candidate.id)
                        .font(HanziFont.font(size: 38))
                        .foregroundStyle(candidate.selected ? .white : Theme.inkSoft)
                    if !candidate.known {
                        Text("待补全")
                            .font(.system(size: 9))
                            .foregroundStyle(candidate.selected ? .white.opacity(0.8) : Theme.hard)
                    }
                }
                .frame(width: 84, height: 84)
                .background(candidate.selected ? Theme.accent : Theme.card,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(candidate.selected ? Color.clear : Theme.paperDeep, lineWidth: 1.5)
                )

                if candidate.inDeck {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.good)
                        .padding(5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var deckChooser: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text("加到")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.inkSoft)

                if creatingDeck {
                    TextField("新字表名字，例如 第 3 课", text: $newDeckName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.paperDeep, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Picker("字表", selection: $targetDeckName) {
                        ForEach(myDecks) { deck in
                            Text(deck.name).tag(deck.name)
                        }
                    }
                    .labelsHidden()
                    .tint(Theme.ink)
                    .lineLimit(1)
                    .frame(maxWidth: 320, alignment: .leading)
                }

                Button(creatingDeck ? "取消新建" : "新建") {
                    creatingDeck.toggle()
                    if creatingDeck { newDeckName = "" }
                }
                .font(.system(size: 15))
                .foregroundStyle(Theme.accent)
            }

            Button {
                confirm()
            } label: {
                Text(selectedHanzi.isEmpty ? "先选几个字" : "加入字表（\(selectedHanzi.count) 个）")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(selectedHanzi.isEmpty ? Theme.inkFaint : Theme.accent,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(selectedHanzi.isEmpty)
        }
        .padding(20)
        .background(Theme.card)
    }

    // MARK: 第三步：完成

    private var finishedStage: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("🎉").font(.system(size: 72))
            Text("加了 \(addedCount) 个字")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("在《\(addedDeckName)》里，去「今日任务」就能开始学")
                .font(.system(size: 16))
                .foregroundStyle(Theme.inkSoft)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("好了")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 320)
                    .padding(.vertical, 15)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 40)
        }
    }

    // MARK: 逻辑

    private func handle(_ image: UIImage) {
        pickedImage = image
        Task { await runOCR(on: image) }
    }

    @MainActor
    private func runOCR(on image: UIImage) async {
        isWorking = true
        errorMessage = nil
        do {
            let outcome = try await OCRService.recognize(in: image)
            prepare(hanzi: outcome.hanzi)
        } catch {
            errorMessage = error.localizedDescription
            stage = .input
        }
        isWorking = false
    }

    private func prepare(hanzi: [String]) {
        guard !hanzi.isEmpty else {
            errorMessage = "没有找到汉字，换个地方试试"
            return
        }
        let deckSet = Set(targetDeck?.hanziList ?? [])
        let cards = cardsByHanzi
        candidates = hanzi.map { character in
            Candidate(id: character,
                      selected: !deckSet.contains(character),
                      known: cards[character]?.needsContent == false,
                      inDeck: deckSet.contains(character))
        }
        errorMessage = nil
        stage = .reviewing
    }

    private func setAll(_ selected: Bool) {
        for index in candidates.indices {
            candidates[index].selected = selected
        }
    }

    private func confirm() {
        let chosen = selectedHanzi
        guard !chosen.isEmpty else { return }
        let cards = cardsByHanzi

        if creatingDeck {
            let name = newDeckName.isEmpty
                ? "新字表 · \(Profile.dayKey(for: Date()))"
                : newDeckName
            let deck = CardImporter.createDeck(named: name,
                                               level: profile.level,
                                               hanziList: chosen,
                                               existing: cards,
                                               context: context)
            profile.activeDeckName = deck.name
            addedDeckName = deck.name
            addedCount = chosen.count
        } else if let deck = targetDeck {
            addedCount = CardImporter.add(chosen, to: deck, existing: cards, context: context)
            addedDeckName = deck.name
        } else {
            let name = "我的字表"
            let deck = CardImporter.createDeck(named: name,
                                               level: profile.level,
                                               hanziList: chosen,
                                               existing: cards,
                                               context: context)
            profile.activeDeckName = deck.name
            addedDeckName = name
            addedCount = chosen.count
        }
        try? context.save()
        stage = .finished
    }

    private func reset() {
        stage = .input
        candidates = []
        pickedImage = nil
        typedText = ""
        errorMessage = nil
        addedCount = 0
    }
}

#if DEBUG
/// 截图 / 冒烟测试用的样张（模拟一页课文）
enum SamplePage {
    static func render() -> UIImage {
        let size = CGSize(width: 1240, height: 900)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 96),
                .foregroundColor: UIColor.black,
            ]
            let lines = ["春天来了，小草绿了。", "小朋友们唱歌跳舞。"]
            for (index, line) in lines.enumerated() {
                (line as NSString).draw(at: CGPoint(x: 90, y: 140 + CGFloat(index) * 200),
                                        withAttributes: attributes)
            }
        }
    }
}
#endif
