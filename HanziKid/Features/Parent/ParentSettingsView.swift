import SwiftUI
import SwiftData

/// 家长设置：每日学习量、语速、字表、重置进度
struct ParentSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @Query(sort: \Deck.createdAt) private var decks: [Deck]

    @State private var resetTarget: Profile?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("每日学习量可以随时调整，改完立刻对下次「今日任务」生效。两个孩子各自独立设置。")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.inkSoft)
                }

                ForEach(profiles) { profile in
                    Section {
                        HStack {
                            Text("名字")
                            Spacer()
                            TextField("名字", text: Binding(
                                get: { profile.name },
                                set: { profile.name = $0; save() }
                            ))
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 180)
                        }

                        Picker("学段", selection: Binding(
                            get: { profile.level },
                            set: { newValue in
                                profile.level = newValue
                                profile.speechRate = newValue.defaultSpeechRate
                                save()
                            }
                        )) {
                            ForEach(LearnerLevel.allCases) { level in
                                Text(level.title).tag(level)
                            }
                        }

                        Stepper(value: Binding(
                            get: { profile.newPerDay },
                            set: { profile.newPerDay = $0; save() }
                        ), in: 0...30) {
                            HStack {
                                Text("每天新字")
                                Spacer()
                                Text("\(profile.newPerDay) 个")
                                    .foregroundStyle(Theme.accent)
                                    .monospacedDigit()
                            }
                        }

                        Stepper(value: Binding(
                            get: { profile.reviewCap },
                            set: { profile.reviewCap = $0; save() }
                        ), in: 0...60) {
                            HStack {
                                Text("每天复习上限")
                                Spacer()
                                Text("\(profile.reviewCap) 个")
                                    .foregroundStyle(Theme.good)
                                    .monospacedDigit()
                            }
                        }

                        VStack(alignment: .leading) {
                            Text("发音语速 \(profile.speechRate, specifier: "%.2f")")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.inkSoft)
                            Slider(value: Binding(
                                get: { profile.speechRate },
                                set: { profile.speechRate = $0; save() }
                            ), in: 0.25...0.6)
                        }

                        Picker("当前字表", selection: Binding(
                            get: { profile.activeDeckName },
                            set: { profile.activeDeckName = $0; save() }
                        )) {
                            ForEach(decks) { deck in
                                Text("\(deck.name)（\(deck.hanziList.count) 字）").tag(deck.name)
                            }
                        }

                        Button(role: .destructive) {
                            resetTarget = profile
                        } label: {
                            Text("清空 \(profile.name) 的学习进度")
                        }
                    } header: {
                        Text("\(profile.emoji) \(profile.name)")
                    } footer: {
                        Text("今天剩余：新字 \(profile.effectiveNewLimit()) 个 · 复习 \(profile.effectiveReviewLimit()) 个")
                            .font(.system(size: 12))
                    }
                }

                Section("关于") {
                    LabeledContent("字库规模", value: "800 字（可继续扩充）")
                    LabeledContent("笔顺数据", value: "Make Me a Hanzi")
                    LabeledContent("拼音 / 部首 / 释义", value: "开源字库（新华字典数据）")
                    LabeledContent("发音", value: "系统离线中文语音")
                    Text("内容来源均为开源数据，仅供家庭学习使用。组词与释义后续会接入更严谨的校对流程。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkFaint)
                }
            }
            .navigationTitle("家长设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { save(); dismiss() }
                }
            }
            .alert("确定清空进度？", isPresented: Binding(
                get: { resetTarget != nil },
                set: { if !$0 { resetTarget = nil } }
            )) {
                Button("取消", role: .cancel) { resetTarget = nil }
                Button("清空", role: .destructive) {
                    if let target = resetTarget { reset(target) }
                    resetTarget = nil
                }
            } message: {
                Text("会删除该孩子所有字的复习记录，字库和字表不受影响。")
            }
        }
    }

    private func save() {
        try? context.save()
    }

    private func reset(_ profile: Profile) {
        let pid = profile.id
        let predicate = #Predicate<SRSState> { $0.profileID == pid }
        if let states = try? context.fetch(FetchDescriptor<SRSState>(predicate: predicate)) {
            states.forEach { context.delete($0) }
        }
        let logPredicate = #Predicate<ReviewLog> { $0.profileID == pid }
        if let logs = try? context.fetch(FetchDescriptor<ReviewLog>(predicate: logPredicate)) {
            logs.forEach { context.delete($0) }
        }
        save()
    }
}
