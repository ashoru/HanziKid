import CoreGraphics
import CoreText
import Foundation
import SwiftUI

// MARK: - 手写笔迹（归一化坐标，左上原点，0…1）

struct HandwritingSample: Equatable {
    /// 每一笔的点序列（归一化到 0…1，左上原点）
    var strokes: [[CGPoint]]
    /// 笔尖粗细（归一化，相对画布边长）
    var lineWidth: CGFloat

    init(strokes: [[CGPoint]], lineWidth: CGFloat) {
        self.strokes = strokes
        self.lineWidth = lineWidth
    }

    var allPoints: [CGPoint] { strokes.flatMap { $0 } }

    var pointCount: Int { strokes.reduce(0) { $0 + $1.count } }

    /// 折线重采样：两点间距压到不超过 `step`
    func resampled(step: CGFloat = 0.012) -> HandwritingSample {
        var result: [[CGPoint]] = []
        for stroke in strokes where !stroke.isEmpty {
            var points: [CGPoint] = [stroke[0]]
            for next in stroke.dropFirst() {
                let previous = points.last!
                let distance = hypot(next.x - previous.x, next.y - previous.y)
                let pieces = max(1, Int((distance / step).rounded(.up)))
                if pieces > 1 {
                    for k in 1..<pieces {
                        let t = CGFloat(k) / CGFloat(pieces)
                        points.append(CGPoint(x: previous.x + (next.x - previous.x) * t,
                                              y: previous.y + (next.y - previous.y) * t))
                    }
                }
                points.append(next)
            }
            result.append(points)
        }
        return HandwritingSample(strokes: result, lineWidth: lineWidth)
    }

    /// 整体平移（补偿"写偏了一点"）
    func shifted(by offset: CGPoint) -> HandwritingSample {
        HandwritingSample(strokes: strokes.map { $0.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) } },
                          lineWidth: lineWidth)
    }
}

// MARK: - 判定结果

struct HandwritingResult: Equatable {
    /// 0…1，给界面显示用（cover 与 stray 的平均）
    var score: Double
    /// 范字的笔画被写到的比例（覆盖率）
    var cover: Double
    /// 写出来的笔画落在范字上的比例（贴合度）
    var stray: Double
    /// 有效笔迹点数
    var inkPoints: Int
    /// 有没有可用的范字（false 时不做判定）
    var hasTemplate: Bool
    var isPass: Bool

    static let noTemplate = HandwritingResult(score: 0, cover: 0, stray: 0,
                                              inkPoints: 0, hasTemplate: false, isPass: false)

    static let empty = HandwritingResult(score: 0, cover: 0, stray: 0,
                                         inkPoints: 0, hasTemplate: true, isPass: false)

    var percentText: String { "\(Int((score * 100).rounded()))%" }
}

// MARK: - 手写识别（完全本地、离线）

/// 判定思路：把孩子的笔迹与范字的中线（笔顺 median，StrokeLibrary 提供）当成两条曲线比较。
/// - `cover`：范字中线上的点，有多少落在笔迹 `tau` 范围内 → 字写全了没有
/// - `stray`：笔迹上的点，有多少落在范字 `tau` 范围内 → 有没有写飞 / 写成别的字
///
/// 先按包围盒中心对齐一次（补偿"写偏了"），再算这两个值，取更好的那个。
/// 字库外的自造字没有笔顺数据时，退回「字模栅格 + 膨胀容差」的粗匹配。
enum HandwritingMatcher {

    struct Params: Equatable {
        /// 允许的偏差（相对画布边长）。0.042 ≈ 32 格网格里的 1.3 格
        var tau: CGFloat = 0.042
        /// 范字被覆盖到的比例下限
        var minCover: Double = 0.68
        /// 笔迹贴合范字的比例下限
        var minStray: Double = 0.78
        /// 对齐时最多平移多少（避免把不相关的笔迹硬"对齐"到范字上）
        var maxAlignShift: CGFloat = 0.06
        /// 允许"写小了/写大了"时等比缩放的倍数区间
        var minAlignScale: CGFloat = 0.55
        var maxAlignScale: CGFloat = 2.4
        /// 少于这么多点当作"还没写"
        var minInkPoints: Int = 14
        /// 笔迹跨度下限（挡掉"点一下""划一小道"）
        var minExtent: CGFloat = 0.35
        /// 采点步长（越小越精细也越慢）
        var step: CGFloat = 0.012

        // 兜底：字模栅格匹配的参数
        var gridTolerance: Int = 1
        var gridRecall: Double = 0.72
        var gridPrecision: Double = 0.55
    }

    static let defaultParams = Params()
    static let grid = 32

    // MARK: 对外入口

    static func check(_ sample: HandwritingSample,
                      hanzi: String,
                      strokeData: HanziStrokeData,
                      params: Params = HandwritingMatcher.defaultParams) -> HandwritingResult {
        let ink = sample.resampled(step: params.step)
        let inkPoints = ink.allPoints
        guard inkPoints.count >= params.minInkPoints else { return .empty }
        guard HandwritingMatcher.extent(of: inkPoints) >= params.minExtent else { return .empty }

        // 1) 有笔顺中线 → 曲线匹配（准）
        if !strokeData.medianPoints.isEmpty {
            let target = strokeData.medianPoints.flatMap { $0.resampledPoints(step: params.step) }
            var best = curveVerdict(ink: inkPoints, target: target, params: params)
            for candidate in alignedVariants(ink: inkPoints, target: strokeData.medianPoints, params: params) {
                let verdict = curveVerdict(ink: candidate, target: target, params: params)
                if verdict.score > best.score { best = verdict }
            }
            return best
        }

        // 2) 没有笔顺数据 → 字模栅格兜底
        let template = glyphMask(text: hanzi)
        guard !template.isEmpty else { return .noTemplate }
        return gridVerdict(ink, template: template, params: params)
    }

    // MARK: 曲线匹配

    private static func curveVerdict(ink: [CGPoint], target: [CGPoint], params: Params) -> HandwritingResult {
        guard !target.isEmpty else { return .noTemplate }
        let inkCount = ink.count
        let targetCount = target.count

        var coverHits = 0
        for point in target where nearestDistance(from: point, to: ink) <= params.tau { coverHits += 1 }
        var strayHits = 0
        for point in ink where nearestDistance(from: point, to: target) <= params.tau { strayHits += 1 }

        let cover = Double(coverHits) / Double(max(1, targetCount))
        let stray = Double(strayHits) / Double(max(1, inkCount))
        let score = 0.5 * cover + 0.5 * stray
        let isPass = cover >= params.minCover && stray >= params.minStray
        return HandwritingResult(score: score, cover: cover, stray: stray,
                                 inkPoints: inkCount, hasTemplate: true, isPass: isPass)
    }

    /// 把笔迹平移/缩放到范字的包围盒上，产生几个候选（写偏了、写小了都能救回来）
    private static func alignedVariants(ink: [CGPoint], target: [[CGPoint]], params: Params) -> [[CGPoint]] {
        var result: [[CGPoint]] = []
        let targetPoints = target.flatMap { $0 }
        guard let inkBox = box(ink), let targetBox = box(targetPoints) else { return result }

        // 1) 只平移
        let dx = max(-params.maxAlignShift, min(params.maxAlignShift, targetBox.midX - inkBox.midX))
        let dy = max(-params.maxAlignShift, min(params.maxAlignShift, targetBox.midY - inkBox.midY))
        if abs(dx) > 0.005 || abs(dy) > 0.005 {
            result.append(ink.map { CGPoint(x: $0.x + dx, y: $0.y + dy) })
        }

        // 2) 平移 + 等比缩放（写得太小/太大）
        //    单维退化的字（一、丨）按能用的那一维算，避免除零
        guard max(inkBox.width, inkBox.height) > 0.08 else { return result }
        let scaleX = targetBox.width / max(inkBox.width, 0.001)
        let scaleY = targetBox.height / max(inkBox.height, 0.001)
        let scale = (inkBox.width < 0.05 || inkBox.height < 0.05) ? max(scaleX, scaleY) : min(scaleX, scaleY)
        let clamped = max(params.minAlignScale, min(params.maxAlignScale, scale))
        if abs(clamped - 1) > 0.05 {
            result.append(ink.map { point in
                CGPoint(x: targetBox.midX + (point.x - inkBox.midX) * clamped,
                        y: targetBox.midY + (point.y - inkBox.midY) * clamped)
            })
        }
        return result
    }

    private static func nearestDistance(from point: CGPoint, to points: [CGPoint]) -> CGFloat {
        var best = CGFloat.greatestFiniteMagnitude
        for other in points {
            let dx = point.x - other.x
            let dy = point.y - other.y
            let d = dx * dx + dy * dy
            if d < best { best = d }
        }
        return best.squareRoot()
    }

    static func box(_ points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        var minX = first.x, maxX = first.x
        var minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func extent(of points: [CGPoint]) -> CGFloat {
        guard let box = box(points) else { return 0 }
        return max(box.width, box.height)
    }

    // MARK: 兜底：字模栅格匹配（只用于没有笔顺数据的自造字）

    static func glyphMask(text: String) -> [Bool] {
        guard !text.isEmpty else { return [] }
        let mask = rasterize { ctx, side in
            let font = makeFont(size: side * 0.92)
            let attributes = [kCTFontAttributeName: font] as CFDictionary
            guard let attributed = CFAttributedStringCreate(nil, text as CFString, attributes) else { return }
            let line = CTLineCreateWithAttributedString(attributed)
            let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            guard bounds.width > 0, bounds.height > 0 else { return }
            // 外层已翻成"左上原点"，写字要再翻回去，否则字是倒的
            ctx.saveGState()
            ctx.translateBy(x: 0, y: side)
            ctx.scaleBy(x: 1, y: -1)
            ctx.textMatrix = .identity
            ctx.textPosition = CGPoint(x: (side - bounds.width) / 2 - bounds.minX,
                                       y: (side - bounds.height) / 2 - bounds.minY)
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
        return mask.contains(true) ? mask : []
    }

    static func inkMask(_ sample: HandwritingSample) -> [Bool] {
        let resampled = sample.resampled(step: 0.008)
        return rasterize { ctx, side in
            ctx.setStrokeColor(gray: 1, alpha: 1)
            ctx.setLineWidth(max(1, sample.lineWidth * side))
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            for stroke in resampled.strokes where !stroke.isEmpty {
                let path = CGMutablePath()
                let first = CGPoint(x: stroke[0].x * side, y: stroke[0].y * side)
                path.move(to: first)
                if stroke.count == 1 {
                    path.addLine(to: CGPoint(x: first.x + 0.5, y: first.y))
                } else {
                    for point in stroke.dropFirst() {
                        path.addLine(to: CGPoint(x: point.x * side, y: point.y * side))
                    }
                }
                ctx.addPath(path)
                ctx.strokePath()
            }
        }
    }

    static func gridVerdict(_ sample: HandwritingSample, template: [Bool], params: Params) -> HandwritingResult {
        let cells = grid * grid
        guard template.count == cells else { return .noTemplate }
        let ink = inkMask(sample)
        let inkCells = ink.reduce(0) { $0 + ($1 ? 1 : 0) }
        let targetCells = template.reduce(0) { $0 + ($1 ? 1 : 0) }
        guard targetCells > 0 else { return .noTemplate }
        guard inkCells >= 8 else { return .empty }

        let inkFat = dilated(ink, radius: params.gridTolerance)
        let targetFat = dilated(template, radius: params.gridTolerance)
        var covered = 0
        var onTarget = 0
        for i in 0..<cells {
            if template[i] && inkFat[i] { covered += 1 }
            if ink[i] && targetFat[i] { onTarget += 1 }
        }
        let cover = Double(covered) / Double(targetCells)
        let stray = Double(onTarget) / Double(max(1, inkCells))
        let score = 0.5 * cover + 0.5 * stray
        let isPass = cover >= params.gridRecall && stray >= params.gridPrecision
        return HandwritingResult(score: score, cover: cover, stray: stray,
                                 inkPoints: inkCells, hasTemplate: true, isPass: isPass)
    }

    /// 用一个 y 向下（左上原点）的绘图闭包栅格化成 `grid × grid` 布尔网格
    private static func rasterize(_ draw: (CGContext, CGFloat) -> Void) -> [Bool] {
        let n = grid
        let count = n * n
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        buffer.initialize(repeating: 0, count: count)
        defer {
            buffer.deinitialize(count: count)
            buffer.deallocate()
        }
        guard let ctx = CGContext(data: buffer,
                                  width: n,
                                  height: n,
                                  bitsPerComponent: 8,
                                  bytesPerRow: n,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return [Bool](repeating: false, count: count) }

        ctx.setShouldAntialias(true)
        ctx.translateBy(x: 0, y: CGFloat(n))
        ctx.scaleBy(x: 1, y: -1)
        draw(ctx, CGFloat(n))

        var mask = [Bool](repeating: false, count: count)
        for i in 0..<count { mask[i] = buffer[i] >= 48 }
        return mask
    }

    private static func makeFont(size: CGFloat) -> CTFont {
        let candidates = ["Kaiti SC", "STKaiti", "Kaiti TC", "PingFang SC", "Heiti SC"]
        for name in candidates {
            let font = CTFontCreateWithName(name as CFString, size, nil)
            let family = CTFontCopyFamilyName(font) as String
            if family.compare(name, options: .caseInsensitive) == .orderedSame, CTFontGetGlyphCount(font) > 0 {
                return font
            }
        }
        return CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    /// 布尔网格膨胀（切比雪夫距离 ≤ radius）
    static func dilated(_ mask: [Bool], radius: Int) -> [Bool] {
        guard radius > 0 else { return mask }
        let n = grid
        var result = [Bool](repeating: false, count: n * n)
        for y in 0..<n {
            for x in 0..<n where mask[y * n + x] {
                for yy in max(0, y - radius)...min(n - 1, y + radius) {
                    for xx in max(0, x - radius)...min(n - 1, x + radius) {
                        result[yy * n + xx] = true
                    }
                }
            }
        }
        return result
    }
}

// MARK: - 折线加密小工具

extension Array where Element == CGPoint {
    /// 按 `step` 补齐相邻点之间的空隙（不改变形状，只是加密）
    func resampledPoints(step: CGFloat) -> [CGPoint] {
        guard count > 1 else { return self }
        var result: [CGPoint] = [self[0]]
        for next in dropFirst() {
            let previous = result.last!
            let distance = hypot(next.x - previous.x, next.y - previous.y)
            let pieces = Swift.max(1, Int((distance / step).rounded(.up)))
            if pieces > 1 {
                for k in 1..<pieces {
                    let ratio = CGFloat(k) / CGFloat(pieces)
                    result.append(CGPoint(x: previous.x + (next.x - previous.x) * ratio,
                                          y: previous.y + (next.y - previous.y) * ratio))
                }
            }
            result.append(next)
        }
        return result
    }
}
