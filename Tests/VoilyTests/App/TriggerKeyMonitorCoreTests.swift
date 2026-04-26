import XCTest
@testable import Voily

final class TriggerKeyMonitorCoreTests: XCTestCase {
    func testSingleTapStartsDictationOnRelease() {
        var core = TriggerKeyMonitorCore(longPressThreshold: 0.8)

        XCTAssertEqual(core.handleTriggerPressChange(true, at: 0.00), [])
        XCTAssertEqual(core.handleTriggerPressChange(false, at: 0.05), [.startDictation])
        XCTAssertFalse(core.stateMachine.hasPendingGesture)
    }

    func testTapWhileDictatingFinishesDictation() {
        var core = TriggerKeyMonitorCore(longPressThreshold: 0.8)
        core.setSessionMode(.dictating)

        XCTAssertEqual(core.handleTriggerPressChange(true, at: 1.00), [])
        XCTAssertEqual(core.handleTriggerPressChange(false, at: 1.05), [.finishDictation])
    }

    func testLongPressStartsQuickTranslation() {
        var core = TriggerKeyMonitorCore(longPressThreshold: 0.8)

        XCTAssertEqual(core.handleTriggerPressChange(true, at: 0.00), [])
        XCTAssertEqual(core.handleLongPressTimer(at: 0.81), [.startQuickTranslation])
    }

    func testLongPressReleaseDoesNotTriggerExtraAction() {
        var core = TriggerKeyMonitorCore(longPressThreshold: 0.8)

        XCTAssertEqual(core.handleTriggerPressChange(true, at: 0.00), [])
        XCTAssertEqual(core.handleLongPressTimer(at: 0.81), [.startQuickTranslation])
        XCTAssertEqual(core.handleTriggerPressChange(false, at: 0.90), [])
    }

    func testLongPressDuringDictationIsIgnored() {
        var core = TriggerKeyMonitorCore(longPressThreshold: 0.8)
        core.setSessionMode(.dictating)

        XCTAssertEqual(core.handleTriggerPressChange(true, at: 0.00), [])
        XCTAssertEqual(core.handleLongPressTimer(at: 0.81), [])
        XCTAssertEqual(core.handleTriggerPressChange(false, at: 0.90), [])
    }

    func testChordedRightCommandPressDoesNotTriggerActions() {
        var core = TriggerKeyMonitorCore(longPressThreshold: 0.8)

        XCTAssertEqual(core.handleTriggerPressChange(true, at: 0.00), [])
        core.handleNonTriggerKeyDown()
        XCTAssertEqual(core.handleTriggerPressChange(false, at: 0.05), [])
        XCTAssertEqual(core.handleLongPressTimer(at: 0.90), [])
    }

    func testTriggerIgnoredWhileTranslationActive() {
        var core = TriggerKeyMonitorCore(longPressThreshold: 0.8)
        core.setSessionMode(.translating)

        XCTAssertEqual(core.handleTriggerPressChange(true, at: 1.00), [])
        XCTAssertEqual(core.handleLongPressTimer(at: 1.90), [])
        XCTAssertEqual(core.handleTriggerPressChange(false, at: 2.00), [])
    }

    func testChordDuringDictationDoesNotFinishRecording() {
        var core = TriggerKeyMonitorCore(longPressThreshold: 0.8)
        core.setSessionMode(.dictating)

        XCTAssertEqual(core.handleTriggerPressChange(true, at: 1.00), [])
        core.handleNonTriggerKeyDown()
        XCTAssertEqual(core.handleTriggerPressChange(false, at: 1.05), [])
        XCTAssertEqual(core.sessionMode, .dictating)
    }

    func testResetClearsPendingGestureState() {
        var core = TriggerKeyMonitorCore(longPressThreshold: 0.8)

        XCTAssertEqual(core.handleTriggerPressChange(true, at: 0.00), [])
        core.reset()

        XCTAssertEqual(core.handleLongPressTimer(at: 0.90), [])
        XCTAssertFalse(core.stateMachine.hasPendingGesture)
        XCTAssertEqual(core.sessionMode, .idle)
    }
}
