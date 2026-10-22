import SwiftUI
import SwiftData

/// 谁在学？（两个孩子各自的档案）
struct ProfilePickerView: View {
    let profiles: [Profile]
    var onSelect: (Profile) -> Void

    @Query private var allStates: [SRSState]

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

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper.ignoresSafeArea())
    }

    private func profileCard(_ profile: Profile) -> some View {
        let states = allStates.filter { $0.profileID == profile.id }
        let mastered = states.filter { $0.cardState == .mastered }.count
        let learning = states.filter { $0.cardState == .review || $0.cardState == .learning }.count

        return Button {
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
