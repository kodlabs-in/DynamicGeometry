import Foundation
import Testing

@testable import DynamicGeometry

@Suite("Geometry primitives")
struct GeometryPrimitiveTests {
  @Test("A circle and ellipse retain different geometric meanings")
  func circleAndEllipseAreDistinct() throws {
    let center = Point2D(x: 10, y: 20)
    let circle = try Circle2D(center: center, radius: 40)
    let ellipse = try Ellipse2D(center: center, radiusX: 40, radiusY: 20)

    #expect(circle.radius == 40)
    #expect(ellipse.radiusX == 40)
    #expect(ellipse.radiusY == 20)
  }

  @Test("Cartesian angles use an upward positive y-axis")
  func cartesianCirclePoint() throws {
    let circle = try Circle2D(center: Point2D(x: 100, y: 100), radius: 50)
    let point = try circle.point(at: .pi / 2)

    #expect(isClose(point.x, 100))
    #expect(isClose(point.y, 150))
  }

  @Test("Screen angles place positive sine above the centre")
  func screenCirclePoint() throws {
    let circle = try Circle2D(center: Point2D(x: 100, y: 100), radius: 50)
    let point = try circle.point(at: .pi / 2, coordinateSystem: .screenYDown)

    #expect(isClose(point.x, 100))
    #expect(isClose(point.y, 50))
  }

  @Test("Angles normalize into one positive turn")
  func normalizesAngles() {
    #expect(isClose(Circle2D.normalizedAngle(-.pi / 2), 3 * .pi / 2))
    #expect(isClose(Circle2D.normalizedAngle(5 * .pi), .pi))
  }

  @Test("Degenerate directions are rejected")
  func rejectsCoincidentLinePoints() {
    let point = Point2D(x: 4, y: 8)

    #expect(throws: GeometryError.undefinedDirection) {
      try Line2D(first: point, second: point)
    }
    #expect(throws: GeometryError.undefinedDirection) {
      try Ray2D(origin: point, through: point)
    }
  }

  @Test("Decoding cannot bypass primitive validation")
  func validatesDecodedPrimitives() {
    let invalidEllipse = Data(
      #"{"center":{"x":0,"y":0},"radiusX":40,"radiusY":0}"#.utf8)
    let coincidentLine = Data(
      #"{"first":{"x":4,"y":8},"second":{"x":4,"y":8}}"#.utf8)

    #expect(throws: GeometryError.nonPositiveDimension("Ellipse radius")) {
      try JSONDecoder().decode(Ellipse2D.self, from: invalidEllipse)
    }
    #expect(throws: GeometryError.undefinedDirection) {
      try JSONDecoder().decode(Line2D.self, from: coincidentLine)
    }
  }
}

@Suite("Dependency-aware scenes")
struct GeometrySceneTests {
  @Test("A unit-circle construction resolves its dependent geometry")
  func resolvesUnitCircleConstruction() throws {
    var scene = GeometryScene(coordinateSystem: .screenYDown)
    let center = try scene.addPoint(.free(Point2D(x: 200, y: 200)))
    let circle = try scene.addCircle(center: center, radius: 100)
    let movingPoint = try scene.addPoint(
      .onCircle(circle: circle, angleRadians: .pi / 4))
    let horizontalProjection = try scene.addPoint(
      .horizontalProjection(of: movingPoint, ontoY: 200))
    let verticalProjection = try scene.addPoint(
      .verticalProjection(of: movingPoint, ontoX: 200))
    let radius = try scene.addSegment(start: center, end: movingPoint)

    let point = try scene.point(movingPoint)
    let horizontal = try scene.point(horizontalProjection)
    let vertical = try scene.point(verticalProjection)

    #expect(isClose(point.x, 200 + 100 / sqrt(2)))
    #expect(isClose(point.y, 200 - 100 / sqrt(2)))
    #expect(horizontal == Point2D(x: point.x, y: 200))
    #expect(vertical == Point2D(x: 200, y: point.y))
    #expect(isClose(try scene.segment(radius).length, 100))
  }

  @Test("Dragging a constrained point projects it onto its circle")
  func movesPointOnCircle() throws {
    var scene = GeometryScene(coordinateSystem: .screenYDown)
    let center = try scene.addPoint(.free(Point2D(x: 100, y: 100)))
    let circle = try scene.addCircle(center: center, radius: 50)
    let movingPoint = try scene.addPoint(.onCircle(circle: circle, angleRadians: 0))

    try scene.movePoint(movingPoint, to: Point2D(x: 100, y: -500))

    let resolved = try scene.point(movingPoint)
    #expect(isClose(resolved.x, 100))
    #expect(isClose(resolved.y, 50))
    guard case .point(.onCircle(_, let angle)) = scene.entity(movingPoint) else {
      Issue.record("Expected a circle-constrained point")
      return
    }
    #expect(isClose(angle, .pi / 2))
  }

  @Test("Moving a free centre updates its circle and dependent point")
  func movesDependencyRoot() throws {
    var scene = GeometryScene()
    let center = try scene.addPoint(.free(Point2D(x: 0, y: 0)))
    let circle = try scene.addCircle(center: center, radius: 10)
    let point = try scene.addPoint(.onCircle(circle: circle, angleRadians: 0))

    try scene.movePoint(center, to: Point2D(x: 40, y: 50))

    #expect(try scene.circle(circle).center == Point2D(x: 40, y: 50))
    #expect(try scene.point(point) == Point2D(x: 50, y: 50))
  }

  @Test("Derived projections cannot be moved directly")
  func derivedPointIsReadOnly() throws {
    var scene = GeometryScene()
    let source = try scene.addPoint(.free(Point2D(x: 5, y: 8)))
    let projection = try scene.addPoint(.horizontalProjection(of: source, ontoY: 0))

    #expect(throws: GeometryError.readOnlyPoint(projection)) {
      try scene.movePoint(projection, to: Point2D(x: 20, y: 20))
    }
  }

  @Test("Multiple overlapping entities remain independent")
  func preservesOverlappingEntities() throws {
    var scene = GeometryScene()
    let center = try scene.addPoint(.free(Point2D(x: 50, y: 50)))
    let first = try scene.addCircle(center: center, radius: 25)
    let second = try scene.addCircle(center: center, radius: 25)

    #expect(first != second)
    #expect(try scene.circle(first) == scene.circle(second))
    #expect(scene.orderedIDs == [center, first, second])
  }

  @Test("Missing dependencies reject insertion without poisoning the scene")
  func rejectsMissingDependency() throws {
    var scene = GeometryScene()
    let missing = GeometryID()

    #expect(throws: GeometryError.missingEntity(missing)) {
      try scene.addCircle(center: missing, radius: 10)
    }
    #expect(scene.orderedIDs.isEmpty)
    try scene.validate()
  }

  @Test("Cycles reject replacement and restore the previous entity")
  func rejectsDependencyCycle() throws {
    var scene = GeometryScene()
    let first = try scene.addPoint(.free(Point2D(x: 1, y: 2)))
    let second = try scene.addPoint(.horizontalProjection(of: first, ontoY: 0))

    #expect(throws: GeometryError.cyclicDependency(first)) {
      try scene.replace(first, with: .point(.verticalProjection(of: second, ontoX: 0)))
    }
    #expect(try scene.point(first) == Point2D(x: 1, y: 2))
  }

  @Test("Referenced entities cannot be removed")
  func rejectsRemovingDependency() throws {
    var scene = GeometryScene()
    let center = try scene.addPoint(.free(Point2D(x: 0, y: 0)))
    let circle = try scene.addCircle(center: center, radius: 1)

    #expect(throws: GeometryError.missingEntity(center)) {
      try scene.remove(center)
    }
    #expect(try scene.circle(circle).center == Point2D(x: 0, y: 0))
  }

  @Test("Scenes round-trip with stable entity identity and order")
  func codableRoundTrip() throws {
    var scene = GeometryScene(coordinateSystem: .screenYDown)
    let center = try scene.addPoint(.free(Point2D(x: 10, y: 20)))
    _ = try scene.addEllipse(center: center, radiusX: 40, radiusY: 20)
    let circle = try scene.addCircle(center: center, radius: 30)
    let point = try scene.addPoint(.onCircle(circle: circle, angleRadians: .pi))
    _ = try scene.addRay(origin: center, through: point)

    let data = try JSONEncoder().encode(scene)
    let decoded = try JSONDecoder().decode(GeometryScene.self, from: data)

    #expect(decoded == scene)
    try decoded.validate()
  }

  @Test("Non-finite input is rejected at the scene boundary")
  func rejectsNonFiniteGeometry() {
    var scene = GeometryScene()

    #expect(throws: GeometryError.nonFiniteValue("Point")) {
      try scene.addPoint(.free(Point2D(x: .nan, y: 0)))
    }
    #expect(scene.orderedIDs.isEmpty)
  }

  @Test("A segment, line, and ray can share the same base points")
  func composesBaseShapes() throws {
    var scene = GeometryScene()
    let first = try scene.addPoint(.free(Point2D(x: 0, y: 0)))
    let second = try scene.addPoint(.free(Point2D(x: 3, y: 4)))
    let segment = try scene.addSegment(start: first, end: second)
    let line = try scene.addLine(first: first, second: second)
    let ray = try scene.addRay(origin: first, through: second)

    #expect(try scene.segment(segment).length == 5)
    #expect(try scene.line(line).direction == Vector2D(x: 3, y: 4))
    #expect(try scene.ray(ray).direction == Vector2D(x: 3, y: 4))
  }
}

private func isClose(_ first: Double, _ second: Double, tolerance: Double = 0.000_000_1) -> Bool {
  abs(first - second) <= tolerance
}
