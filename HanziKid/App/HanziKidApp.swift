import SwiftUI
import SwiftData

@main
struct HanziKidApp: App {
    private let container: ModelContainer

    init() {
        container = Self.makeContainer()
        LibrarySeeder.seedIfNeeded(container.mainContext)
        SpeechService.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([
            Profile.self,
            CharacterCard.self,
            Deck.self,
            SRSState.self,
            ReviewLog.self,
        ])
        do {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // 开发期兜底：结构不兼容时退回内存库，避免一启动就崩
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [fallback])
        }
    }
}

struct RootView: View {
    @Query(sort: \Profile.createdAt) private var profiles: [Profile]
    @AppStorage("activeProfileID") private var activeProfileID: String = ""

    private var activeProfile: Profile? {
        if let matched = profiles.first(where: { $0.id.uuidString == activeProfileID }) {
            return matched
        }
        #if DEBUG
        // 截图 / 冒烟测试用：--demo 自动进入第一个档案
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            return profiles.first
        }
        #endif
        return nil
    }

    var body: some View {
        Group {
            if let profile = activeProfile {
                TodayView(profile: profile) {
                    activeProfileID = ""
                }
            } else if profiles.isEmpty {
                ProgressView("正在准备字库…")
                    .font(.system(size: 16))
            } else {
                ProfilePickerView(profiles: profiles) { profile in
                    activeProfileID = profile.id.uuidString
                }
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .preferredColorScheme(.light)
    }
}
