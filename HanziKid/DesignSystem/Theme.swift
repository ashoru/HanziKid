import SwiftUI
import UIKit

/// 统一视觉：护眼米白底 + 墨色字 + 暖橙主色
enum Theme {
    static let paper = Color(red: 0.984, green: 0.965, blue: 0.929)     // #FBF6ED
    static let paperDeep = Color(red: 0.957, green: 0.929, blue: 0.878)
    static let ink = Color(red: 0.129, green: 0.133, blue: 0.145)       // #212224
    static let inkSoft = Color(red: 0.35, green: 0.36, blue: 0.38)
    static let inkFaint = Color(red: 0.62, green: 0.62, blue: 0.63)
    static let accent = Color(red: 0.949, green: 0.478, blue: 0.290)    // 暖橙
    static let accentSoft = Color(red: 0.992, green: 0.886, blue: 0.835)
    static let good = Color(red: 0.298, green: 0.686, blue: 0.463)
    static let hard = Color(red: 0.937, green: 0.702, blue: 0.271)
    static let again = Color(red: 0.898, green: 0.451, blue: 0.427)
    static let card = Color.white
    static let shadow = Color.black.opacity(0.06)

    static func gradeColor(_ grade: ReviewGrade) -> Color {
        switch grade {
        case .good: return good
        case .hard: return hard
        case .again: return again
        }
    }
}

/// 汉字用楷体（教学标准字形），取不到则回退系统字体
enum HanziFont {
    private static let candidates = ["Kaiti SC", "STKaiti", "KaiTi", "Kaiti TC"]

    static func resolvedName() -> String? {
        candidates.first { UIFont(name: $0, size: 12) != nil }
    }

    static func font(size: CGFloat) -> Font {
        if let name = resolvedName() {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: .regular)
    }
}

extension View {
    /// 统一卡片样式
    func kidCard(padding: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Theme.shadow, radius: 12, y: 4)
    }
}
