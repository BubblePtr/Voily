import XCTest
@testable import Voily

final class FnShortcutStateMachineTests: XCTestCase {
    func testLongPressStartsAndStopsDictation() {
        var machine = FnShortcutStateMachine(longPressThreshold: 0.18, doubleTapWindow: 0.3)

        XCTAssertEqual(machine.handleKeyDown(at: 0), [])
        XCTAssertEqual(machine.handleLongPressTimer(at: 0.18), [.startDictation])
        XCTAssertEqual(machine.handleKeyUp(at: 0.25), [.finishDictation])
        XCTAssertEqual(machine.state, .idle)
    }

    func testSingleTapExpiresWithoutAction() {
        var machine = FnShortcutStateMachine(longPressThreshold: 0.18, doubleTapWindow: 0.3)

        XCTAssertEqual(machine.handleKeyDown(at: 0), [])
        XCTAssertEqual(machine.handleKeyUp(at: 0.1), [])
        XCTAssertEqual(machine.handleDoubleTapTimer(at: 0.4), [])
        XCTAssertEqual(machine.state, .idle)
    }

    func testSecondTapWithinWindowStartsQuickTranslation() {
        var machine = FnShortcutStateMachine(longPressThreshold: 0.18, doubleTapWindow: 0.3)

        XCTAssertEqual(machine.handleKeyDown(at: 0), [])
        XCTAssertEqual(machine.handleKeyUp(at: 0.1), [])
        XCTAssertEqual(machine.handleKeyDown(at: 0.35), [.startQuickTranslation])
        XCTAssertEqual(machine.state, .idle)
    }

    func testBoundaryValuesAreHandledConsistently() {
        var dictationMachine = FnShortcutStateMachine(longPressThreshold: 0.18, doubleTapWindow: 0.3)
        XCTAssertEqual(dictationMachine.handleKeyDown(at: 0), [])
        XCTAssertEqual(dictationMachine.handleLongPressTimer(at: 0.18), [.startDictation])
        XCTAssertEqual(dictationMachine.state, .dictating)

        var translationMachine = FnShortcutStateMachine(longPressThreshold: 0.18, doubleTapWindow: 0.3)
        XCTAssertEqual(translationMachine.handleKeyDown(at: 0), [])
        XCTAssertEqual(translationMachine.handleKeyUp(at: 0.1), [])
        XCTAssertEqual(translationMachine.handleKeyDown(at: 0.4), [.startQuickTranslation])
        XCTAssertEqual(translationMachine.state, .idle)
    }
}
