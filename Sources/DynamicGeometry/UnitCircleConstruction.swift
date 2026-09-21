/// Stable identifiers for a reusable unit-circle construction.
public struct UnitCircleConstruction: Codable, Equatable, Sendable {
  /// Shared radius parameter used by the circle definition.
  public let radiusParameterID: ScalarParameterID

  /// Shared angle parameter used by the constrained point definition.
  public let angleParameterID: ScalarParameterID

  /// Free point at the construction's origin.
  public let centerID: GeometryID

  /// Circle driven by ``radiusParameterID``.
  public let circleID: GeometryID

  /// Point constrained to ``circleID`` by ``angleParameterID``.
  public let movingPointID: GeometryID

  /// Point projecting ``movingPointID`` onto the horizontal axis.
  public let horizontalProjectionID: GeometryID

  /// Point projecting ``movingPointID`` onto the vertical axis.
  public let verticalProjectionID: GeometryID

  /// Segment from the centre to the constrained point.
  public let radiusSegmentID: GeometryID

  /// Segment visualizing the horizontal projection.
  public let horizontalProjectionSegmentID: GeometryID

  /// Segment visualizing the vertical projection.
  public let verticalProjectionSegmentID: GeometryID

  /// Atomically inserts a parameter-driven unit-circle recipe into a scene.
  public static func insert(
    into scene: inout GeometryScene,
    center: Point2D = Point2D(x: 0, y: 0),
    radius: Double = 1,
    angleRadians: Double = .pi / 4
  ) throws -> Self {
    _ = try Circle2D(center: center, radius: radius)
    guard angleRadians.isFinite else {
      throw GeometryError.nonFiniteValue("Angle")
    }

    var updated = scene
    let radiusParameterID = try updated.addParameter(name: "radius", value: radius)
    let angleParameterID = try updated.addParameter(name: "theta", value: angleRadians)
    let centerID = try updated.addPoint(.free(center))
    let circleID = try updated.addCircle(
      center: centerID,
      radius: .parameter(.identified(radiusParameterID)))
    let movingPointID = try updated.addPoint(
      .onCircleExpression(
        circle: circleID,
        angleRadians: .parameter(.identified(angleParameterID))))
    let horizontalProjectionID = try updated.addPoint(
      .horizontalProjectionExpression(of: movingPointID, ontoY: .constant(center.y)))
    let verticalProjectionID = try updated.addPoint(
      .verticalProjectionExpression(of: movingPointID, ontoX: .constant(center.x)))
    let radiusSegmentID = try updated.addSegment(start: centerID, end: movingPointID)
    let horizontalProjectionSegmentID = try updated.addSegment(
      start: movingPointID,
      end: horizontalProjectionID)
    let verticalProjectionSegmentID = try updated.addSegment(
      start: movingPointID,
      end: verticalProjectionID)

    let construction = Self(
      radiusParameterID: radiusParameterID,
      angleParameterID: angleParameterID,
      centerID: centerID,
      circleID: circleID,
      movingPointID: movingPointID,
      horizontalProjectionID: horizontalProjectionID,
      verticalProjectionID: verticalProjectionID,
      radiusSegmentID: radiusSegmentID,
      horizontalProjectionSegmentID: horizontalProjectionSegmentID,
      verticalProjectionSegmentID: verticalProjectionSegmentID)
    scene = updated
    return construction
  }

  /// Changes the shared angle parameter and reports the affected geometry branch.
  @discardableResult
  public func setAngle(
    in scene: inout GeometryScene,
    to angleRadians: Double
  ) throws -> GeometrySceneChange {
    try scene.setParameter(angleParameterID, to: angleRadians)
  }

  /// Changes the shared radius parameter and reports the affected geometry branch.
  @discardableResult
  public func setRadius(
    in scene: inout GeometryScene,
    to radius: Double
  ) throws -> GeometrySceneChange {
    try scene.setParameter(radiusParameterID, to: radius)
  }

  /// Projects a drag location onto the circle through the scene's constraint engine.
  @discardableResult
  public func movePoint(
    in scene: inout GeometryScene,
    to target: Point2D
  ) throws -> GeometrySceneChange {
    try scene.movePointReportingChanges(movingPointID, to: target)
  }

  /// Resolves the current geometry and normalized trigonometric values.
  public func snapshot(in scene: GeometryScene) throws -> UnitCircleSnapshot {
    guard let radius = scene.parameter(radiusParameterID)?.value,
      let angleRadians = scene.parameter(angleParameterID)?.value
    else {
      throw GeometryError.inconsistentScene
    }
    let center = try scene.point(centerID)
    let movingPoint = try scene.point(movingPointID)
    let verticalDirection = scene.coordinateSystem == .cartesian ? 1.0 : -1.0
    return UnitCircleSnapshot(
      center: center,
      movingPoint: movingPoint,
      horizontalProjection: try scene.point(horizontalProjectionID),
      verticalProjection: try scene.point(verticalProjectionID),
      radius: radius,
      angleRadians: angleRadians,
      cosine: (movingPoint.x - center.x) / radius,
      sine: verticalDirection * (movingPoint.y - center.y) / radius)
  }
}

/// Resolved values displayed by a unit-circle learning experience.
public struct UnitCircleSnapshot: Equatable, Sendable {
  /// Current resolved centre.
  public let center: Point2D

  /// Current resolved constrained point.
  public let movingPoint: Point2D

  /// Current projection onto the horizontal axis.
  public let horizontalProjection: Point2D

  /// Current projection onto the vertical axis.
  public let verticalProjection: Point2D

  /// Current positive circle radius.
  public let radius: Double

  /// Current continuous angle in radians.
  public let angleRadians: Double

  /// Normalized horizontal coordinate relative to the circle.
  public let cosine: Double

  /// Normalized mathematical vertical coordinate relative to the circle.
  public let sine: Double

  /// Current angle converted from radians to degrees.
  public var angleDegrees: Double {
    angleRadians * 180 / .pi
  }
}
