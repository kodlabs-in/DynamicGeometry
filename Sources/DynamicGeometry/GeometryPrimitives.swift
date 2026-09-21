import Foundation

/// Errors produced while validating or resolving a geometric construction.
public enum GeometryError: Error, Equatable, LocalizedError, Sendable {
  /// A coordinate, angle, or dimension was not finite.
  case nonFiniteValue(String)

  /// A radius or other positive dimension was zero or negative.
  case nonPositiveDimension(String)

  /// A referenced entity does not exist in the scene.
  case missingEntity(GeometryID)

  /// An entity exists but has a different geometric type than required.
  case unexpectedEntity(GeometryID, expected: String)

  /// Adding an entity would reuse an existing identifier.
  case duplicateEntity(GeometryID)

  /// A dependency eventually refers back to itself.
  case cyclicDependency(GeometryID)

  /// A derived point cannot be moved directly.
  case readOnlyPoint(GeometryID)

  /// A direction cannot be calculated from two coincident points.
  case undefinedDirection

  /// Encoded scene storage and its display order do not contain the same identifiers.
  case inconsistentScene

  /// A human-readable description of the geometry failure.
  public var errorDescription: String? {
    switch self {
    case .nonFiniteValue(let name):
      "\(name) must be a finite number."
    case .nonPositiveDimension(let name):
      "\(name) must be greater than zero."
    case .missingEntity(let id):
      "The construction refers to missing entity \(id)."
    case .unexpectedEntity(let id, let expected):
      "Entity \(id) is not a \(expected)."
    case .duplicateEntity(let id):
      "Entity \(id) already exists."
    case .cyclicDependency(let id):
      "Entity \(id) creates a cyclic geometry dependency."
    case .readOnlyPoint(let id):
      "Derived point \(id) cannot be moved directly."
    case .undefinedDirection:
      "A direction requires two distinct points."
    case .inconsistentScene:
      "The scene order does not match its stored entities."
    }
  }
}

/// A stable identifier used to connect entities without application-specific model types.
public struct GeometryID: Codable, CustomStringConvertible, Hashable, Sendable {
  /// The underlying universally unique identifier.
  public let rawValue: UUID

  /// Creates an identifier, generating a new UUID by default.
  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }

  /// A printable form of the identifier.
  public var description: String {
    rawValue.uuidString
  }
}

/// The orientation used when converting an angle into screen or Cartesian coordinates.
public enum CoordinateSystem2D: String, Codable, Equatable, Sendable {
  /// Positive y values point upward.
  case cartesian

  /// Positive y values point downward, as in UIKit and SwiftUI layout coordinates.
  case screenYDown
}

/// A finite-capable point in a two-dimensional coordinate space.
public struct Point2D: Codable, Equatable, Sendable {
  /// The horizontal coordinate.
  public var x: Double

  /// The vertical coordinate.
  public var y: Double

  /// Creates a point from horizontal and vertical coordinates.
  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }

  /// Whether both coordinates are finite.
  public var isFinite: Bool {
    x.isFinite && y.isFinite
  }

  /// Returns the Euclidean distance to another point.
  public func distance(to other: Point2D) -> Double {
    hypot(other.x - x, other.y - y)
  }
}

/// A two-dimensional displacement or direction.
public struct Vector2D: Codable, Equatable, Sendable {
  /// The horizontal component.
  public var x: Double

  /// The vertical component.
  public var y: Double

  /// Creates a vector from horizontal and vertical components.
  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }

  /// The vector magnitude.
  public var length: Double {
    hypot(x, y)
  }
}

/// A circle with a centre point and positive radius.
public struct Circle2D: Codable, Equatable, Sendable {
  /// The centre of the circle.
  public let center: Point2D

  /// The radius of the circle.
  public let radius: Double

  /// Creates and validates a circle.
  public init(center: Point2D, radius: Double) throws {
    try Self.validate(center: center, radius: radius)
    self.center = center
    self.radius = radius
  }

  /// Returns the point at an angle measured counterclockwise from the positive x-axis.
  public func point(
    at angleRadians: Double,
    coordinateSystem: CoordinateSystem2D = .cartesian
  ) throws -> Point2D {
    guard angleRadians.isFinite else {
      throw GeometryError.nonFiniteValue("Angle")
    }
    let verticalDirection = coordinateSystem == .cartesian ? 1.0 : -1.0
    return Point2D(
      x: center.x + radius * cos(angleRadians),
      y: center.y + verticalDirection * radius * sin(angleRadians))
  }

  /// Returns a normalized angle for a point relative to this circle's centre.
  public func angle(
    toward point: Point2D,
    coordinateSystem: CoordinateSystem2D = .cartesian
  ) throws -> Double {
    guard point.isFinite else {
      throw GeometryError.nonFiniteValue("Point")
    }
    let horizontalOffset = point.x - center.x
    let rawVerticalOffset = point.y - center.y
    guard horizontalOffset != 0 || rawVerticalOffset != 0 else {
      throw GeometryError.undefinedDirection
    }
    let verticalOffset = coordinateSystem == .cartesian ? rawVerticalOffset : -rawVerticalOffset
    return Self.normalizedAngle(atan2(verticalOffset, horizontalOffset))
  }

  /// Returns an equivalent angle in the half-open range from zero to two pi.
  public static func normalizedAngle(_ angleRadians: Double) -> Double {
    let fullTurn = 2 * Double.pi
    let remainder = angleRadians.truncatingRemainder(dividingBy: fullTurn)
    return remainder >= 0 ? remainder : remainder + fullTurn
  }

  private static func validate(center: Point2D, radius: Double) throws {
    guard center.isFinite else {
      throw GeometryError.nonFiniteValue("Circle centre")
    }
    guard radius.isFinite else {
      throw GeometryError.nonFiniteValue("Circle radius")
    }
    guard radius > 0 else {
      throw GeometryError.nonPositiveDimension("Circle radius")
    }
  }

  private enum CodingKeys: CodingKey {
    case center
    case radius
  }

  /// Decodes and validates a circle.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      center: container.decode(Point2D.self, forKey: .center),
      radius: container.decode(Double.self, forKey: .radius))
  }

  /// Encodes a validated circle.
  public func encode(to encoder: Encoder) throws {
    try Self.validate(center: center, radius: radius)
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(center, forKey: .center)
    try container.encode(radius, forKey: .radius)
  }
}

/// An ellipse with independent positive horizontal and vertical radii.
public struct Ellipse2D: Codable, Equatable, Sendable {
  /// The centre of the ellipse.
  public let center: Point2D

  /// The horizontal radius.
  public let radiusX: Double

  /// The vertical radius.
  public let radiusY: Double

  /// Creates and validates an ellipse.
  public init(center: Point2D, radiusX: Double, radiusY: Double) throws {
    guard center.isFinite else {
      throw GeometryError.nonFiniteValue("Ellipse centre")
    }
    guard radiusX.isFinite, radiusY.isFinite else {
      throw GeometryError.nonFiniteValue("Ellipse radius")
    }
    guard radiusX > 0, radiusY > 0 else {
      throw GeometryError.nonPositiveDimension("Ellipse radius")
    }
    self.center = center
    self.radiusX = radiusX
    self.radiusY = radiusY
  }

  private enum CodingKeys: CodingKey {
    case center
    case radiusX
    case radiusY
  }

  /// Decodes and validates an ellipse.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      center: container.decode(Point2D.self, forKey: .center),
      radiusX: container.decode(Double.self, forKey: .radiusX),
      radiusY: container.decode(Double.self, forKey: .radiusY))
  }
}

/// A finite segment between two points.
public struct Segment2D: Codable, Equatable, Sendable {
  /// The first endpoint.
  public let start: Point2D

  /// The second endpoint.
  public let end: Point2D

  /// Creates and validates a segment.
  public init(start: Point2D, end: Point2D) throws {
    guard start.isFinite, end.isFinite else {
      throw GeometryError.nonFiniteValue("Segment endpoint")
    }
    self.start = start
    self.end = end
  }

  /// The segment length.
  public var length: Double {
    start.distance(to: end)
  }

  private enum CodingKeys: CodingKey {
    case start
    case end
  }

  /// Decodes and validates a segment.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      start: container.decode(Point2D.self, forKey: .start),
      end: container.decode(Point2D.self, forKey: .end))
  }
}

/// An infinite line defined by two distinct points.
public struct Line2D: Codable, Equatable, Sendable {
  /// The first point on the line.
  public let first: Point2D

  /// The second point on the line.
  public let second: Point2D

  /// Creates and validates an infinite line.
  public init(first: Point2D, second: Point2D) throws {
    guard first.isFinite, second.isFinite else {
      throw GeometryError.nonFiniteValue("Line point")
    }
    guard first != second else {
      throw GeometryError.undefinedDirection
    }
    self.first = first
    self.second = second
  }

  /// The line direction from the first point toward the second.
  public var direction: Vector2D {
    Vector2D(x: second.x - first.x, y: second.y - first.y)
  }

  private enum CodingKeys: CodingKey {
    case first
    case second
  }

  /// Decodes and validates an infinite line.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      first: container.decode(Point2D.self, forKey: .first),
      second: container.decode(Point2D.self, forKey: .second))
  }
}

/// A ray beginning at an origin and extending through another point.
public struct Ray2D: Codable, Equatable, Sendable {
  /// The ray origin.
  public let origin: Point2D

  /// A second point defining the ray direction.
  public let through: Point2D

  /// Creates and validates a ray.
  public init(origin: Point2D, through: Point2D) throws {
    guard origin.isFinite, through.isFinite else {
      throw GeometryError.nonFiniteValue("Ray point")
    }
    guard origin != through else {
      throw GeometryError.undefinedDirection
    }
    self.origin = origin
    self.through = through
  }

  /// The ray direction from its origin toward its second point.
  public var direction: Vector2D {
    Vector2D(x: through.x - origin.x, y: through.y - origin.y)
  }

  private enum CodingKeys: CodingKey {
    case origin
    case through
  }

  /// Decodes and validates a ray.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      origin: container.decode(Point2D.self, forKey: .origin),
      through: container.decode(Point2D.self, forKey: .through))
  }
}
