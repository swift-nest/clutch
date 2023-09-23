import Atomics
import Foundation

public struct AsyncCount: CustomStringConvertible, Comparable {
  public typealias GlobalValue = UInt32
  public typealias TaskIdValue = UInt16
  public typealias TaskIndexValue = UInt16  // too small?

  // global, taskId, taskIndex
  private let value: UInt64

  public var globalId: GlobalValue {
    UInt32(value >> 32)
  }
  public var taskId: TaskIdValue {
    UInt16((value & 0xFFFF_0000) >> 16)
  }
  public var actorIndex: TaskIndexValue {
    UInt16(value & 0xFFFF)
  }
  public var description: String {
    "\(globalId) \(taskId).\(actorIndex)"
  }

  public static func < (lhs: AsyncCount, rhs: AsyncCount) -> Bool {
    lhs.value < rhs.value
  }

  fileprivate static func make(
    _ global: UInt32,
    taskId: UInt16,
    actorIndex: UInt16
  ) -> AsyncCount {
    var value = UInt64(global << 32)
    value &= UInt64(taskId << 16)
    value &= UInt64(actorIndex)
    return AsyncCount(value: value)
  }
}

public actor AsyncCounter {
  // global order really only needs to be unique (TODO: manage wrapping)
  public typealias GlobalValue = AsyncCount.GlobalValue
  public typealias TaskIdValue = AsyncCount.TaskIdValue
  public typealias TaskIndexValue = AsyncCount.TaskIndexValue

  private static let globalCount = ManagedAtomic<GlobalValue>(0)
  private static let globalTaskId = ManagedAtomic<TaskIdValue>(0)

  private static var taskIdSource = globalTaskId.loadThenWrappingIncrement(
    by: 1,
    ordering: .relaxed
  )

  // s.b in API?
  private let taskId = AsyncCounter.taskIdSource
  private var actorIndex = TaskIndexValue(0)

  // also need current?
  public func next() -> AsyncCount {
    let global = Self.globalCount.loadThenWrappingIncrement(ordering: .relaxed)
    let result = AsyncCount.make(global, taskId: taskId, actorIndex: actorIndex)
    actorIndex += 1  // actor serializes? never two actors per task?
    return result
  }
}
