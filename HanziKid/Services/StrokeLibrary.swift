import Foundation
import SwiftUI

// MARK: - 单个汉字的笔顺数据

struct HanziStrokeData {
    /// 每一笔的填充轮廓（makemeahanzi 原始 1024 网格，y 轴向上）
    let outlines: [Path]
    /// 每一笔的中线，用于"顺手写出来"的逐步显示
    let medians: [Path]
    /// 每一笔中线的点序列，已归一化到 0…1（左上原点），手写识别用
    let medianPoints: [[CGPoint]]

    static let empty = HanziStrokeData(outlines: [], medians: [], medianPoints: [])
}

// MARK: - 笔顺库（从内置 strokes.json 读取，按字懒解析）

final class StrokeLibrary {
    static let shared = StrokeLibrary()

    private struct Raw: Decodable {
        let strokes: [String]
        let medians: [[[Double]]]
    }

    private var raw: [String: Raw] = [:]
    private var cache: [String: HanziStrokeData] = [:]
    private let queue = DispatchQueue(label: "hanzikid.strokes")

    private init() {
        guard let url = Bundle.main.url(forResource: "strokes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Raw].self, from: data)
        else { return }
        raw = decoded
    }

    func hasData(for hanzi: String) -> Bool { raw[hanzi] != nil }

    func strokeCount(for hanzi: String) -> Int { raw[hanzi]?.strokes.count ?? 0 }

    func data(for hanzi: String) -> HanziStrokeData {
        var result: HanziStrokeData?
        queue.sync {
            if let cached = cache[hanzi] {
                result = cached
                return
            }
            guard let entry = raw[hanzi] else {
                result = .empty
                return
            }
            let outlines = entry.strokes.map { SVGPath.parse($0) }
            let medians = entry.medians.map { SVGPath.polyline($0) }
            // 1024 网格、y 轴向上 → 归一化 0…1、左上原点（和手写画布一致）
            let medianPoints = entry.medians.map { stroke in
                stroke.compactMap { point -> CGPoint? in
                    guard point.count >= 2 else { return nil }
                    return CGPoint(x: point[0] / 1024.0, y: (900 - point[1]) / 1024.0)
                }
            }
            let built = HanziStrokeData(outlines: outlines, medians: medians, medianPoints: medianPoints)
            cache[hanzi] = built
            result = built
        }
        return result ?? .empty
    }
}

// MARK: - SVG path 解析（只支持 makemeahanzi 用到的 M/L/Q/C/Z，顺带兼容相对指令）

enum SVGPath {
    static func polyline(_ points: [[Double]]) -> Path {
        var path = Path()
        guard let first = points.first, first.count >= 2 else { return path }
        path.move(to: CGPoint(x: first[0], y: first[1]))
        for p in points.dropFirst() where p.count >= 2 {
            path.addLine(to: CGPoint(x: p[0], y: p[1]))
        }
        return path
    }

    static func parse(_ d: String) -> Path {
        var path = Path()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero

        for (cmd, nums) in tokenize(d) {
            var i = 0
            switch cmd {
            case "M", "m":
                while i + 1 < nums.count {
                    let p = point(nums, i, relative: cmd == "m", base: current)
                    if i == 0 {
                        path.move(to: p)
                        subpathStart = p
                    } else {
                        path.addLine(to: p)
                    }
                    current = p
                    i += 2
                }
            case "L", "l":
                while i + 1 < nums.count {
                    let p = point(nums, i, relative: cmd == "l", base: current)
                    path.addLine(to: p)
                    current = p
                    i += 2
                }
            case "H", "h":
                while i < nums.count {
                    let x = cmd == "h" ? current.x + nums[i] : nums[i]
                    current = CGPoint(x: x, y: current.y)
                    path.addLine(to: current)
                    i += 1
                }
            case "V", "v":
                while i < nums.count {
                    let y = cmd == "v" ? current.y + nums[i] : nums[i]
                    current = CGPoint(x: current.x, y: y)
                    path.addLine(to: current)
                    i += 1
                }
            case "Q", "q":
                while i + 3 < nums.count {
                    let c = point(nums, i, relative: cmd == "q", base: current)
                    let e = point(nums, i + 2, relative: cmd == "q", base: current)
                    path.addQuadCurve(to: e, control: c)
                    current = e
                    i += 4
                }
            case "C", "c":
                while i + 5 < nums.count {
                    let c1 = point(nums, i, relative: cmd == "c", base: current)
                    let c2 = point(nums, i + 2, relative: cmd == "c", base: current)
                    let e = point(nums, i + 4, relative: cmd == "c", base: current)
                    path.addCurve(to: e, control1: c1, control2: c2)
                    current = e
                    i += 6
                }
            case "Z", "z":
                path.closeSubpath()
                current = subpathStart
            default:
                break
            }
        }
        return path
    }

    private static func point(_ nums: [Double], _ i: Int, relative: Bool, base: CGPoint) -> CGPoint {
        let x = nums[i], y = nums[i + 1]
        return relative ? CGPoint(x: base.x + x, y: base.y + y) : CGPoint(x: x, y: y)
    }

    /// 拆成 [(指令, 数字数组)]
    private static func tokenize(_ d: String) -> [(Character, [Double])] {
        var result: [(Character, [Double])] = []
        var numbers: [Double] = []
        var current: Character?
        var buffer = ""
        var hasBuffer = false

        func flush() {
            if hasBuffer, let v = Double(buffer) { numbers.append(v) }
            buffer = ""
            hasBuffer = false
        }

        for ch in d {
            if ch.isLetter {
                flush()
                if let c = current {
                    result.append((c, numbers))
                    numbers = []
                }
                current = ch
            } else if ch == "," || ch == " " || ch == "\n" || ch == "\t" || ch == "\r" {
                flush()
            } else if ch == "-" {
                flush()
                buffer = "-"
                hasBuffer = true
            } else {
                buffer.append(ch)
                hasBuffer = true
            }
        }
        flush()
        if let c = current { result.append((c, numbers)) }
        return result
    }
}

// MARK: - 形状：把 1024 网格（y 向上）映射到视图坐标（y 向下）

struct HanziStrokeShape: Shape {
    let path: Path

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 1024.0
        // 目标：x' = s·x ；y' = s·(900 − y) = −s·y + 900s
        let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale,
                                          tx: rect.minX, ty: rect.minY + 900 * scale)
        return path.applying(transform)
    }
}
