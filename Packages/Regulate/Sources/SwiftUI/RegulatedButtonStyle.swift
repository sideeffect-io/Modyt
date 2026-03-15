//
//  RegulatedButtonStyle.swift
//  
//
//  Created by Thibault Wittemberg on 30/09/2022.
//

#if canImport(SwiftUI)
import SwiftUI

@MainActor
private final class RegulatedButtonTriggerRelay: ObservableObject {
  private var trigger: (() -> Void)?

  func update(trigger: @escaping () -> Void) {
    self.trigger = trigger
  }

  func fire() {
    trigger?()
  }
}

public struct RegulatedButtonStyle<R: Regulator<Void>>: PrimitiveButtonStyle {
  @StateObject var regulator = R.init()
  @StateObject private var triggerRelay = RegulatedButtonTriggerRelay()
  let dueTime: DispatchTimeInterval

  init(dueTime: DispatchTimeInterval) {
    self.dueTime = dueTime
  }

  public func makeBody(configuration: Configuration) -> some View {
    regulator.dueTime = self.dueTime
    triggerRelay.update {
      configuration.trigger()
    }
    regulator.output = { [triggerRelay] _ in
      await triggerRelay.fire()
    }

    if #available(iOS 15.0, macOS 12.0, *) {
      return Button(role: configuration.role) {
        regulator.push(())
      } label: {
        configuration.label
      }
    } else {
      return Button {
        regulator.push(())
      } label: {
        configuration.label
      }
    }
  }
}
#endif
