/// cf ``AsyncCount`` and ``AsyncCounter``
public class Count {
  public typealias Value = Int
  private var next: Value
  public init(next: Value) {
    self.next = next
  }
  public func nextPeek() -> Value {
    return next
  }

  public func nextInc() -> Value {
    let result = next
    if next < Int.max {
      next += 1
    }
    return result
  }
}

public class IndexedRecorder<Index, Tag, T> {
  public typealias Renderer = (T) -> String
  public typealias Record = (index: Index, tag: Tag, item: T)
  public typealias RecordStr = (Record, String)
  private var records = [Record]()
  public let tag: Tag
  private let renderer: Renderer

  public init(_ tag: Tag, _ renderer: @escaping Renderer) {
    self.tag = tag
    self.renderer = renderer
  }

  // TODO: want to restrict record to creator, but permit copy to anyone
  public func record(_ index: Index, _ record: T) {
    records.append((index, tag, record))
  }

  public func copy() -> [Record] {
    return records
  }

  public func copyStr() -> [RecordStr] {
    records.map { ($0, render($0.item)) }
  }

  public func render(_ item: T) -> String {
    renderer(item)
  }
}
