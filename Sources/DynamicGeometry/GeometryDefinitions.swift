/// A point's independent coordinates or its relationship to other scene entities.
public enum PointDefinition: Codable, Equatable, Sendable {
  /// A point that can move anywhere in the scene.
  case free(Point2D)

  /// A point constrained to a circle at a stored angle.
  case onCircle(circle: GeometryID, angleRadians: Double)

  /// A derived point sharing another point's x-coordinate at a fixed y-coordinate.
  case horizontalProjection(of: GeometryID, ontoY: Double)

  /// A derived point sharing another point's y-coordinate at a fixed x-coordinate.
  case verticalProjection(of: GeometryID, ontoX: Double)
}

/// A circle whose centre is supplied by another point entity.
public struct CircleDefinition: Codable, Equatable, Sendable {
  /// The identifier of the centre point.
  public let center: GeometryID

  /// The circle radius.
  public let radius: Double

  /// Creates a circle definition.
  public init(center: GeometryID, radius: Double) {
    self.center = center
    self.radius = radius
  }
}

/// An ellipse whose centre is supplied by another point entity.
public struct EllipseDefinition: Codable, Equatable, Sendable {
  /// The identifier of the centre point.
  public let center: GeometryID

  /// The horizontal radius.
  public let radiusX: Double

  /// The vertical radius.
  public let radiusY: Double

  /// Creates an ellipse definition.
  public init(center: GeometryID, radiusX: Double, radiusY: Double) {
    self.center = center
    self.radiusX = radiusX
    self.radiusY = radiusY
  }
}

/// A segment whose endpoints are supplied by point entities.
public struct SegmentDefinition: Codable, Equatable, Sendable {
  /// The identifier of the first endpoint.
  public let start: GeometryID

  /// The identifier of the second endpoint.
  public let end: GeometryID

  /// Creates a segment definition.
  public init(start: GeometryID, end: GeometryID) {
    self.start = start
    self.end = end
  }
}

/// An infinite line passing through two point entities.
public struct LineDefinition: Codable, Equatable, Sendable {
  /// The identifier of the first point.
  public let first: GeometryID

  /// The identifier of the second point.
  public let second: GeometryID

  /// Creates an infinite-line definition.
  public init(first: GeometryID, second: GeometryID) {
    self.first = first
    self.second = second
  }
}

/// A ray starting at one point entity and passing through another.
public struct RayDefinition: Codable, Equatable, Sendable {
  /// The identifier of the origin point.
  public let origin: GeometryID

  /// The identifier of the point defining direction.
  public let through: GeometryID

  /// Creates a ray definition.
  public init(origin: GeometryID, through: GeometryID) {
    self.origin = origin
    self.through = through
  }
}

/// One base or derived entity stored in a geometry scene.
public enum GeometryEntity: Codable, Equatable, Sendable {
  /// A free, constrained, or derived point.
  case point(PointDefinition)

  /// A circle dependent on a centre point.
  case circle(CircleDefinition)

  /// An ellipse dependent on a centre point.
  case ellipse(EllipseDefinition)

  /// A finite segment dependent on two points.
  case segment(SegmentDefinition)

  /// An infinite line dependent on two points.
  case line(LineDefinition)

  /// A ray dependent on an origin and another point.
  case ray(RayDefinition)
}
