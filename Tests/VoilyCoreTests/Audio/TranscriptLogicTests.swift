import XCTest
@testable import VoilyCore

final class TranscriptLogicTests: XCTestCase {
    func testTranscriptAccumulatorKeepsCommittedSegmentsAcrossPauses() {
        var accumulator = TranscriptAccumulator()

        XCTAssertEqual(accumulator.updatePartial("现在我来测试一下流式输出"), "现在我来测试一下流式输出")
        XCTAssertEqual(accumulator.commit("现在我来测试一下流式输出"), "现在我来测试一下流式输出")
        XCTAssertEqual(accumulator.updatePartial("如果我有停顿的话"), "现在我来测试一下流式输出如果我有停顿的话")
        XCTAssertEqual(accumulator.commit("如果我有停顿的话"), "现在我来测试一下流式输出如果我有停顿的话")
        XCTAssertEqual(accumulator.finalText, "现在我来测试一下流式输出如果我有停顿的话")
    }

    func testTranscriptAccumulatorAddsSpaceBetweenASCIIWordSegments() {
        var accumulator = TranscriptAccumulator()

        XCTAssertEqual(accumulator.commit("hello"), "hello")
        XCTAssertEqual(accumulator.updatePartial("world"), "hello world")
        XCTAssertEqual(accumulator.commit("world"), "hello world")
        XCTAssertEqual(accumulator.finalText, "hello world")
    }

    func testTranscriptAccumulatorAppendsIncrementalDeltasIntoLiveText() {
        var accumulator = TranscriptAccumulator()

        XCTAssertEqual(accumulator.appendDelta("你"), "你")
        XCTAssertEqual(accumulator.appendDelta("好"), "你好")
        XCTAssertEqual(accumulator.appendDelta("，世界"), "你好，世界")
        XCTAssertEqual(accumulator.finalText, "你好，世界")
    }

    func testTranscriptAccumulatorRevisesOverlappingPartialSuffix() {
        var accumulator = TranscriptAccumulator()

        XCTAssertEqual(accumulator.updateOverlappingPartial("我看这个本地六式显示"), "我看这个本地六式显示")
        XCTAssertEqual(
            accumulator.updateOverlappingPartial("本地流式显示还是有问题"),
            "我看这个本地流式显示还是有问题"
        )
        XCTAssertEqual(accumulator.finalText, "我看这个本地流式显示还是有问题")
    }

    func testTranscriptAccumulatorReplacesSimilarOverlappingTail() {
        var accumulator = TranscriptAccumulator()

        XCTAssertEqual(accumulator.updateOverlappingPartial("这里明显是有重复的，他会不会能显示出来？"), "这里明显是有重复的，他会不会能显示出来？")
        XCTAssertEqual(
            accumulator.updateOverlappingPartial("它会不会能显示出来并且修改的。"),
            "这里明显是有重复的，它会不会能显示出来并且修改的。"
        )
    }

    func testTranscriptAccumulatorAppendsOverlappingPartialWithoutReliableRevision() {
        var accumulator = TranscriptAccumulator()

        XCTAssertEqual(accumulator.updateOverlappingPartial("今天"), "今天")
        XCTAssertEqual(accumulator.updateOverlappingPartial("天气不错"), "今天天气不错")
    }

    func testTranscriptAccumulatorRevisesCommittedSuffixWithoutClearingLiveText() {
        var accumulator = TranscriptAccumulator()

        XCTAssertEqual(accumulator.updatePartial("第一段"), "第一段")
        XCTAssertEqual(accumulator.commitLiveText(), "第一段")
        XCTAssertEqual(accumulator.updatePartial("第二句"), "第一段第二句")
        XCTAssertEqual(accumulator.reviseCommittedSuffix("第一段尾巴"), "第一段尾巴第二句")
        XCTAssertEqual(accumulator.finalText, "第一段尾巴第二句")
    }

    func testPartialTranscriptDisplayThrottleEmitsFirstPartialImmediatelyAndBuffersRapidUpdates() {
        var throttle = PartialTranscriptDisplayThrottle(minimumInterval: 0.25)

        XCTAssertEqual(throttle.push("你", at: 0.00), "你")
        XCTAssertNil(throttle.push("你好", at: 0.05))
        XCTAssertNil(throttle.push("你好世", at: 0.10))
        XCTAssertEqual(throttle.pendingText, "你好世")
    }

    func testPartialTranscriptDisplayThrottleFlushesLatestBufferedTextAfterInterval() {
        var throttle = PartialTranscriptDisplayThrottle(minimumInterval: 0.25)

        XCTAssertEqual(throttle.push("你", at: 0.00), "你")
        XCTAssertNil(throttle.push("你好", at: 0.05))
        XCTAssertEqual(throttle.flush(at: 0.25), "你好")
        XCTAssertNil(throttle.pendingText)
    }

    func testPartialTranscriptDisplayThrottleDefaultIntervalIs220ms() {
        var throttle = PartialTranscriptDisplayThrottle()

        XCTAssertEqual(throttle.minimumInterval, 0.22, accuracy: 0.0001)
        XCTAssertEqual(throttle.push("你", at: 0.00), "你")
        XCTAssertNil(throttle.push("你好", at: 0.05))
        XCTAssertEqual(throttle.pendingText, "你好")
        XCTAssertEqual(throttle.flush(at: 0.22), "你好")
        XCTAssertNil(throttle.pendingText)
    }
}
