/// A point's independent coordinates or its relationship to other scene entities.
public enum PointDefinition: Codable, Equatable, Sendable {
  /// A point that can move anywhere in the scene.
  case free(Point2D)

  /// A derived point whose coordinates are scalar expressions.
  case computed(x: ScalarExpression, y: ScalarExpression)

  /// A point constrained to a circle at a stored angle.
  case onCircle(circle: GeometryID, angleRadians: Double)

  /// A point constrained to a circle at an expression-backed angle.
  case onCircleExpression(circle: GeometryID, angleRadians: ScalarExpression)

  /// A derived point sharing another point's x-coordinate at a fixed y-coordinate.
  case horizontalProjection(of: GeometryID, ontoY: Double)

  /// A derived horizontal projection with an expression-backed y-coordinate.
  case horizontalProjectionExpression(of: GeometryID, ontoY: ScalarExpression)

  /// A derived point sharing another point's y-coordinate at a fixed x-coordinate.
  case verticalProjection(of: GeometryID, ontoX: Double)

  /// A derived vertical projection with an expression-backed x-coordinate.
  case verticalProjectionExpression(of: GeometryID, ontoX: ScalarExpression)
}

/// A circle whose centre is supplied by another point entity.
public struct CircleDefinition: Codable, Equatable, Sendable {
  /// The identifier of the centre point.
  public let center: GeometryID

  /// The expression that supplies the circle radius.
  public let radius: ScalarExpression

  /// Creates a circle definition.
  public init(center: GeometryID, radius: Double) {
    self.center = center
    self.radius = .constant(radius)
  }

  /// Creates a circle definition with an expression-backed radius.
  public init(center: GeometryID, radius: ScalarExpression) {
    self.center = center
    self.radius = radius
  }

  private enum CodingKeys: CodingKey {
    case center
    case radius
  }

  /// Decodes expression-backed definitions and migrates legacy literal radii.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    center = try container.decode(GeometryID.self, forKey: .center)
    if let expression = try? container.decode(ScalarExpression.self, forKey: .radius) {
      radius = expression
    } else {
      radius = .constant(try container.decode(Double.self, forKey: .radius))
    }
  }

  /// Encodes the canonical expression-backed definition.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(center, forKey: .center)
    try container.encode(radius, forKey: .radius)
  }
}

/// An ellipse whose centre is supplied by another point entity.
public struct EllipseDefinition: Codable, Equatable, Sendable {
  /// The identifier of the centre point.
  public let center: GeometryID

  /// The expression that supplies the horizontal radius.
  public let radiusX: ScalarExpression

  /// The expression that supplies the vertical radius.
  public let radiusY: ScalarExpression

  /// Creates an ellipse definition.
  public init(center: GeometryID, radiusX: Double, radiusY: Double) {
    self.center = center
    self.radiusX = .constant(radiusX)
    self.radiusY = .constant(radiusY)
  }

  /// Creates an ellipse definition with expression-backed radii.
  public init(
    center: GeometryID,
    radiusX: ScalarExpression,
    radiusY: ScalarExpression
  ) {
    self.center = center
    self.radiusX = radiusX
    self.radiusY = radiusY
  }

  private enum CodingKeys: CodingKey {
    case center
    case radiusX
    case radiusY
  }

  /// Decodes expression-backed definitions and migrates legacy literal radii.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    center = try container.decode(GeometryID.self, forKey: .center)
    radiusX = try Self.decodeExpression(from: container, forKey: .radiusX)
    radiusY = try Self.decodeExpression(from: container, forKey: .radiusY)
  }

  /// Encodes the canonical expression-backed definition.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(center, forKey: .center)
    try container.encode(radiusX, forKey: .radiusX)
    try container.encode(radiusY, forKey: .radiusY)
  }

  private static func decodeExpression(
    from container: KeyedDecodingContainer<CodingKeys>,
    forKey key: CodingKeys
  ) throws -> ScalarExpression {
    if let expression = try? container.decode(ScalarExpression.self, forKey: key) {
      return expression
    }
    return .constant(try container.decode(Double.self, forKey: key))
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
