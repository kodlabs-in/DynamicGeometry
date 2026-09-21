import Foundation

/// A validated affine transform for points and vectors in three dimensions.
///
/// Points receive the linear component and translation; vectors receive only the linear component.
public struct CoordinateTransform3D: Codable, Equatable, Sendable {
  /// The identity transform.
  public static let identity = CoordinateTransform3D(
    uncheckedCoefficients: [1, 0, 0, 0, 1, 0, 0, 0, 1],
    translation: [0, 0, 0])

  /// The first row and first column of the linear component.
  public let m11: Double

  /// The first row and second column of the linear component.
  public let m12: Double

  /// The first row and third column of the linear component.
  public let m13: Double

  /// The second row and first column of the linear component.
  public let m21: Double

  /// The second row and second column of the linear component.
  public let m22: Double

  /// The second row and third column of the linear component.
  public let m23: Double

  /// The third row and first column of the linear component.
  public let m31: Double

  /// The third row and second column of the linear component.
  public let m32: Double

  /// The third row and third column of the linear component.
  public let m33: Double

  /// Translation along the first axis, applied only to points.
  public let translationX: Double

  /// Translation along the second axis, applied only to points.
  public let translationY: Double

  /// Translation along the third axis, applied only to points.
  public let translationZ: Double

  /// Creates a validated affine transform from a row-major linear component and translation.
  public init(
    m11: Double,
    m12: Double,
    m13: Double,
    m21: Double,
    m22: Double,
    m23: Double,
    m31: Double,
    m32: Double,
    m33: Double,
    translationX: Double,
    translationY: Double,
    translationZ: Double
  ) throws {
    let coefficients = [m11, m12, m13, m21, m22, m23, m31, m32, m33]
    let translation = [translationX, translationY, translationZ]
    guard (coefficients + translation).allSatisfy(\.isFinite) else {
      throw Geometry3DError.nonFiniteTransform
    }
    self.init(uncheckedCoefficients: coefficients, translation: translation)
  }

  /// Creates a translation along the three coordinate axes.
  public static func translation(x: Double, y: Double, z: Double) throws -> Self {
    try Self(
      m11: 1,
      m12: 0,
      m13: 0,
      m21: 0,
      m22: 1,
      m23: 0,
      m31: 0,
      m32: 0,
      m33: 1,
      translationX: x,
      translationY: y,
      translationZ: z)
  }

  /// Creates an axis-aligned scale.
  public static func scale(x: Double, y: Double, z: Double) throws -> Self {
    try Self(
      m11: x,
      m12: 0,
      m13: 0,
      m21: 0,
      m22: y,
      m23: 0,
      m31: 0,
      m32: 0,
      m33: z,
      translationX: 0,
      translationY: 0,
      translationZ: 0)
  }

  /// Composes this transform with another transform in application order.
  ///
  /// `first.followed(by: second)` applies `first`, then `second`.
  public func followed(by next: Self) throws -> Self {
    let product = multipliedLinearComponent(by: next)
    return try Self(
      m11: product[0],
      m12: product[1],
      m13: product[2],
      m21: product[3],
      m22: product[4],
      m23: product[5],
      m31: product[6],
      m32: product[7],
      m33: product[8],
      translationX:
        next.m11 * translationX + next.m12 * translationY + next.m13 * translationZ
        + next.translationX,
      translationY:
        next.m21 * translationX + next.m22 * translationY + next.m23 * translationZ
        + next.translationY,
      translationZ:
        next.m31 * translationX + next.m32 * translationY + next.m33 * translationZ
        + next.translationZ)
  }

  /// Returns the affine transform that reverses this transform.
  public func inverted() throws -> Self {
    let determinant =
      m11 * (m22 * m33 - m23 * m32)
      - m12 * (m21 * m33 - m23 * m31)
      + m13 * (m21 * m32 - m22 * m31)
    guard determinant.isFinite else {
      throw Geometry3DError.nonFiniteTransform
    }
    guard determinant != 0 else {
      throw Geometry3DError.singularTransform
    }

    let inverse = [
      (m22 * m33 - m23 * m32) / determinant,
      (m13 * m32 - m12 * m33) / determinant,
      (m12 * m23 - m13 * m22) / determinant,
      (m23 * m31 - m21 * m33) / determinant,
      (m11 * m33 - m13 * m31) / determinant,
      (m13 * m21 - m11 * m23) / determinant,
      (m21 * m32 - m22 * m31) / determinant,
      (m12 * m31 - m11 * m32) / determinant,
      (m11 * m22 - m12 * m21) / determinant,
    ]
    let inverseTranslation = [
      -(inverse[0] * translationX + inverse[1] * translationY + inverse[2] * translationZ),
      -(inverse[3] * translationX + inverse[4] * translationY + inverse[5] * translationZ),
      -(inverse[6] * translationX + inverse[7] * translationY + inverse[8] * translationZ),
    ]
    return try Self(
      m11: inverse[0],
      m12: inverse[1],
      m13: inverse[2],
      m21: inverse[3],
      m22: inverse[4],
      m23: inverse[5],
      m31: inverse[6],
      m32: inverse[7],
      m33: inverse[8],
      translationX: inverseTranslation[0],
      translationY: inverseTranslation[1],
      translationZ: inverseTranslation[2])
  }

  /// Applies the complete affine transform to a point.
  public func transform(_ point: Point3D) throws -> Point3D {
    try Point3D(
      x: m11 * point.x + m12 * point.y + m13 * point.z + translationX,
      y: m21 * point.x + m22 * point.y + m23 * point.z + translationY,
      z: m31 * point.x + m32 * point.y + m33 * point.z + translationZ)
  }

  /// Applies only the linear component to a vector.
  public func transform(_ vector: Vector3D) throws -> Vector3D {
    try Vector3D(
      x: m11 * vector.x + m12 * vector.y + m13 * vector.z,
      y: m21 * vector.x + m22 * vector.y + m23 * vector.z,
      z: m31 * vector.x + m32 * vector.y + m33 * vector.z)
  }

  private func multipliedLinearComponent(by next: Self) -> [Double] {
    [
      next.m11 * m11 + next.m12 * m21 + next.m13 * m31,
      next.m11 * m12 + next.m12 * m22 + next.m13 * m32,
      next.m11 * m13 + next.m12 * m23 + next.m13 * m33,
      next.m21 * m11 + next.m22 * m21 + next.m23 * m31,
      next.m21 * m12 + next.m22 * m22 + next.m23 * m32,
      next.m21 * m13 + next.m22 * m23 + next.m23 * m33,
      next.m31 * m11 + next.m32 * m21 + next.m33 * m31,
      next.m31 * m12 + next.m32 * m22 + next.m33 * m32,
      next.m31 * m13 + next.m32 * m23 + next.m33 * m33,
    ]
  }

  private init(uncheckedCoefficients coefficients: [Double], translation: [Double]) {
    m11 = coefficients[0]
    m12 = coefficients[1]
    m13 = coefficients[2]
    m21 = coefficients[3]
    m22 = coefficients[4]
    m23 = coefficients[5]
    m31 = coefficients[6]
    m32 = coefficients[7]
    m33 = coefficients[8]
    translationX = translation[0]
    translationY = translation[1]
    translationZ = translation[2]
  }

  private enum CodingKeys: CodingKey {
    case m11
    case m12
    case m13
    case m21
    case m22
    case m23
    case m31
    case m32
    case m33
    case translationX
    case translationY
    case translationZ
  }

  /// Decodes and validates an affine transform.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      m11: container.decode(Double.self, forKey: .m11),
      m12: container.decode(Double.self, forKey: .m12),
      m13: container.decode(Double.self, forKey: .m13),
      m21: container.decode(Double.self, forKey: .m21),
      m22: container.decode(Double.self, forKey: .m22),
      m23: container.decode(Double.self, forKey: .m23),
      m31: container.decode(Double.self, forKey: .m31),
      m32: container.decode(Double.self, forKey: .m32),
      m33: container.decode(Double.self, forKey: .m33),
      translationX: container.decode(Double.self, forKey: .translationX),
      translationY: container.decode(Double.self, forKey: .translationY),
      translationZ: container.decode(Double.self, forKey: .translationZ))
  }
}
