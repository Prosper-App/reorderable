import SwiftUI

/// A view that arranges its subviews in a line and allows reordering of its elements by drag and dropping.
///
/// Note that this doesn't participate in iOS standard drag-and-drop mechanism and thus dragged elements can't be dropped into other views modified with `.onDrop`.
@available(iOS 18.0, macOS 15.0, *)
package struct ReorderableStack<Axis: ContainerAxis, Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable, Data.Index == Int {

  /// Creates a reorderable stack that computes its rows on demand from an underlying collection of identifiable data, with the added information of whether the user is currently dragging the element.
  ///
  /// - Parameters:
  ///   - data: A collection of identifiable data for computing the stack
  ///   - onMove: A callback triggered whenever two elements had their positions switched
  ///   - content: A view builder that creates the view for a single element of the list, with an extra boolean parameter indicating whether the user is currently dragging the element.
  ///   -
  package init(_ data: Data, coordinateSpaceName: String, onMove: @escaping (Int, Int) -> Void, content: @escaping (Data.Element, Bool) -> Content) {
    self.data = data
    self.idToIndex = Dictionary(uniqueKeysWithValues: data.enumerated().map { ($1.id, $0) })
    self.coordinateSpaceName = coordinateSpaceName
    self.onMove = onMove
    self.content = content
  }

  /// Creates a reorderable stack that computes its rows on demand from an underlying collection of identifiable data.
  ///
  /// - Parameters:
  ///   - data: A collection of identifiable data for computing the stack
  ///   - onMove: A callback triggered whenever two elements had their positions switched
  ///   - content: A view builder that creates the view for a single element of the list.
  package init(_ data: Data, coordinateSpaceName: String, onMove: @escaping (Int, Int) -> Void, @ViewBuilder content: @escaping (Data.Element) -> Content) {
    self.data = data
    self.idToIndex = Dictionary(uniqueKeysWithValues: data.enumerated().map { ($1.id, $0) })
    self.coordinateSpaceName = coordinateSpaceName
    self.onMove = onMove
    self.content = { datum, _ in content(datum) }
  }

  var data: Data

  /// Precomputed ID-to-index mapping for O(1) index lookups.
  /// Replaces the previous `dataKeys` Set and eliminates all `firstIndex(where:)` calls.
  private let idToIndex: [Data.Element.ID: Int]

  let onMove: (_ from: Int, _ to: Int) -> Void
  @ViewBuilder var content: (_ data: Data.Element, _ isDragged: Bool) -> Content
  let coordinateSpaceName: String

  /// Contains the positions of all elements.
  @State private var positions: [Data.Element.ID: Axis.Position] = [:]

  /// This contains both drag and scroll offsets for rendering
  @State private var displayOffset: CGFloat = 0

  /// The ID of the element being dragged. Nil if nothing is being dragged.
  @State private var dragging: Data.Element.ID? = nil

  /// These two properties are used to compute the offset due to changing the position while dragging.
  @State private var initialIndex: Data.Index? = nil
  @State private var currentIndex: Data.Index? = nil

  /// The ID of the last element that switched position with the dragged element.
  ///
  /// This property is so that we can prevent some hysteresis from hovering over the child we just switched to.
  @State private var lastChange: Data.Element.ID? = nil

  /// The ID of the element that has just been dropped and is animating into its final position.
  ///
  /// We keep track of this so that we can adjust its Z index while its animating. Else, the element might be hidden while it animates back in place.
  @State private var pendingDrop: Data.Element.ID? = nil

  @Environment(\.autoScrollContainerAttributes) private var scrollContainer: AutoScrollContainerAttributes?

  @Environment(\.dragDisabled) private var dragDisabled: Bool

  @Environment(\.disableSensoryFeedback) private var feedbackDisabled: Bool

  /// Timer used to continually scroll when dragging an element close to the top. We use this rather than an animation because SwiftUI doesn't allow configuring the `ContentOffsetChanged` animation.
  @State private var scrollTimer: Timer?

  /// This is the position of the drag in the ScrollView coordinate space. This is used to prevent some jiggling that can happen with the timer and the drag action.
  @State private var scrollViewDragLocation: CGFloat? = nil

  public var body: some View {
    ForEach(data) { datum in
      content(datum, datum.id == dragging)
        .onGeometryChange(for: CGRect.self) { [coordinateSpaceName] proxy in
          proxy.frame(in: .named(coordinateSpaceName))
        } action: { frame in
          positions[datum.id] = Axis.Position(frame)
        }
        .dragHandle()
        .offset(Axis.asSize(value: offsetFor(id: datum.id)))
        .zIndex(datum.id == dragging || datum.id == pendingDrop ? 10 : 0)
        .environment(\.reorderableDragCallback, DragCallbacks(
          onDrag: { dragCallback($0, $1, datum) },
          onDrop: { dropCallback($0, datum) },
          dragCoordinatesSpaceName: coordinateSpaceName,
          isEnabled: !dragDisabled))
        .onDisappear {
          positions.removeValue(forKey: datum.id)
        }
    }
    .sensoryFeedback(trigger: currentIndex) { old, new in
      guard !feedbackDisabled else { return nil }
      switch (old, new) {
        case (.none, .some(_)): return .selection
        case (.some(_), .none): return .selection
        case (.some(_), .some(_)): return .impact(weight: .light)
        default: return nil
      }
    }
  }

  /// The offset of the dragged item due to it having changed position.
  ///
  /// We need this since we're using the drag offset to render the element while were dragging it. The problem is that the element changes location while we're dragging it, but the origin of the drag remains the same.
  private var positionOffset: CGFloat {
    guard let d = dragging,
          let currentIdx = idToIndex[d],
          let initIdx = initialIndex
    else {
      return 0
    }

    if currentIdx > initIdx {
      return data[initIdx..<currentIdx].reduce(0.0) { result, element in
        guard let pos = positions[element.id], idToIndex[element.id] != nil else { return result }
        return result - pos.span
      }
    } else if currentIdx < initIdx {
      return data[currentIdx + 1 ... initIdx].reduce(0.0) { result, element in
        guard let pos = positions[element.id], idToIndex[element.id] != nil else { return result }
        return result + pos.span
      }
    }

    return 0.0
  }

  private func offsetFor(id: Data.Element.ID) -> CGFloat {
    guard id == dragging else { return 0.0 }
    return displayOffset + positionOffset
  }

  /// Checks whether we're dragging an element to the edge of the container and starts scrolling if so.
  private func edgeCheck(_ stackDrag: DragGesture.Value, _ scrollDrag: DragGesture.Value) -> Void {
    guard let pos = scrollContainer?.position,
          let bounds = scrollContainer?.bounds,
          let scrollContentBounds = scrollContainer?.contentBounds,
          let scrollContainerOffset = scrollContainer?.offset
    else {
      return
    }

    let bumperSize = 52.0
    let scrollSpeed = 5.0
    let timerInterval = 1.0 / 60.0

    let scrollEnd = Axis.project(size: scrollContentBounds) - Axis.project(size: bounds)
    let scrollDragPos = Axis.project(point: scrollDrag.location)

    if (scrollDragPos <= bumperSize && Axis.project(maybePoint: pos.wrappedValue.point) ?? 1.0 > 0) {
      if (scrollTimer == nil) {
        var scrollOffset = Axis.project(point: scrollContainerOffset)
        var dragPos = Axis.project(point: stackDrag.location)

        scrollTimer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { _ in
          Task { @MainActor in
            pos.wrappedValue.scrollTo(point: Axis.asPoint(value: scrollOffset))

            checkIntersection(position: dragPos, dragged: dragging)
            scrollOffset -= scrollSpeed
            dragPos -= scrollSpeed


            if (Axis.project(maybePoint: pos.wrappedValue.point) ?? 0.0 <= 0) {
              scrollTimer?.invalidate()
              scrollTimer = nil
            } else {
              // Put this after the check to avoid unecessary jiggle when at the top.
              displayOffset -= scrollSpeed
            }
          }
        }
      }
    } else if (scrollDragPos >= Axis.project(size: bounds) - bumperSize && Axis.project(maybePoint: pos.wrappedValue.point) ?? 0.0 < scrollEnd) {
      if (scrollTimer == nil) {
        var scrollOffset = Axis.project(point: scrollContainerOffset)
        var dragPos = Axis.project(point: stackDrag.location)

        scrollTimer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true) { _ in
          Task { @MainActor in
            pos.wrappedValue.scrollTo(point: Axis.asPoint(value: scrollOffset))

            checkIntersection(position: dragPos, dragged: dragging)
            scrollOffset += scrollSpeed
            dragPos += scrollSpeed

            if (Axis.project(maybePoint: pos.wrappedValue.point) ?? Axis.project(size: bounds) >= scrollEnd) {
              scrollTimer?.invalidate()
              scrollTimer = nil
            } else {
              // Put this after the check to avoid unecessary jiggle when at the top.
              displayOffset += scrollSpeed
            }
          }
        }
      }
    } else {
      if (scrollTimer != nil) {
        scrollTimer?.invalidate()
        scrollTimer = nil
      }
    }
  }

  private func dragCallback(_ stackDrag: DragGesture.Value, _ scrollDrag: DragGesture.Value, _ datum: Data.Element) {

    if (scrollViewDragLocation == nil) {
      scrollViewDragLocation = Axis.project(point: scrollDrag.location)
    }

    if scrollTimer != nil, let lastScrollDragLocation = scrollViewDragLocation {
      if abs(lastScrollDragLocation - Axis.project(point: scrollDrag.location)) > 0.0 {
        displayOffset = Axis.project(size: stackDrag.translation)
      }
    } else {
      displayOffset = Axis.project(size: stackDrag.translation)
    }

    currentIndex = idToIndex[datum.id]
    if (dragging == nil) {
      dragging = datum.id
      initialIndex = currentIndex
    }

    checkIntersection(position: Axis.project(point: stackDrag.location), dragged: datum.id)
    scrollViewDragLocation = Axis.project(point: scrollDrag.location)

    edgeCheck(stackDrag, scrollDrag)
  }

  /// Checks whether the given position intersects with any elements and switch its position with the dragged element if so.
  private func checkIntersection(position: CGFloat, dragged: Data.Element.ID?) {
    guard let datumId = dragged,
          let dragIdx = idToIndex[datumId] else { return }

    // Check neighbors first (most common swap case), then fall back to full scan for fast drags
    var foundKey: Data.Element.ID? = nil
    var foundValue: Axis.Position? = nil

    if dragIdx > 0 {
      let prev = data[dragIdx - 1]
      if let pos = positions[prev.id], idToIndex[prev.id] != nil, pos.contains(position) {
        foundKey = prev.id
        foundValue = pos
      }
    }

    if foundKey == nil, dragIdx < data.count - 1 {
      let next = data[dragIdx + 1]
      if let pos = positions[next.id], idToIndex[next.id] != nil, pos.contains(position) {
        foundKey = next.id
        foundValue = pos
      }
    }

    // Fall back to scanning all elements for fast drags that skip neighbors
    if foundKey == nil {
      for element in data where element.id != datumId {
        if let pos = positions[element.id], idToIndex[element.id] != nil, pos.contains(position) {
          foundKey = element.id
          foundValue = pos
          break
        }
      }
    }

    guard let elementKey = foundKey, let elementValue = foundValue else {
      lastChange = nil
      return
    }

    guard let currentIdx = idToIndex[datumId],
          let targetIdx = idToIndex[elementKey] else { return }

    if (lastChange == elementKey && notAtOtherEdge(currentIndex: currentIdx, elementKey: elementKey, elementValue: elementValue, position: position)) {
      return
    } else {
      lastChange = elementKey
    }

    onMove(currentIdx, targetIdx)

    currentIndex = targetIdx
  }

  /// Whether the user is currently hovering over the opposite side (i.e. the bottom edge of the element below or the top edge of the element above) of the given element.
  ///
  /// This is to help with the hysteresis cases where the user wants to switch back to the position the element was even though that they're still hovering over the previous element after changing spot.
  private func notAtOtherEdge(currentIndex: Int, elementKey: Data.Element.ID, elementValue: Axis.Position, position: CGFloat) -> Bool {
    let edgeBumperSize = 64.0

    guard let otherIndex = idToIndex[elementKey] else { return true }
    if (currentIndex > otherIndex) {
      if (position < elementValue.min + edgeBumperSize && position > elementValue.min) {
        return false
      }
    } else {
      if (position > elementValue.max - edgeBumperSize && position < elementValue.max) {
        return false
      }
    }

    return true
  }

  private func dropCallback(_ drag: DragGesture.Value, _ datum: Data.Element) {
    scrollTimer?.invalidate()
    scrollTimer = nil
    scrollViewDragLocation = nil

    withAnimation {
      pendingDrop = dragging
      lastChange = nil
      dragging = nil
      displayOffset = 0
      currentIndex = nil
    } completion: {
      pendingDrop = nil
    }
  }
}
