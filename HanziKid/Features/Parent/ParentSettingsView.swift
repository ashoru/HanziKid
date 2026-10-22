import SwiftUI

/// 家长设置：每日学习量、语速、字表、重置进度
struct ParentSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    private var profiles: [Profile] { store.profiles }
    private var decks: [Deck] { store.decks }

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
                                set: { newValue in store.updateProfile(profile.id) { $0.name = newValue } }
                            ))
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 180)
                        }

                        Picker("学段", selection: Binding(
                            get: { profile.level },
                            set: { newValue in
                                store.updateProfile(profile.id) {
                                    $0.level = newValue
                                    $0.speechRate = newValue.defaultSpeechRate
                                }
                            }
                        )) {
                            ForEach(LearnerLevel.allCases) { level in
                                Text(level.title).tag(level)
                            }
                        }

                        Stepper(value: Binding(
                            get: { profile.newPerDay },
                            set: { newValue in store.updateProfile(profile.id) { $0.newPerDay = newValue } }
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
                            set: { newValue in store.updateProfile(profile.id) { $0.reviewCap = newValue } }
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
                                set: { newValue in store.updateProfile(profile.id) { $0.speechRate = newValue } }
                            ), in: 0.25...0.6)
                        }

                        Toggle(isOn: Binding(
                            get: { profile.autoRead },
                            set: { newValue in store.updateProfile(profile.id) { $0.autoRead = newValue } }
                        )) {
                            Text("切到新字自动朗读")
                        }

                        Stepper(value: Binding(
                            get: { profile.repeatCount },
                            set: { newValue in store.updateProfile(profile.id) { $0.repeatCount = newValue } }
                        ), in: 1...5) {
                            HStack {
                                Text("每个字读几遍")
                                Spacer()
                                Text("\(profile.repeatCount) 遍")
                                    .foregroundStyle(Theme.accent)
                                    .monospacedDigit()
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("跟读停顿")
                                Spacer()
                                Text(String(format: "%.1f 秒", profile.pauseSeconds))
                                    .foregroundStyle(Theme.accent)
                                    .monospacedDigit()
                            }
                            Slider(value: Binding(
                                get: { profile.pauseSeconds },
                                set: { newValue in store.updateProfile(profile.id) { $0.pauseSeconds = newValue } }
                            ), in: 0.5...4.0, step: 0.1)
                            Text("每读一遍（以及每个组词之间）停这么久，留出孩子跟读的时间")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.inkFaint)
                        }

                        Picker("声音", selection: Binding(
                            get: { profile.voiceGender },
                            set: { newValue in store.updateProfile(profile.id) { $0.voiceGender = newValue } }
                        )) {
                            ForEach(SpeechGender.allCases) { gender in
                                Text("\(gender.title) · \(SpeechService.shared.voiceDescription(for: gender))")
                                    .tag(gender)
                            }
                        }

                        if !SpeechService.shared.hasVoice(for: .male) {
                            Text("这台设备还没有中文男声。可以在 设置 → 辅助功能 → 朗读内容 → 声音 → 中文 里下载一个男声，返回后这里会自动出现。")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.hard)
                        }

                        Picker("当前字表", selection: Binding(
                            get: { profile.activeDeckName },
                            set: { newValue in store.updateProfile(profile.id) { $0.activeDeckName = newValue } }
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
                    Button("完成") { store.saveNow(); dismiss() }
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

    private func reset(_ profile: Profile) {
        store.resetProgress(profileID: profile.id)
        store.saveNow()
    }
}
