import Foundation

/// Failures produced while constructing or applying a two-dimensional transform.
public enum CoordinateTransformError: Error, Equatable, LocalizedError, Sendable {
  /// One or more affine coefficients are not finite.
  case nonFiniteTransform

  /// A point supplied to the transform is not finite.
  case nonFinitePoint

  /// A vector supplied to the transform is not finite.
  case nonFiniteVector

  /// The transform collapses at least one dimension and cannot be inverted.
  case singularTransform

  /// A human-readable description of the transform failure.
  public var errorDescription: String? {
    switch self {
    case .nonFiniteTransform:
      "Transform coefficients must be finite numbers."
    case .nonFinitePoint:
      "Point coordinates must be finite numbers."
    case .nonFiniteVector:
      "Vector components must be finite numbers."
    case .singularTransform:
      "A singular transform cannot be inverted."
    }
  }
}

/// A validated affine transform for points and vectors in a two-dimensional coordinate space.
///
/// The transform uses the following layout:
///
/// ```text
/// x' = m11 * x + m12 * y + translationX
/// y' = m21 * x + m22 * y + translationY
/// ```
///
/// This value type is independent of any rendering framework or coordinate-system orientation.
public struct CoordinateTransform2D: Codable, Equatable, Sendable {
  /// The identity transform, which leaves every finite point and vector unchanged.
  public static let identity = CoordinateTransform2D(
    uncheckedM11: 1,
    m12: 0,
    m21: 0,
    m22: 1,
    translationX: 0,
    translationY: 0)

  /// The first coefficient of the transform's linear component.
  public let m11: Double

  /// The second coefficient in the transformed x-coordinate.
  public let m12: Double

  /// The first coefficient in the transformed y-coordinate.
  public let m21: Double

  /// The final coefficient of the transform's linear component.
  public let m22: Double

  /// The horizontal translation applied to points.
  public let translationX: Double

  /// The vertical translation applied to points.
  public let translationY: Double

  /// Creates a transform from its six affine coefficients.
  ///
  /// - Throws: ``CoordinateTransformError/nonFiniteTransform`` when any coefficient is not
  ///   finite.
  public init(
    m11: Double,
    m12: Double,
    m21: Double,
    m22: Double,
    translationX: Double,
    translationY: Double
  ) throws {
    guard Self.areFinite(m11, m12, m21, m22, translationX, translationY) else {
      throw CoordinateTransformError.nonFiniteTransform
    }

    self.init(
      uncheckedM11: m11,
      m12: m12,
      m21: m21,
      m22: m22,
      translationX: translationX,
      translationY: translationY)
  }

  /// Creates a translation by the supplied horizontal and vertical offsets.
  public static func translation(x: Double, y: Double) throws -> Self {
    try Self(
      m11: 1,
      m12: 0,
      m21: 0,
      m22: 1,
      translationX: x,
      translationY: y)
  }

  /// Creates a uniform scale for both axes.
  public static func scale(_ factor: Double) throws -> Self {
    try scale(x: factor, y: factor)
  }

  /// Creates a scale with independent horizontal and vertical factors.
  public static func scale(x: Double, y: Double) throws -> Self {
    try Self(
      m11: x,
      m12: 0,
      m21: 0,
      m22: y,
      translationX: 0,
      translationY: 0)
  }

  /// Creates a rotation in radians around the origin.
  ///
  /// Positive angles turn the positive x-axis toward the positive y-axis. In a screen coordinate
  /// system, where positive y points downward, that same numeric rotation appears clockwise.
  public static func rotation(radians: Double) throws -> Self {
    guard radians.isFinite else {
      throw CoordinateTransformError.nonFiniteTransform
    }
    let cosine = cos(radians)
    let sine = sin(radians)
    return try Self(
      m11: cosine,
      m12: -sine,
      m21: sine,
      m22: cosine,
      translationX: 0,
      translationY: 0)
  }

  /// Composes this transform with another transform in application order.
  ///
  /// `first.followed(by: second)` transforms geometry with `first`, then transforms that result
  /// with `second`. This explicit order is independent of the matrix multiplication order used by
  /// the implementation.
  public func followed(by next: Self) throws -> Self {
    try Self(
      m11: next.m11 * m11 + next.m12 * m21,
      m12: next.m11 * m12 + next.m12 * m22,
      m21: next.m21 * m11 + next.m22 * m21,
      m22: next.m21 * m12 + next.m22 * m22,
      translationX: next.m11 * translationX + next.m12 * translationY + next.translationX,
      translationY: next.m21 * translationX + next.m22 * translationY + next.translationY)
  }

  /// Returns the transform that reverses this transform.
  ///
  /// - Throws: ``CoordinateTransformError/singularTransform`` when the linear component has no
  ///   inverse, or ``CoordinateTransformError/nonFiniteTransform`` when inversion overflows.
  public func inverted() throws -> Self {
    let determinant = m11 * m22 - m12 * m21
    guard determinant.isFinite else {
      throw CoordinateTransformError.nonFiniteTransform
    }
    guard determinant != 0 else {
      throw CoordinateTransformError.singularTransform
    }

    return try Self(
      m11: m22 / determinant,
      m12: -m12 / determinant,
      m21: -m21 / determinant,
      m22: m11 / determinant,
      translationX: (m12 * translationY - m22 * translationX) / determinant,
      translationY: (m21 * translationX - m11 * translationY) / determinant)
  }

  private init(
    uncheckedM11 m11: Double,
    m12: Double,
    m21: Double,
    m22: Double,
    translationX: Double,
    translationY: Double
  ) {
    self.m11 = m11
    self.m12 = m12
    self.m21 = m21
    self.m22 = m22
    self.translationX = translationX
    self.translationY = translationY
  }

  private enum CodingKeys: CodingKey {
    case m11
    case m12
    case m21
    case m22
    case translationX
    case translationY
  }

  /// Decodes and validates an affine transform.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      m11: container.decode(Double.self, forKey: .m11),
      m12: container.decode(Double.self, forKey: .m12),
      m21: container.decode(Double.self, forKey: .m21),
      m22: container.decode(Double.self, forKey: .m22),
      translationX: container.decode(Double.self, forKey: .translationX),
      translationY: container.decode(Double.self, forKey: .translationY))
  }

  /// Encodes this validated affine transform.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(m11, forKey: .m11)
    try container.encode(m12, forKey: .m12)
    try container.encode(m21, forKey: .m21)
    try container.encode(m22, forKey: .m22)
    try container.encode(translationX, forKey: .translationX)
    try container.encode(translationY, forKey: .translationY)
  }

  /// Applies this affine transform to a point, including its translation.
  public func transform(_ point: Point2D) throws -> Point2D {
    guard point.isFinite else {
      throw CoordinateTransformError.nonFinitePoint
    }

    let result = Point2D(
      x: m11 * point.x + m12 * point.y + translationX,
      y: m21 * point.x + m22 * point.y + translationY)
    guard result.isFinite else {
      throw CoordinateTransformError.nonFinitePoint
    }
    return result
  }

  /// Applies only this transform's linear component to a vector.
  public func transform(_ vector: Vector2D) throws -> Vector2D {
    guard vector.x.isFinite, vector.y.isFinite else {
      throw CoordinateTransformError.nonFiniteVector
    }

    let result = Vector2D(
      x: m11 * vector.x + m12 * vector.y,
      y: m21 * vector.x + m22 * vector.y)
    guard result.x.isFinite, result.y.isFinite else {
      throw CoordinateTransformError.nonFiniteVector
    }
    return result
  }

  private static func areFinite(_ values: Double...) -> Bool {
    values.allSatisfy(\.isFinite)
  }
}
