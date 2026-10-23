import PencilKit
import SwiftUI

// MARK: - 手写区（学习页右下方）

/// 跟读结束后，让孩子用 Apple Pencil（或手指）把当前字写出来。
/// 识别对了算「写了一遍」，攒够家长设置的遍数才能换下一个字。
struct HandwritingPad: View {
    let hanzi: String
    /// 需要写对几遍（0 = 不要求）
    let required: Int
    /// 已经写对几遍
    let done: Int
    /// 跟读还没结束 → 先不能写
    let isLocked: Bool
    /// 显示淡色范字（描红）
    let showsGhost: Bool
    /// 写对一遍时回调
    let onPass: () -> Void

    @State private var drawing = PKDrawing()
    @State private var clearToken = 0
    @State private var verdict: HandwritingResult?
    @State private var attempts = 0
    @State private var celebrating = false
    @State private var toast: String?
    @State private var padSide: CGFloat = 300

    private var strokeData: HanziStrokeData { StrokeLibrary.shared.data(for: hanzi) }
    private var isComplete: Bool { required > 0 && done >= required }
    /// 有没有写出东西（决定「写好了」按钮能不能点）
    private var hasInk: Bool { !drawing.strokes.isEmpty }
    private var canCheck: Bool { hasInk && !isLocked && !celebrating }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            pad
            footer
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Theme.shadow, radius: 12, y: 4)
        .onChange(of: hanzi) { _ in
            reset()
        }
        .task(id: TaskKey(hanzi: hanzi, locked: isLocked)) {
            await runDemoInkIfNeeded()
        }
    }

    // MARK: 顶部说明 + 进度

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil.and.outline")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("写一写")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 4)
            if required > 0 {
                HStack(spacing: 6) {
                    ForEach(0..<required, id: \.self) { index in
                        Circle()
                            .fill(index < done ? Theme.good : Theme.paperDeep)
                            .frame(width: 11, height: 11)
                            .overlay(Circle().stroke(Theme.inkFaint.opacity(index < done ? 0 : 0.35), lineWidth: 1))
                    }
                    Text("\(done)/\(required) 遍")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(done >= required ? Theme.good : Theme.inkSoft)
                        .monospacedDigit()
                }
            } else {
                Text("选做")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.inkFaint)
            }
        }
    }

    // MARK: 写字板

    private var pad: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                MiGrid()

                if showsGhost {
                    GhostGlyph(hanzi: hanzi, data: strokeData, side: side)
                        .allowsHitTesting(false)
                }

                InkCanvas(drawing: $drawing,
                          isEnabled: !isLocked && !celebrating,
                          lineWidth: max(10, side * 0.045),
                          clearToken: clearToken,
                          onChange: handleDrawingChanged)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                if isLocked {
                    lockedOverlay
                }

                if celebrating {
                    celebrateOverlay
                } else if let toast {
                    hintBanner(toast)
                }
            }
            .frame(width: side, height: side)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .onAppear { padSide = side }
            .onChange(of: side) { newSide in padSide = newSide }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var lockedOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.paper.opacity(0.82))
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                Text("先听一遍读音，再写")
            }
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Theme.inkSoft)
        }
        .allowsHitTesting(true)
    }

    private var celebrateOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Theme.good.opacity(0.12))
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(Theme.good)
                Text(isComplete ? "这个字写好啦！" : "写对啦！")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.good)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .transition(.scale.combined(with: .opacity))
        }
        .allowsHitTesting(false)
    }

    /// 判定没通过时的提示（写在板子下方，不挡笔迹）
    private func hintBanner(_ text: String) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "arrow.uturn.left.circle.fill")
                Text(text)
            }
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.again.opacity(0.94), in: Capsule())
            .padding(.bottom, 12)
        }
        .allowsHitTesting(false)
    }

    // MARK: 底部按钮 + 提示

    private var footer: some View {
        VStack(spacing: 8) {
            if required > 0 {
                Text(isComplete ? "这个字写好啦，可以换下一个" : "写对 \(max(0, required - done)) 遍就能换下一个字")
                    .font(.system(size: 13))
                    .foregroundStyle(isComplete ? Theme.good : Theme.inkFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button {
                    clear()
                } label: {
                    Image(systemName: "eraser.line.dashed")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 56, height: 54)
                        .background(Theme.paperDeep, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isLocked || celebrating)
                .accessibilityLabel("擦掉重写")

                Button {
                    check()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: canCheck ? "checkmark.seal.fill" : "hand.draw.fill")
                            .font(.system(size: 20, weight: .semibold))
                        Text(canCheck ? "写好了，看看对不对" : "先写，再点这里")
                            .font(.system(size: 19, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(canCheck ? Theme.accent : Theme.inkFaint.opacity(0.4),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canCheck)
            }
        }
    }

    // MARK: 识别

    /// 笔迹变化只记录，不自动判定 —— 必须由小朋友点「写好了」才认
    private func handleDrawingChanged(_ newDrawing: PKDrawing) {
        drawing = newDrawing
        guard !isLocked, !celebrating else { return }
        if verdict != nil { verdict = nil }
    }

    /// 「写好了」按钮
    private func check() {
        guard canCheck else { return }
        evaluate()
    }

    private func evaluate() {
        guard canCheck else { return }
        let sample = makeSample()
        // 至少要有两笔中的一个有效笔画才判定（单笔画字如「一」点数本来就不多）
        guard sample.strokes.contains(where: { $0.count >= 2 }) else { return }

        let result = HandwritingMatcher.check(sample, hanzi: hanzi, strokeData: strokeData)
        attempts += 1

        // 字库外的自造字、或字模渲染失败时不做拦截
        if !result.hasTemplate {
            pass(praise: false)
            return
        }

        verdict = result
        if result.isPass {
            pass(praise: true)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            if result.cover < 0.5 {
                toast = "笔画还没写全，再补几笔"
            } else {
                toast = "和范字不太像，擦掉重写一次"
            }
        }
    }

    private func pass(praise: Bool) {
        if praise {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            celebrating = true
        }
        onPass()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            withAnimation(.easeOut(duration: 0.2)) { celebrating = false }
            clear()
        }
    }

    private func makeSample() -> HandwritingSample {
        let side = max(padSide, 1)
        var widths: [CGFloat] = []
        var strokes: [[CGPoint]] = []
        for stroke in drawing.strokes {
            var points: [CGPoint] = []
            for point in stroke.path {
                points.append(CGPoint(x: point.location.x / side, y: point.location.y / side))
                let width = point.size.width
                if width > 0 { widths.append(width) }
            }
            if !points.isEmpty { strokes.append(points) }
        }
        let averageWidth = widths.isEmpty ? max(10, side * 0.045) : widths.reduce(0, +) / CGFloat(widths.count)
        return HandwritingSample(strokes: strokes, lineWidth: averageWidth / side)
    }

    private func clear() {
        verdict = nil
        toast = nil
        drawing = PKDrawing()
        clearToken += 1
    }

    private func reset() {
        clear()
        attempts = 0
        celebrating = false
    }

    // MARK: 调试 / 冒烟测试

    private struct TaskKey: Equatable {
        let hanzi: String
        let locked: Bool
    }

    #if DEBUG
    /// --demo-write：自动把当前字"写"进手写区，验证识别 → 计数 → 解锁全链路（截图用）
    private func runDemoInkIfNeeded() async {
        guard ProcessInfo.processInfo.arguments.contains("--demo-write") else { return }
        guard !isLocked else { return }
        try? await Task.sleep(nanoseconds: 800_000_000)
        guard !Task.isCancelled else { return }

        let rounds = max(1, min(3, required == 0 ? 1 : required))
        for _ in 0..<rounds {
            let strokes = strokeData.medianPoints.filter { $0.count >= 2 }
            guard !strokes.isEmpty else { return }
            let side = max(padSide, 1)
            var pkStrokes: [PKStroke] = []
            for line in strokes {
                let points = line.enumerated().map { index, point in
                    PKStrokePoint(location: CGPoint(x: point.x * side, y: point.y * side),
                                  timeOffset: TimeInterval(index) * 0.01,
                                  size: CGSize(width: max(10, side * 0.045), height: max(10, side * 0.045)),
                                  opacity: 1,
                                  force: 1,
                                  azimuth: 0,
                                  altitude: .pi / 2)
                }
                let path = PKStrokePath(controlPoints: points, creationDate: Date())
                pkStrokes.append(PKStroke(ink: PKInk(.pen, color: UIColor(Theme.ink)), path: path))
            }
            handleDrawingChanged(PKDrawing(strokes: pkStrokes))
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            check()      // 手动判定的流程也一起验证
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
        }
    }
    #else
    private func runDemoInkIfNeeded() async {}
    #endif
}

// MARK: - 淡色范字（描红底）

private struct GhostGlyph: View {
    let hanzi: String
    let data: HanziStrokeData
    let side: CGFloat

    var body: some View {
        ZStack {
            if data.outlines.isEmpty {
                Text(hanzi)
                    .font(HanziFont.font(size: side * 0.78))
                    .foregroundStyle(Theme.accent.opacity(0.14))
            } else {
                ForEach(Array(data.outlines.enumerated()), id: \.offset) { _, outline in
                    HanziStrokeShape(path: outline)
                        .fill(Theme.accent.opacity(0.14))
                }
            }
        }
        .frame(width: side, height: side)
    }
}

// MARK: - PencilKit 画布

private struct InkCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let isEnabled: Bool
    let lineWidth: CGFloat
    let clearToken: Int
    let onChange: (PKDrawing) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let view = PKCanvasView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.drawingPolicy = .anyInput          // 手指也能写
        view.delegate = context.coordinator
        view.tool = PKInkingTool(.pen, color: UIColor(Theme.ink), width: lineWidth)
        view.drawing = drawing
        context.coordinator.token = clearToken
        return view
    }

    func updateUIView(_ view: PKCanvasView, context: Context) {
        context.coordinator.onChange = onChange
        view.isUserInteractionEnabled = isEnabled

        if view.drawing != drawing {
            view.drawing = drawing
        }

        if context.coordinator.token != clearToken {
            context.coordinator.token = clearToken
            view.drawing = PKDrawing()
        }
        if let tool = view.tool as? PKInkingTool, abs(tool.width - lineWidth) > 0.5 {
            view.tool = PKInkingTool(.pen, color: UIColor(Theme.ink), width: lineWidth)
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var onChange: (PKDrawing) -> Void
        var token = 0

        init(onChange: @escaping (PKDrawing) -> Void) {
            self.onChange = onChange
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onChange(canvasView.drawing)
        }
    }
}
