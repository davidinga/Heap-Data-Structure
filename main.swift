@frozen
public struct Heap {
  @usableFromInline
  internal var _storage: ContiguousArray

  @inlinable
  public init() {
    _storage = []
  }
}

#if swift(>=5.5)
extension Heap: Sendable where Element: Sendable {}
#endif

extension Heap {
  @inlinable @inline(__always)
  public var isEmpty: Bool {
    _storage.isEmpty
  }

  @inlinable @inline(__always)
  public var count: Int {
    _storage.count
  }

  @inlinable
  public var unordered: [Element] {
    Array(_storage)
  }

  @inlinable
  public mutating func insert(_ element: Element) {
    _storage.append(element)

    _update { handle in
      handle.bubbleUp(_Node(offset: handle.count - 1))
    }
    _checkInvariants()
  }

  @inlinable
  public func min() -> Element? {
    _storage.first
  }

  @inlinable
  public func max() -> Element? {
    _storage.withUnsafeBufferPointer { buffer in
      guard buffer.count > 2 else {
        return buffer.last
      }
      return Swift.max(buffer[1], buffer[2])
    }
  }

  @inlinable
  public mutating func popMin() -> Element? {
    guard _storage.count > 0 else { return nil }

    var removed = _storage.removeLast()

    if _storage.count > 0 {
      _update { handle in
        let minNode = _Node.root
        handle.swapAt(minNode, with: &removed)
        handle.trickleDownMin(minNode)
      }
    }

    _checkInvariants()
    return removed
  }

  @inlinable
  public mutating func popMax() -> Element? {
    guard _storage.count > 2 else { return _storage.popLast() }

    var removed = _storage.removeLast()

    _update { handle in
      if handle.count == 2 {
        if handle[.leftMax] > removed {
          handle.swapAt(.leftMax, with: &removed)
        }
      } else {
        let maxNode = handle.maxValue(.rightMax, .leftMax)
        handle.swapAt(maxNode, with: &removed)
        handle.trickleDownMax(maxNode)
      }
    }

    _checkInvariants()
    return removed
  }

  @inlinable
  public mutating func removeMin() -> Element {
    return popMin()!
  }

  @inlinable
  public mutating func removeMax() -> Element {
    return popMax()!
  }

  @inlinable
  @discardableResult
  public mutating func replaceMin(with replacement: Element) -> Element {
    precondition(!isEmpty, "No element to replace")

    var removed = replacement
    _update { handle in
      let minNode = _Node.root
      handle.swapAt(minNode, with: &removed)
      handle.trickleDownMin(minNode)
    }
    _checkInvariants()
    return removed
  }

  @inlinable
  @discardableResult
  public mutating func replaceMax(with replacement: Element) -> Element {
    precondition(!isEmpty, "No element to replace")

    var removed = replacement
    _update { handle in
      switch handle.count {
      case 1:
        handle.swapAt(.root, with: &removed)
      case 2:
        handle.swapAt(.leftMax, with: &removed)
        handle.bubbleUp(.leftMax)
      default:
        let maxNode = handle.maxValue(.leftMax, .rightMax)
        handle.swapAt(maxNode, with: &removed)
        handle.bubbleUp(maxNode)
        handle.trickleDownMax(maxNode)
      }
    }
    _checkInvariants()
    return removed
  }
}

extension Heap {
  
  @inlinable
  public init(_ elements: S) where S.Element == Element {
    _storage = ContiguousArray(elements)
    guard _storage.count > 1 else { return }

    _update { handle in
      handle.heapify()
    }
    _checkInvariants()
  }

  @inlinable
  public mutating func insert(
    contentsOf newElements: S
  ) where S.Element == Element {
    if count == 0 {
      self = Self(newElements)
      return
    }
    _storage.reserveCapacity(count + newElements.underestimatedCount)
    for element in newElements {
      insert(element)
    }
  }
}

@usableFromInline @frozen
internal struct _Node {
  @usableFromInline
  internal var offset: Int

  @usableFromInline
  internal var level: Int

  @inlinable
  internal init(offset: Int, level: Int) {
    assert(offset >= 0)
#if COLLECTIONS_INTERNAL_CHECKS
    assert(level == Self.level(forOffset: offset))
#endif
    self.offset = offset
    self.level = level
  }

  @inlinable
  internal init(offset: Int) {
    self.init(offset: offset, level: Self.level(forOffset: offset))
  }
}

extension _Node: Comparable {
  @inlinable @inline(__always)
  internal static func ==(left: Self, right: Self) -> Bool {
    left.offset == right.offset
  }

  @inlinable @inline(__always)
  internal static func <(left: Self, right: Self) -> Bool {
    left.offset < right.offset
  }
}

extension _Node: CustomStringConvertible {
  @usableFromInline
  internal var description: String {
    "(offset: \(offset), level: \(level))"
  }
}

extension _Node {
  @inlinable @inline(__always)
  internal static func level(forOffset offset: Int) -> Int {
    (offset &+ 1)._binaryLogarithm()
  }

  @inlinable @inline(__always)
  internal static func firstNode(onLevel level: Int) -> _Node {
    assert(level >= 0)
    return _Node(offset: (1 &<< level) &- 1, level: level)
  }

  @inlinable @inline(__always)
  internal static func lastNode(onLevel level: Int) -> _Node {
    assert(level >= 0)
    return _Node(offset: (1 &<< (level &+ 1)) &- 2, level: level)
  }

  @inlinable @inline(__always)
  internal static func isMinLevel(_ level: Int) -> Bool {
    level & 0b1 == 0
  }
}

extension _Node {
  @inlinable @inline(__always)
  internal static var root: Self {
    Self.init(offset: 0, level: 0)
  }

  @inlinable @inline(__always)
  internal static var leftMax: Self {
    Self.init(offset: 1, level: 1)
  }

  @inlinable @inline(__always)
  internal static var rightMax: Self {
    Self.init(offset: 2, level: 1)
  }

  @inlinable @inline(__always)
  internal var isMinLevel: Bool {
    Self.isMinLevel(level)
  }

  @inlinable @inline(__always)
  internal var isRoot: Bool {
    offset == 0
  }
}

extension _Node {
  @inlinable @inline(__always)
  internal func parent() -> Self {
    assert(!isRoot)
    return Self(offset: (offset &- 1) / 2, level: level &- 1)
  }

  @inlinable @inline(__always)
  internal func grandParent() -> Self? {
    guard offset > 2 else { return nil }
    return Self(offset: (offset &- 3) / 4, level: level &- 2)
  }

  @inlinable @inline(__always)
  internal func leftChild() -> Self {
    Self(offset: offset &* 2 &+ 1, level: level &+ 1)
  }

  @inlinable @inline(__always)
  internal func rightChild() -> Self {
    Self(offset: offset &* 2 &+ 2, level: level &+ 1)
  }

  @inlinable @inline(__always)
  internal func firstGrandchild() -> Self {
    Self(offset: offset &* 4 &+ 3, level: level &+ 2)
  }

  @inlinable @inline(__always)
  internal func lastGrandchild() -> Self {
    Self(offset: offset &* 4 &+ 6, level: level &+ 2)
  }

  @inlinable
  internal static func allNodes(
    onLevel level: Int,
    limit: Int
  ) -> ClosedRange? {
    let first = Self.firstNode(onLevel: level)
    guard first.offset < limit else { return nil }
    var last = self.lastNode(onLevel: level)
    if last.offset >= limit {
      last.offset = limit &- 1
    }
    return ClosedRange(uncheckedBounds: (first, last))
  }
}

extension ClosedRange where Bound == _Node {
  @inlinable @inline(__always)
  internal func _forEach(_ body: (_Node) -> Void) {
    assert(
      isEmpty || _Node.level(forOffset: upperBound.offset) == lowerBound.level)
    var node = self.lowerBound
    while node.offset <= self.upperBound.offset {
      body(node)
      node.offset &+= 1
    }
  }
}

extension Heap {
  #if COLLECTIONS_INTERNAL_CHECKS
  @inlinable
  @inline(never)
  internal func _checkInvariants() {
    guard count > 1 else { return }
    _checkInvariants(node: .root, min: nil, max: nil)
  }

  @inlinable
  internal func _checkInvariants(node: _Node, min: Element?, max: Element?) {
    let value = _storage[node.offset]
    if let min = min {
      precondition(value >= min,
                   "Element \(value) at \(node) is less than min \(min)")
    }
    if let max = max {
      precondition(value <= max,
                   "Element \(value) at \(node) is greater than max \(max)")
    }
    let left = node.leftChild()
    let right = node.rightChild()
    if node.isMinLevel {
      if left.offset < count {
        _checkInvariants(node: left, min: value, max: max)
      }
      if right.offset < count {
        _checkInvariants(node: right, min: value, max: max)
      }
    } else {
      if left.offset < count {
        _checkInvariants(node: left, min: min, max: value)
      }
      if right.offset < count {
        _checkInvariants(node: right, min: min, max: value)
      }
    }
  }
  #else
  @inlinable
  @inline(__always)
  public func _checkInvariants() {}
  #endif
}

extension Heap {
  @usableFromInline @frozen
  struct _UnsafeHandle {
    @usableFromInline
    var buffer: UnsafeMutableBufferPointer

    @inlinable @inline(__always)
    init(_ buffer: UnsafeMutableBufferPointer) {
      self.buffer = buffer
    }
  }

  @inlinable @inline(__always)
  mutating func _update(_ body: (_UnsafeHandle) -> R) -> R {
    _storage.withUnsafeMutableBufferPointer { buffer in
      body(_UnsafeHandle(buffer))
    }
  }
}

extension Heap._UnsafeHandle {
  @inlinable @inline(__always)
  internal var count: Int {
    buffer.count
  }

  @inlinable
  subscript(node: _Node) -> Element {
    @inline(__always)
    get {
      buffer[node.offset]
    }
    @inline(__always)
    nonmutating _modify {
      yield &buffer[node.offset]
    }
  }

  @inlinable @inline(__always)
  internal func ptr(to node: _Node) -> UnsafeMutablePointer {
    assert(node.offset < count)
    return buffer.baseAddress! + node.offset
  }

  @inlinable @inline(__always)
  internal func extract(_ node: _Node) -> Element {
    ptr(to: node).move()
  }

  @inlinable @inline(__always)
  internal func initialize(_ node: _Node, to value: __owned Element) {
    ptr(to: node).initialize(to: value)
  }

  @inlinable @inline(__always)
  internal func swapAt(_ i: _Node, _ j: _Node) {
    buffer.swapAt(i.offset, j.offset)
  }

  @inlinable @inline(__always)
  internal func swapAt(_ i: _Node, with value: inout Element) {
    let p = buffer.baseAddress.unsafelyUnwrapped + i.offset
    swap(&p.pointee, &value)
  }


  @inlinable @inline(__always)
  internal func minValue(_ a: _Node, _ b: _Node) -> _Node {
    self[a] < self[b] ? a : b
  }

  @inlinable @inline(__always)
  internal func maxValue(_ a: _Node, _ b: _Node) -> _Node {
    self[a] < self[b] ? b : a
  }
}

extension Heap._UnsafeHandle {
  @inlinable
  internal func bubbleUp(_ node: _Node) {
    guard !node.isRoot else { return }

    let parent = node.parent()

    var node = node
    if (node.isMinLevel && self[node] > self[parent])
        || (!node.isMinLevel && self[node] < self[parent]){
      swapAt(node, parent)
      node = parent
    }

    if node.isMinLevel {
      while let grandparent = node.grandParent(),
            self[node] < self[grandparent] {
        swapAt(node, grandparent)
        node = grandparent
      }
    } else {
      while let grandparent = node.grandParent(),
            self[node] > self[grandparent] {
        swapAt(node, grandparent)
        node = grandparent
      }
    }
  }
}

extension Heap._UnsafeHandle {
  @inlinable
  internal func trickleDownMin(_ node: _Node) {
    assert(node.isMinLevel)
    var node = node
    var value = extract(node)
    _trickleDownMin(node: &node, value: &value)
    initialize(node, to: value)
  }

  @inlinable @inline(__always)
  internal func _trickleDownMin(node: inout _Node, value: inout Element) {
    var gc0 = node.firstGrandchild()
    while gc0.offset &+ 3 < count {
      let gc1 = _Node(offset: gc0.offset &+ 1, level: gc0.level)
      let minA = minValue(gc0, gc1)

      let gc2 = _Node(offset: gc0.offset &+ 2, level: gc0.level)
      let gc3 = _Node(offset: gc0.offset &+ 3, level: gc0.level)
      let minB = minValue(gc2, gc3)

      let min = minValue(minA, minB)
      guard self[min] < value else {
        return
      }

      initialize(node, to: extract(min))
      node = min
      gc0 = node.firstGrandchild()

      let parent = min.parent()
      if self[parent] < value {
        swapAt(parent, with: &value)
      }
    }

    let c0 = node.leftChild()
    if c0.offset >= count {
      return
    }
    let min = _minDescendant(c0: c0, gc0: gc0)
    guard self[min] < value else {
      return
    }

    initialize(node, to: extract(min))
    node = min

    if min < gc0 { return }

    let parent = min.parent()
    if self[parent] < value {
      initialize(node, to: extract(parent))
      node = parent
    }
  }

  @inlinable
  internal func _minDescendant(c0: _Node, gc0: _Node) -> _Node {
    assert(c0.offset < count)
    assert(gc0.offset + 3 >= count)

    if gc0.offset < count {
      if gc0.offset &+ 2 < count {
        let gc1 = _Node(offset: gc0.offset &+ 1, level: gc0.level)
        let gc2 = _Node(offset: gc0.offset &+ 2, level: gc0.level)
        return minValue(minValue(gc0, gc1), gc2)
      }

      let c1 = _Node(offset: c0.offset &+ 1, level: c0.level)
      let m = minValue(c1, gc0)
      if gc0.offset &+ 1 < count {
        let gc1 = _Node(offset: gc0.offset &+ 1, level: gc0.level)
        return minValue(m, gc1)
      }

      return m
    }

    let c1 = _Node(offset: c0.offset &+ 1, level: c0.level)
    if c1.offset < count {
      return minValue(c0, c1)
    }

    return c0
  }

  @inlinable
  internal func trickleDownMax(_ node: _Node) {
    assert(!node.isMinLevel)
    var node = node
    var value = extract(node)

    _trickleDownMax(node: &node, value: &value)
    initialize(node, to: value)
  }

  @inlinable @inline(__always)
  internal func _trickleDownMax(node: inout _Node, value: inout Element) {
    var gc0 = node.firstGrandchild()
    while gc0.offset &+ 3 < count {
      let gc1 = _Node(offset: gc0.offset &+ 1, level: gc0.level)
      let maxA = maxValue(gc0, gc1)

      let gc2 = _Node(offset: gc0.offset &+ 2, level: gc0.level)
      let gc3 = _Node(offset: gc0.offset &+ 3, level: gc0.level)
      let maxB = maxValue(gc2, gc3)

      let max = maxValue(maxA, maxB)
      guard value < self[max] else {
        return
      }

      initialize(node, to: extract(max))
      node = max
      gc0 = node.firstGrandchild()

      let parent = max.parent()
      if value < self[parent] {
        swapAt(parent, with: &value)
      }
    }

    let c0 = node.leftChild()
    if c0.offset >= count {
      return
    }
    let max = _maxDescendant(c0: c0, gc0: gc0)
    guard value < self[max] else {
      return
    }

    initialize(node, to: extract(max))
    node = max

    if max < gc0 { return }

    let parent = max.parent()
    if value < self[parent] {
      initialize(node, to: extract(parent))
      node = parent
    }
  }

  @inlinable
  internal func _maxDescendant(c0: _Node, gc0: _Node) -> _Node {
    assert(c0.offset < count)
    assert(gc0.offset + 3 >= count)

    if gc0.offset < count {
      if gc0.offset &+ 2 < count {
        let gc1 = _Node(offset: gc0.offset &+ 1, level: gc0.level)
        let gc2 = _Node(offset: gc0.offset &+ 2, level: gc0.level)
        return maxValue(maxValue(gc0, gc1), gc2)
      }

      let c1 = _Node(offset: c0.offset &+ 1, level: c0.level)
      let m = maxValue(c1, gc0)
      if gc0.offset &+ 1 < count {
        let gc1 = _Node(offset: gc0.offset &+ 1, level: gc0.level)
        return maxValue(m, gc1)
      }

      return m
    }

    let c1 = _Node(offset: c0.offset &+ 1, level: c0.level)
    if c1.offset < count {
      return maxValue(c0, c1)
    }

    return c0
  }
}

extension Heap._UnsafeHandle {
  @inlinable
  internal func heapify() {

    let limit = count / 2 // The first offset without a left child
    var level = _Node.level(forOffset: limit &- 1)
    while level >= 0 {
      let nodes = _Node.allNodes(onLevel: level, limit: limit)
      _heapify(level, nodes)
      level &-= 1
    }
  }

  @inlinable
  internal func _heapify(_ level: Int, _ nodes: ClosedRange<_Node>?) {
    guard let nodes = nodes else { return }
    if _Node.isMinLevel(level) {
      nodes._forEach { node in
        trickleDownMin(node)
      }
    } else {
      nodes._forEach { node in
        trickleDownMax(node)
      }
    }
  }
}