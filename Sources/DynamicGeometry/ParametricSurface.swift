import Foundation

/// Validation failures for semantic parametric-surface definitions and sampling requests.
public enum ParametricSurfaceError: Error, Equatable, LocalizedError, Sendable {
  /// An independent variable has no usable display name.
  case emptyIndependentVariableName

  /// The two independent variables have the same name or stable identifier.
  case duplicateIndependentVariable

  /// At least one domain bound is not finite.
  case nonFiniteBounds

  /// At least one domain does not increase from its lower bound to its upper bound.
  case invalidBounds

  /// A sampling dimension is too small to form a mesh.
  case invalidSampleCount(minimum: Int)

  /// A human-readable description of the validation failure.
  public var errorDescription: String? {
    switch self {
    case .emptyIndependentVariableName:
      "Independent variable names cannot be empty."
    case .duplicateIndependentVariable:
      "A parametric surface requires two distinct independent variables."
    case .nonFiniteBounds:
      "Parametric-surface bounds must be finite."
    case .invalidBounds:
      "Each lower bound must be smaller than its upper bound."
    case .invalidSampleCount(let minimum):
      "Each surface sample count must be at least \(minimum)."
    }
  }
}

/// A semantic three-dimensional surface defined by `(x(u,v), y(u,v), z(u,v))`.
public struct ParametricSurfaceDefinition: Codable, Equatable, Sendable {
  /// The stable identity of the first independent variable.
  public let uVariableID: ScalarParameterID

  /// The display name of the first independent variable.
  public let uVariableName: String

  /// The stable identity of the second independent variable.
  public let vVariableID: ScalarParameterID

  /// The display name of the second independent variable.
  public let vVariableName: String

  /// The expression that supplies each first coordinate.
  public let xExpression: ScalarExpression

  /// The expression that supplies each second coordinate.
  public let yExpression: ScalarExpression

  /// The expression that supplies each third coordinate.
  public let zExpression: ScalarExpression

  /// The finite increasing domain sampled for the first variable.
  public let uDomain: ClosedRange<Double>

  /// The finite increasing domain sampled for the second variable.
  public let vDomain: ClosedRange<Double>

  /// Creates and validates a semantic parametric-surface definition.
  public init(
    uVariableID: ScalarParameterID = ScalarParameterID(),
    uVariableName: String = "u",
    vVariableID: ScalarParameterID = ScalarParameterID(),
    vVariableName: String = "v",
    xExpression: ScalarExpression,
    yExpression: ScalarExpression,
    zExpression: ScalarExpression,
    uDomain: ClosedRange<Double>,
    vDomain: ClosedRange<Double>
  ) throws {
    try Self.validateVariables(
      uID: uVariableID,
      uName: uVariableName,
      vID: vVariableID,
      vName: vVariableName)
    try Self.validateDomain(uDomain)
    try Self.validateDomain(vDomain)
    try xExpression.validate()
    try yExpression.validate()
    try zExpression.validate()
    self.uVariableID = uVariableID
    self.uVariableName = uVariableName
    self.vVariableID = vVariableID
    self.vVariableName = vVariableName
    self.xExpression = xExpression
    self.yExpression = yExpression
    self.zExpression = zExpression
    self.uDomain = uDomain
    self.vDomain = vDomain
  }

  private static func validateVariables(
    uID: ScalarParameterID,
    uName: String,
    vID: ScalarParameterID,
    vName: String
  ) throws {
    guard
      !uName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !vName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw ParametricSurfaceError.emptyIndependentVariableName
    }
    guard uID != vID, uName != vName else {
      throw ParametricSurfaceError.duplicateIndependentVariable
    }
  }

  private static func validateDomain(_ domain: ClosedRange<Double>) throws {
    guard domain.lowerBound.isFinite, domain.upperBound.isFinite else {
      throw ParametricSurfaceError.nonFiniteBounds
    }
    guard domain.lowerBound < domain.upperBound else {
      throw ParametricSurfaceError.invalidBounds
    }
  }

  private enum CodingKeys: CodingKey {
    case uVariableID
    case uVariableName
    case vVariableID
    case vVariableName
    case xExpression
    case yExpression
    case zExpression
    case uDomain
    case vDomain
  }

  /// Decodes and validates a semantic surface definition.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      uVariableID: container.decode(ScalarParameterID.self, forKey: .uVariableID),
      uVariableName: container.decode(String.self, forKey: .uVariableName),
      vVariableID: container.decode(ScalarParameterID.self, forKey: .vVariableID),
      vVariableName: container.decode(String.self, forKey: .vVariableName),
      xExpression: container.decode(ScalarExpression.self, forKey: .xExpression),
      yExpression: container.decode(ScalarExpression.self, forKey: .yExpression),
      zExpression: container.decode(ScalarExpression.self, forKey: .zExpression),
      uDomain: container.decode(ClosedRange<Double>.self, forKey: .uDomain),
      vDomain: container.decode(ClosedRange<Double>.self, forKey: .vDomain))
  }
}

/// One coordinate of a parametric-surface evaluation.
public enum ParametricSurfaceCoordinate: String, Equatable, Sendable {
  /// The first spatial coordinate.
  case x

  /// The second spatial coordinate.
  case y

  /// The third spatial coordinate.
  case z
}

/// A recoverable issue encountered at one parameter-space location.
public enum ParametricSurfaceSamplingIssue: Equatable, Sendable {
  /// A coordinate expression did not produce a finite numerical value.
  case coordinate(ParametricSurfaceCoordinate, outcome: ScalarEvaluationOutcome)

  /// Three sampled points did not produce a usable triangle normal.
  case degenerateTriangle(diagnostic: String)
}

/// A structured diagnostic for an omitted point or triangle.
public struct ParametricSurfaceSamplingDiagnostic: Equatable, Sendable {
  /// The first independent-variable value where sampling failed.
  public let u: Double

  /// The second independent-variable value where sampling failed.
  public let v: Double

  /// The recoverable reason that geometry was omitted.
  public let issue: ParametricSurfaceSamplingIssue
}

/// A finite mesh vertex and its original parameter-space location.
public struct ParametricSurfaceVertex: Equatable, Sendable {
  /// The sampled three-dimensional point.
  public let point: Point3D

  /// The first independent-variable value used to produce the point.
  public let u: Double

  /// The second independent-variable value used to produce the point.
  public let v: Double
}

/// One indexed, consistently oriented mesh triangle with a unit normal.
public struct ParametricSurfaceTriangle: Equatable, Sendable {
  /// The first vertex index in the sample's vertex array.
  public let firstVertexIndex: Int

  /// The second vertex index in the sample's vertex array.
  public let secondVertexIndex: Int

  /// The third vertex index in the sample's vertex array.
  public let thirdVertexIndex: Int

  /// The unit normal derived from the triangle's winding order.
  public let normal: Vector3D
}

/// A renderer-independent indexed mesh plus recoverable sampling diagnostics.
public struct ParametricSurfaceMesh: Equatable, Sendable {
  /// Finite sampled vertices in row-major parameter order.
  public let vertices: [ParametricSurfaceVertex]

  /// Indexed triangles; cells containing an undefined vertex are omitted.
  public let triangles: [ParametricSurfaceTriangle]

  /// Undefined coordinate evaluations and degenerate triangles encountered while sampling.
  public let diagnostics: [ParametricSurfaceSamplingDiagnostic]
}
