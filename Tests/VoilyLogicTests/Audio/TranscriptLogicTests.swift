import XCTest
@testable import VoilyLogic

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
}
