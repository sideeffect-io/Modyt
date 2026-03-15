//
//  DebouncerTests.swift
//  
//
//  Created by Thibault Wittemberg on 28/09/2022.
//

@testable import Regulate
import XCTest

final class DebouncerTests: XCTestCase {
  func test_debouncer_discards_intermediates_values_and_outputs_last_value() async {
    let spy = Spy<Int>()
    let scheduler = ManualRegulateScheduler()

    let sut = Task.debounce(
      dueTime: .milliseconds(200),
      scheduler: scheduler.scheduler
    ) { value in
      await spy.push(value)
    }

    sut.push(0)
    scheduler.advance(by: .milliseconds(100))
    sut.push(1)
    scheduler.advance(by: .milliseconds(100))
    sut.push(2)
    scheduler.advance(by: .milliseconds(100))
    sut.push(3)
    scheduler.advance(by: .milliseconds(100))
    sut.push(4)
    scheduler.advance(by: .milliseconds(199))
    await settleRegulateTasks()
    await spy.assertEqual(expected: [])

    scheduler.advance(by: .milliseconds(1))
    await settleRegulateTasks()

    await spy.assertEqual(expected: [4])
    sut.cancel()
  }
}
