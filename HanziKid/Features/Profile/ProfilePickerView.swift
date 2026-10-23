import SwiftUI

/// 谁在学？（两个孩子各自的档案）
struct ProfilePickerView: View {
    let profiles: [Profile]
    var onSelect: (Profile) -> Void

    @EnvironmentObject private var store: AppStore
    /// 正在编辑的档案（改名字 / 换头像）
    @State private var editing: Profile?

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text("今天，谁来认字？")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("每个孩子有自己的进度，字卡内容共享")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(.top, 60)

            HStack(spacing: 24) {
                ForEach(profiles) { profile in
                    profileCard(profile)
                }
            }

            Text("点卡片右上角的铅笔可以改名字、换头像")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkFaint)
                .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper.ignoresSafeArea())
        .task {
            #if DEBUG
            // 截图 / 冒烟测试用：--demo-edit-profile 直接打开第一个孩子的编辑页
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--demo-edit-profile"), editing == nil {
                try? await Task.sleep(nanoseconds: 600_000_000)
                editing = profiles.first
            }
            // --demo-rename：验证"改名 + 换头像"真的写进去了
            if arguments.contains("--demo-rename"), let first = profiles.first {
                try? await Task.sleep(nanoseconds: 400_000_000)
                store.updateProfile(first.id) {
                    $0.name = "小星星"
                    $0.emoji = "🦄"
                }
                store.saveNow()
            }
            #endif
        }
        .sheet(item: $editing) { profile in
            ProfileEditSheet(profile: profile) { name, emoji in
                store.updateProfile(profile.id) {
                    $0.name = name
                    $0.emoji = emoji
                }
                store.saveNow()
            }
        }
    }

    private func profileCard(_ profile: Profile) -> some View {
        let states = store.states(for: profile.id)
        let mastered = states.filter { $0.cardState == .mastered }.count
        let learning = states.filter { $0.cardState == .review || $0.cardState == .learning }.count

        return ZStack(alignment: .topTrailing) {
            Button {
                onSelect(profile)
            } label: {
            VStack(spacing: 14) {
                Text(profile.emoji)
                    .font(.system(size: 64))
                    .frame(width: 120, height: 120)
                    .background(Theme.paperDeep, in: Circle())

                Text(profile.name)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.ink)

                Text(profile.level.title)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Theme.paperDeep, in: Capsule())

                HStack(spacing: 18) {
                    stat(value: learning, label: "在学习")
                    stat(value: mastered, label: "已掌握")
                }
                .padding(.top, 4)

                Text("每天 \(profile.newPerDay) 个新字 · \(profile.reviewCap) 个复习")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.inkFaint)
            }
                .frame(width: 260, height: 380)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                .shadow(color: Theme.shadow, radius: 16, y: 6)
            }
            .buttonStyle(.plain)

            // 改名字 / 换头像
            Button {
                editing = profile
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 38, height: 38)
                    .background(Theme.paperDeep, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(14)
            .accessibilityLabel("编辑 \(profile.name) 的名字和头像")
        }
    }

    private func stat(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkFaint)
        }
    }
}
