import SwiftUI

// MARK: - 米字格

struct MiGrid: View {
    var lineColor: Color = Theme.inkFaint.opacity(0.55)
    var borderColor: Color = Theme.accent.opacity(0.55)

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            var border = Path()
            border.addRect(CGRect(x: 1, y: 1, width: w - 2, height: h - 2))
            context.stroke(border, with: .color(borderColor), lineWidth: 3)

            var cross = Path()
            cross.move(to: CGPoint(x: w / 2, y: 0))
            cross.addLine(to: CGPoint(x: w / 2, y: h))
            cross.move(to: CGPoint(x: 0, y: h / 2))
            cross.addLine(to: CGPoint(x: w, y: h / 2))
            context.stroke(cross, with: .color(lineColor.opacity(0.7)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [7, 7]))

            var diagonal = Path()
            diagonal.move(to: CGPoint(x: 0, y: 0))
            diagonal.addLine(to: CGPoint(x: w, y: h))
            diagonal.move(to: CGPoint(x: w, y: 0))
            diagonal.addLine(to: CGPoint(x: 0, y: h))
            context.stroke(diagonal, with: .color(lineColor.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [7, 7]))
        }
    }
}

// MARK: - 笔顺动画（原生渲染，逐笔"写"出来）

struct HanziBoard: View {
    let hanzi: String
    var showsGrid: Bool = true
    var inkColor: Color = Theme.ink
    /// 外部改变这个值即可重播笔顺
    var replayTrigger: Int = 0

    @State private var reveal: [CGFloat] = []

    private var data: HanziStrokeData { StrokeLibrary.shared.data(for: hanzi) }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                if showsGrid {
                    MiGrid()
                        .frame(width: side, height: side)
                }
                if data.outlines.isEmpty {
                    Text(hanzi)
                        .font(HanziFont.font(size: side * 0.62))
                        .foregroundStyle(inkColor)
                        .frame(width: side, height: side)
                } else {
                    ForEach(Array(data.outlines.enumerated()), id: \.offset) { index, outline in
                        strokeView(index: index, outline: outline, side: side)
                            .frame(width: side, height: side)
                    }
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .task(id: TaskKey(hanzi: hanzi, token: replayTrigger)) {
            await play()
        }
    }

    private struct TaskKey: Equatable {
        let hanzi: String
        let token: Int
    }

    @ViewBuilder
    private func strokeView(index: Int, outline: Path, side: CGFloat) -> some View {
        let progress: CGFloat = index < reveal.count ? reveal[index] : 1
        if index < data.medians.count {
            HanziStrokeShape(path: outline)
                .fill(inkColor)
                .mask(
                    HanziStrokeShape(path: data.medians[index])
                        .trim(from: 0, to: progress)
                        .stroke(style: StrokeStyle(lineWidth: max(8, side * 0.085),
                                                   lineCap: .round,
                                                   lineJoin: .round))
                )
        } else {
            HanziStrokeShape(path: outline)
                .fill(inkColor)
                .opacity(progress)
        }
    }

    @MainActor
    private func play() async {
        let count = data.outlines.count
        guard count > 0 else { return }
        reveal = Array(repeating: 0, count: count)
        try? await Task.sleep(nanoseconds: 250_000_000)
        for i in 0..<count {
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.33)) {
                if reveal.indices.contains(i) { reveal[i] = 1 }
            }
            try? await Task.sleep(nanoseconds: 390_000_000)
        }
    }
}
