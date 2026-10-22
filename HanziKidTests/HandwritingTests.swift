import XCTest
@testable import HanziKid

/// 手写识别的一致性测试（与 Tools/logic_checks 里的断言对应）
final class HandwritingTests: XCTestCase {

    /// 「十」：一横一竖
    private var cross: HanziStrokeData {
        HanziStrokeData(outlines: [], medians: [], medianPoints: [
            [CGPoint(x: 0.20, y: 0.50), CGPoint(x: 0.80, y: 0.50)],
            [CGPoint(x: 0.50, y: 0.15), CGPoint(x: 0.50, y: 0.85)]
        ])
    }

    /// 「口」：一个方框
    private var box: HanziStrokeData {
        HanziStrokeData(outlines: [], medians: [], medianPoints: [
            [CGPoint(x: 0.28, y: 0.28), CGPoint(x: 0.72, y: 0.28)],
            [CGPoint(x: 0.28, y: 0.28), CGPoint(x: 0.28, y: 0.72)],
            [CGPoint(x: 0.72, y: 0.28), CGPoint(x: 0.72, y: 0.72)],
            [CGPoint(x: 0.28, y: 0.72), CGPoint(x: 0.72, y: 0.72)]
        ])
    }

    /// 把折点插值成密集点
    private func line(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = [points[0]]
        for next in points.dropFirst() {
            let previous = result.last!
            let distance = hypot(next.x - previous.x, next.y - previous.y)
            let pieces = max(2, Int((distance / 0.01).rounded(.up)))
            for k in 1..<pieces {
                let ratio = CGFloat(k) / CGFloat(pieces)
                result.append(CGPoint(x: previous.x + (next.x - previous.x) * ratio,
                                      y: previous.y + (next.y - previous.y) * ratio))
            }
            result.append(next)
        }
        return result
    }

    private func sample(_ strokes: [[CGPoint]], width: CGFloat = 0.05) -> HandwritingSample {
        HandwritingSample(strokes: strokes, lineWidth: width)
    }

    func testCorrectWritingPasses() {
        let ink = sample([line([CGPoint(x: 0.20, y: 0.50), CGPoint(x: 0.80, y: 0.50)]),
                          line([CGPoint(x: 0.50, y: 0.15), CGPoint(x: 0.50, y: 0.85)])])
        let result = HandwritingMatcher.check(ink, hanzi: "十", strokeData: cross)
        XCTAssertTrue(result.isPass)
        XCTAssertGreaterThan(result.cover, 0.9)
        XCTAssertGreaterThan(result.stray, 0.9)
    }

    func testShakyWritingStillPasses() {
        let ink = sample([
            line([CGPoint(x: 0.20, y: 0.50), CGPoint(x: 0.40, y: 0.52),
                  CGPoint(x: 0.60, y: 0.48), CGPoint(x: 0.80, y: 0.50)]),
            line([CGPoint(x: 0.51, y: 0.15), CGPoint(x: 0.49, y: 0.50), CGPoint(x: 0.51, y: 0.85)])
        ], width: 0.07)
        XCTAssertTrue(HandwritingMatcher.check(ink, hanzi: "十", strokeData: cross).isPass)
    }

    func testSmallAndOffsetWritingPasses() {
        let ink = sample([
            line([CGPoint(x: 0.32, y: 0.60), CGPoint(x: 0.62, y: 0.60)]),
            line([CGPoint(x: 0.47, y: 0.42), CGPoint(x: 0.47, y: 0.78)])
        ], width: 0.04)
        XCTAssertTrue(HandwritingMatcher.check(ink, hanzi: "十", strokeData: cross).isPass)
    }

    func testMissingStrokeFails() {
        let ink = sample([line([CGPoint(x: 0.20, y: 0.50), CGPoint(x: 0.80, y: 0.50)])])
        XCTAssertFalse(HandwritingMatcher.check(ink, hanzi: "十", strokeData: cross).isPass)
    }

    func testWrongCharacterFails() {
        let ink = sample(box.medianPoints.map { line($0) })
        XCTAssertFalse(HandwritingMatcher.check(ink, hanzi: "十", strokeData: cross).isPass)
        XCTAssertTrue(HandwritingMatcher.check(ink, hanzi: "口", strokeData: box).isPass)
    }

    func testScribbleAndDotFail() {
        let circle = (0...40).map { index -> CGPoint in
            let angle = CGFloat(index) / 40 * 2 * .pi
            return CGPoint(x: 0.5 + 0.3 * cos(angle), y: 0.5 + 0.3 * sin(angle))
        }
        XCTAssertFalse(HandwritingMatcher.check(sample([line(circle)]), hanzi: "十", strokeData: cross).isPass)
        XCTAssertFalse(HandwritingMatcher.check(sample([[CGPoint(x: 0.5, y: 0.5)]]), hanzi: "十", strokeData: cross).isPass)
        XCTAssertFalse(HandwritingMatcher.check(sample([]), hanzi: "十", strokeData: cross).isPass)
    }

    func testMissingTemplateIsNotBlocking() {
        let ink = sample([line([CGPoint(x: 0.2, y: 0.5), CGPoint(x: 0.8, y: 0.5)])])
        XCTAssertFalse(HandwritingMatcher.check(ink, hanzi: "龘", strokeData: .empty).hasTemplate)
    }

    func testWritesPerCharSetting() {
        var profile = Profile(name: "豆豆", level: .preschool, emoji: "🐣")
        XCTAssertEqual(profile.writesPerChar, 2)
        XCTAssertTrue(profile.handwritingGhost)
        profile.writesPerChar = 9
        XCTAssertEqual(profile.writesPerChar, 5)
        profile.writesPerChar = -1
        XCTAssertEqual(profile.writesPerChar, 0)
    }
}
