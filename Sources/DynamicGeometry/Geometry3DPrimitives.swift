import Foundation

/// Failures produced by validated three-dimensional geometry values.
public enum Geometry3DError: Error, Equatable, LocalizedError, Sendable {
  /// At least one point coordinate is not finite.
  case nonFinitePoint

  /// At least one vector component or vector result is not finite.
  case nonFiniteVector

  /// An operation requires a direction but received a zero-length vector.
  case zeroLengthVector

  /// At least one affine-transform coefficient is not finite.
  case nonFiniteTransform

  /// An affine transform collapses at least one dimension and has no inverse.
  case singularTransform

  /// A human-readable description of the validation failure.
  public var errorDescription: String? {
    switch self {
    case .nonFinitePoint:
      "Point coordinates must be finite numbers."
    case .nonFiniteVector:
      "Vector components and results must be finite numbers."
    case .zeroLengthVector:
      "A zero-length vector does not define a direction."
    case .nonFiniteTransform:
      "Transform coefficients and results must be finite numbers."
    case .singularTransform:
      "A singular transform cannot be inverted."
    }
  }
}

/// A validated finite point in a three-dimensional coordinate space.
public struct Point3D: Codable, Equatable, Sendable {
  /// The first coordinate.
  public let x: Double

  /// The second coordinate.
  public let y: Double

  /// The third coordinate.
  public let z: Double

  /// Creates a point after validating all three coordinates.
  public init(x: Double, y: Double, z: Double) throws {
    guard x.isFinite, y.isFinite, z.isFinite else {
      throw Geometry3DError.nonFinitePoint
    }
    self.x = x
    self.y = y
    self.z = z
  }

  /// Returns the finite displacement from this point to another point.
  public func displacement(to other: Point3D) throws -> Vector3D {
    try Vector3D(x: other.x - x, y: other.y - y, z: other.z - z)
  }

  private enum CodingKeys: CodingKey {
    case x
    case y
    case z
  }

  /// Decodes and validates a finite point.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      x: container.decode(Double.self, forKey: .x),
      y: container.decode(Double.self, forKey: .y),
      z: container.decode(Double.self, forKey: .z))
  }
}

/// A validated finite displacement or direction in three dimensions.
public struct Vector3D: Codable, Equatable, Sendable {
  /// The first component.
  public let x: Double

  /// The second component.
  public let y: Double

  /// The third component.
  public let z: Double

  /// Creates a vector after validating all three components.
  public init(x: Double, y: Double, z: Double) throws {
    guard x.isFinite, y.isFinite, z.isFinite else {
      throw Geometry3DError.nonFiniteVector
    }
    self.x = x
    self.y = y
    self.z = z
  }

  /// Returns the finite Euclidean length of this vector.
  public func length() throws -> Double {
    let value = hypot(hypot(x, y), z)
    guard value.isFinite else {
      throw Geometry3DError.nonFiniteVector
    }
    return value
  }

  /// Returns the finite dot product with another vector.
  public func dot(_ other: Vector3D) throws -> Double {
    let value = x * other.x + y * other.y + z * other.z
    guard value.isFinite else {
      throw Geometry3DError.nonFiniteVector
    }
    return value
  }

  /// Returns the finite cross product with another vector.
  public func cross(_ other: Vector3D) throws -> Vector3D {
    try Vector3D(
      x: y * other.z - z * other.y,
      y: z * other.x - x * other.z,
      z: x * other.y - y * other.x)
  }

  /// Returns a unit-length vector with the same direction.
  public func normalized() throws -> Vector3D {
    let magnitude = try length()
    guard magnitude > 0 else {
      throw Geometry3DError.zeroLengthVector
    }
    return try Vector3D(x: x / magnitude, y: y / magnitude, z: z / magnitude)
  }

  private enum CodingKeys: CodingKey {
    case x
    case y
    case z
  }

  /// Decodes and validates a finite vector.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      x: container.decode(Double.self, forKey: .x),
      y: container.decode(Double.self, forKey: .y),
      z: container.decode(Double.self, forKey: .z))
  }
}
