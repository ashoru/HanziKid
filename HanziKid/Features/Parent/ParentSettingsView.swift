import SwiftUI

/// 家长设置：每日学习量、语速、字表、重置进度
struct ParentSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    private var profiles: [Profile] { store.profiles }
    private var decks: [Deck] { store.decks }

    @State private var resetTarget: Profile?
    /// 正在编辑名字 / 头像的档案
    @State private var editingProfile: Profile?

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
                        Button {
                            editingProfile = profile
                        } label: {
                            HStack {
                                Text("名字与头像")
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Text("\(profile.emoji) \(profile.name)")
                                    .foregroundStyle(Theme.accent)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.inkFaint)
                            }
                        }

                        Picker("年级", selection: Binding(
                            get: { profile.grade() },
                            set: { newValue in
                                store.updateProfile(profile.id) { $0.setGrade(newValue) }
                            }
                        )) {
                            ForEach(SchoolGrade.all, id: \.self) { index in
                                Text(SchoolGrade.title(index)).tag(index)
                            }
                        }

                        Toggle(isOn: Binding(
                            get: { profile.autoGrade },
                            set: { newValue in store.updateProfile(profile.id) { $0.autoGrade = newValue } }
                        )) {
                            Text("到时间自动升年级")
                        }

                        if profile.autoGrade {
                            Picker("升年级时间", selection: Binding(
                                get: { profile.gradeMonth },
                                set: { newValue in store.updateProfile(profile.id) { $0.gradeMonth = newValue } }
                            )) {
                                ForEach(1...12, id: \.self) { month in
                                    Text("每年 \(month) 月").tag(month)
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                if profile.didAutoUpgrade() {
                                    Text("已按时间自动升级：设置的是 \(SchoolGrade.title(profile.gradeBase))，现在是 \(profile.gradeTitle)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.good)
                                }
                                if let next = profile.nextGradeDate() {
                                    Text("下一次 \(Self.monthDayText(next)) 自动升到 \(profile.nextGradeTitle())")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.inkFaint)
                                } else {
                                    Text("已经是最高年级（六年级），不再自动升")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.inkFaint)
                                }
                                Text("年级决定学习页显示的内容量（幼儿园组词 3 个、小学 6 个），升年级会自动切换；每天学多少仍然按上面单独设置。")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.inkFaint)
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

                        Stepper(value: Binding(
                            get: { profile.wordsPerCard },
                            set: { newValue in store.updateProfile(profile.id) { $0.wordsPerCard = newValue } }
                        ), in: 0...4) {
                            HStack {
                                Text("每个词读几个")
                                Spacer()
                                Text(profile.wordsPerCard == 0 ? "不读词" : "\(profile.wordsPerCard) 个")
                                    .foregroundStyle(Theme.accent)
                                    .monospacedDigit()
                            }
                        }

                        Toggle(isOn: Binding(
                            get: { profile.readsPolyphonic },
                            set: { newValue in store.updateProfile(profile.id) { $0.readsPolyphonic = newValue } }
                        )) {
                            Text("多音字也读其他读音的组词")
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("组词都是词典里能查到的常用词，每个读音两个；关掉上面这个开关就只读最常用的那个读音。")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.inkFaint)
                        }

                        Stepper(value: Binding(
                            get: { profile.writesPerChar },
                            set: { newValue in store.updateProfile(profile.id) { $0.writesPerChar = newValue } }
                        ), in: 0...5) {
                            HStack {
                                Text("每个字写对几遍")
                                Spacer()
                                Text(profile.writesPerChar == 0 ? "不要求" : "\(profile.writesPerChar) 遍")
                                    .foregroundStyle(Theme.good)
                                    .monospacedDigit()
                            }
                        }

                        Toggle(isOn: Binding(
                            get: { profile.handwritingGhost },
                            set: { newValue in store.updateProfile(profile.id) { $0.handwritingGhost = newValue } }
                        )) {
                            Text("手写区显示淡色范字")
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("学习页右下角有手写区：跟读结束后让孩子用 Apple Pencil（或手指）把字写出来，识别对了算一遍；写够上面的遍数，「会了 / 有点忘」才会亮起来。设成 0 就是不要求手写。")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.inkFaint)
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
                                Text("\(gender.title) · \(gender == .female ? "预生成录音" : SpeechService.shared.voiceDescription(for: gender))")
                                    .tag(gender)
                            }
                        }

                        Toggle(isOn: Binding(
                            get: { profile.onlineAudio },
                            set: { newValue in store.updateProfile(profile.id) { $0.onlineAudio = newValue } }
                        )) {
                            Text("联网获取发音")
                        }

                        if profile.onlineAudio {
                            Button {
                                AudioCache.shared.clearCache()
                            } label: {
                                Text("清空发音缓存（\(AudioCache.shared.cachedCount) 个）")
                                    .font(.system(size: 15))
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
                        Text("\(profile.emoji) \(profile.name) · \(profile.gradeTitle) · 今天剩余：新字 \(profile.effectiveNewLimit()) 个 · 复习 \(profile.effectiveReviewLimit()) 个")
                            .font(.system(size: 12))
                    }
                }

                Section("关于") {
                    LabeledContent("版本", value: AppInfo.versionText)
                    LabeledContent("字库规模", value: "\(store.library.count) 字")
                    LabeledContent("笔顺数据", value: "Make Me a Hanzi")
                    LabeledContent("拼音 / 部首 / 释义", value: "开源字库（新华字典数据）")
                    LabeledContent("发音", value: "预生成离线音频（百度 TTS）")
                    LabeledContent("教材", value: "部编版一年级上 / 下册生字表")
                    Text("内容来源均为开源数据，仅供家庭学习使用。组词与释义后续会接入更严谨的校对流程。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkFaint)
                }
            }
            .sheet(item: $editingProfile) { profile in
                ProfileEditSheet(profile: profile) { name, emoji in
                    store.updateProfile(profile.id) {
                        $0.name = name
                        $0.emoji = emoji
                    }
                    store.saveNow()
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

    private static func monthDayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy 年 M 月 d 日"
        return formatter.string(from: date)
    }

    private func reset(_ profile: Profile) {
        store.resetProgress(profileID: profile.id)
        store.saveNow()
    }
}
