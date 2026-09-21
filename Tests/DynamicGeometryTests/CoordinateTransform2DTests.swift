import Foundation
import Testing

@testable import DynamicGeometry

@Suite("Coordinate transforms")
struct CoordinateTransform2DTests {
  @Test("Identity preserves points and vectors")
  func identityPreservesGeometry() throws {
    let point = Point2D(x: 3, y: -4)
    let vector = Vector2D(x: -2, y: 5)

    #expect(try CoordinateTransform2D.identity.transform(point) == point)
    #expect(try CoordinateTransform2D.identity.transform(vector) == vector)
  }

  @Test("Translation moves points but does not change vectors")
  func translationIgnoresVectors() throws {
    let transform = try CoordinateTransform2D.translation(x: 10, y: -3)

    #expect(
      try transform.transform(Point2D(x: 2, y: 5))
        == Point2D(x: 12, y: 2))
    #expect(
      try transform.transform(Vector2D(x: 2, y: 5))
        == Vector2D(x: 2, y: 5))
  }

  @Test("Uniform and non-uniform scales affect each axis")
  func scalesAxes() throws {
    let point = Point2D(x: 3, y: -4)

    #expect(
      try CoordinateTransform2D.scale(2).transform(point)
        == Point2D(x: 6, y: -8))
    #expect(
      try CoordinateTransform2D.scale(x: 2, y: 0.5).transform(point)
        == Point2D(x: 6, y: -2))
  }

  @Test("Positive rotation turns the positive x-axis toward the positive y-axis")
  func rotatesCoordinates() throws {
    let quarterTurn = try CoordinateTransform2D.rotation(radians: .pi / 2)
    let point = try quarterTurn.transform(Point2D(x: 4, y: 0))

    #expect(isClose(point.x, 0))
    #expect(isClose(point.y, 4))
  }

  @Test("Composition applies the receiver before the following transform")
  func compositionOrderIsExplicit() throws {
    let scale = try CoordinateTransform2D.scale(x: 2, y: 3)
    let translation = try CoordinateTransform2D.translation(x: 10, y: -1)
    let point = Point2D(x: 1, y: 2)

    let scaleThenTranslate = try scale.followed(by: translation)
    let translateThenScale = try translation.followed(by: scale)

    #expect(try scaleThenTranslate.transform(point) == Point2D(x: 12, y: 5))
    #expect(try translateThenScale.transform(point) == Point2D(x: 22, y: 3))
  }

  @Test("An invertible transform round-trips points and vectors")
  func inverseRoundTrip() throws {
    let scale = try CoordinateTransform2D.scale(x: 2, y: 0.5)
    let rotation = try CoordinateTransform2D.rotation(radians: .pi / 3)
    let translation = try CoordinateTransform2D.translation(x: 8, y: -11)
    let transform = try scale.followed(by: rotation).followed(by: translation)
    let inverse = try transform.inverted()
    let point = Point2D(x: 7, y: -9)
    let vector = Vector2D(x: -4, y: 12)

    let roundTripPoint = try inverse.transform(transform.transform(point))
    let roundTripVector = try inverse.transform(transform.transform(vector))

    #expect(isClose(roundTripPoint.x, point.x))
    #expect(isClose(roundTripPoint.y, point.y))
    #expect(isClose(roundTripVector.x, vector.x))
    #expect(isClose(roundTripVector.y, vector.y))
  }

  @Test("A singular transform reports a typed inversion error")
  func singularInverseFails() throws {
    let flattened = try CoordinateTransform2D.scale(x: 1, y: 0)

    #expect(throws: CoordinateTransformError.singularTransform) {
      try flattened.inverted()
    }
  }

  @Test("Non-finite transforms and geometry are rejected")
  func nonFiniteValuesFail() throws {
    #expect(throws: CoordinateTransformError.nonFiniteTransform) {
      try CoordinateTransform2D.translation(x: .infinity, y: 0)
    }

    #expect(throws: CoordinateTransformError.nonFinitePoint) {
      try CoordinateTransform2D.identity.transform(Point2D(x: .nan, y: 0))
    }

    #expect(throws: CoordinateTransformError.nonFiniteVector) {
      try CoordinateTransform2D.identity.transform(Vector2D(x: 0, y: -.infinity))
    }

    let inverseWouldOverflow = try CoordinateTransform2D.scale(
      x: .leastNonzeroMagnitude,
      y: 1)
    #expect(throws: CoordinateTransformError.nonFiniteTransform) {
      try inverseWouldOverflow.inverted()
    }
  }

  @Test("Transforms preserve all coefficients through Codable")
  func codableRoundTrip() throws {
    let transform = try CoordinateTransform2D(
      m11: 1,
      m12: 2,
      m21: 3,
      m22: 4,
      translationX: 5,
      translationY: 6)

    let data = try JSONEncoder().encode(transform)
    let decoded = try JSONDecoder().decode(CoordinateTransform2D.self, from: data)

    #expect(decoded == transform)
  }
}

private func isClose(_ first: Double, _ second: Double, tolerance: Double = 0.000_000_1) -> Bool {
  abs(first - second) <= tolerance
}
