//
//  ThrottlerTests.swift
//  
//
//  Created by Thibault Wittemberg on 28/09/2022.
//

@testable import Regulate
import XCTest

final class ThrottlerTests: XCTestCase {
  func test_throttler_outputs_first_value_per_time_interval() async {
    let spy = Spy<Int>()
    let scheduler = ManualRegulateScheduler()

    let sut = Task.throttle(
      dueTime: .milliseconds(100),
      latest: false,
      scheduler: scheduler.scheduler
    ) { value in
      await spy.push(value)
    }

    sut.push(0)
    await settleRegulateTasks()
    scheduler.advance(by: .milliseconds(40))
    sut.push(1)
    scheduler.advance(by: .milliseconds(40))
    sut.push(2)
    scheduler.advance(by: .milliseconds(20))
    await settleRegulateTasks()
    sut.push(3)
    scheduler.advance(by: .milliseconds(40))
    sut.push(4)
    scheduler.advance(by: .milliseconds(60))
    await settleRegulateTasks()

    await spy.assertEqual(expected: [0, 3])
    sut.cancel()
  }

  func test_throttler_outputs_last_value_per_time_interval() async {
    let spy = Spy<Int>()
    let scheduler = ManualRegulateScheduler()

    let sut = Task.throttle(
      dueTime: .milliseconds(100),
      latest: true,
      scheduler: scheduler.scheduler
    ) { value in
      await spy.push(value)
    }

    sut.push(0)
    await settleRegulateTasks()
    scheduler.advance(by: .milliseconds(40))
    sut.push(1)
    scheduler.advance(by: .milliseconds(40))
    sut.push(2)
    scheduler.advance(by: .milliseconds(20))
    await settleRegulateTasks()
    sut.push(3)
    scheduler.advance(by: .milliseconds(40))
    sut.push(4)
    scheduler.advance(by: .milliseconds(60))
    await settleRegulateTasks()

    await spy.assertEqual(expected: [2, 4])
    sut.cancel()
  }

  func test_throttler_outputs_last_value_per_time_interval_when_no_last() async {
    let spy = Spy<Int>()
    let scheduler = ManualRegulateScheduler()

    let sut = Task.throttle(
      dueTime: .milliseconds(100),
      latest: true,
      scheduler: scheduler.scheduler
    ) { value in
      await spy.push(value)
    }

    sut.push(0)
    await settleRegulateTasks()
    scheduler.advance(by: .milliseconds(40))
    sut.push(1)
    scheduler.advance(by: .milliseconds(40))
    sut.push(2)
    scheduler.advance(by: .milliseconds(20))
    await settleRegulateTasks()
    scheduler.advance(by: .milliseconds(20))
    sut.push(3)
    scheduler.advance(by: .milliseconds(80))
    await settleRegulateTasks()

    await spy.assertEqual(expected: [2, 3])
    sut.cancel()
  }
}
