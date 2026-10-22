import SwiftUI

@main
struct HanziKidApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    private var activeProfile: Profile? {
        if let id = store.activeProfileID, let matched = store.profile(id: id) {
            return matched
        }
        #if DEBUG
        // 截图 / 冒烟测试用：--demo 自动进入第一个档案
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            return store.profiles.first
        }
        #endif
        return nil
    }

    var body: some View {
        Group {
            if let profile = activeProfile {
                TodayView(profile: profile) {
                    store.setActiveProfile(nil)
                }
            } else if store.profiles.isEmpty {
                ProgressView("正在准备字库…")
                    .font(.system(size: 16))
            } else {
                ProfilePickerView(profiles: store.profiles) { profile in
                    store.setActiveProfile(profile.id)
                }
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .preferredColorScheme(.light)
    }
}
