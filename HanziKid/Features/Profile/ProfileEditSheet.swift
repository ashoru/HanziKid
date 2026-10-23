import SwiftUI

/// 改名字 / 换头像（两个孩子都能自定义，不再是固定的「豆豆」「果果」）
struct ProfileEditSheet: View {
    let profile: Profile
    var onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var emoji: String
    @FocusState private var nameFocused: Bool

    private static let emojiChoices = [
        "🐣", "🐥", "🦁", "🐼", "🐰", "🐯", "🐨", "🐷",
        "🐸", "🦊", "🐻", "🐮", "🐵", "🦄", "🐙", "🦖",
        "🌟", "🍎", "🚀", "🌈"
    ]

    private static let maxNameLength = 12

    init(profile: Profile, onSave: @escaping (String, String) -> Void) {
        self.profile = profile
        self.onSave = onSave
        _name = State(initialValue: profile.name)
        _emoji = State(initialValue: profile.emoji.isEmpty ? "🐣" : profile.emoji)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && trimmedName.count <= Self.maxNameLength
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        Text(emoji)
                            .font(.system(size: 52))
                            .frame(width: 88, height: 88)
                            .background(Theme.paperDeep, in: Circle())
                        VStack(alignment: .leading, spacing: 6) {
                            Text(trimmedName.isEmpty ? "还没起名字" : trimmedName)
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(trimmedName.isEmpty ? Theme.inkFaint : Theme.ink)
                            Text(profile.gradeTitle)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    TextField("例如：豆豆", text: $name)
                        .font(.system(size: 22))
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit { if canSave { save() } }
                        .onChange(of: name) { newValue in
                            if newValue.count > Self.maxNameLength {
                                name = String(newValue.prefix(Self.maxNameLength))
                            }
                        }
                    if trimmedName.isEmpty {
                        Text("名字不能为空")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.again)
                    }
                } header: {
                    Text("名字")
                } footer: {
                    Text("最多 \(Self.maxNameLength) 个字，可以随时再改；进度按档案走，改名字不会丢学习记录。")
                        .font(.system(size: 12))
                }

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                        ForEach(Self.emojiChoices, id: \.self) { choice in
                            Button {
                                emoji = choice
                            } label: {
                                Text(choice)
                                    .font(.system(size: 30))
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(emoji == choice ? Theme.accentSoft : Theme.paperDeep)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(emoji == choice ? Theme.accent : .clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("头像")
                } footer: {
                    Text("想用别的？在下面的输入框里打一个 emoji 就行。")
                        .font(.system(size: 12))
                }

                Section {
                    TextField("自定义头像（一个 emoji）", text: Binding(
                        get: { emoji },
                        set: { newValue in
                            // 只收第一个字符，避免塞进一整段文字
                            if let first = newValue.first {
                                emoji = String(first)
                            } else {
                                emoji = ""
                            }
                        }
                    ))
                    .font(.system(size: 22))
                }
            }
            .navigationTitle("编辑档案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear { nameFocused = true }
        }
    }

    private func save() {
        guard canSave else { return }
        onSave(trimmedName, emoji.isEmpty ? profile.emoji : emoji)
        dismiss()
    }
}
