/// Stable identifiers for geometry features a host can discover before issuing commands.
public enum GeometryCapability: String, CaseIterable, Codable, Equatable, Sendable {
  case scalarParameters
  case scalarExpressions
  case recoverableEvaluationStates
  case entityPoint
  case entityCircle
  case entityEllipse
  case entitySegment
  case entityLine
  case entityRay
  case explicitCurves
  case parametricCurves
  case polarCurves
  case implicitCurves
  case discontinuitySafeSampling
  case riemannSums
  case referenceUnitCircle
  case geometry3D
  case affineTransforms3D
  case parametricSurfaces
  case symbolicSimplification
  case symbolicDifferentiation
  case polynomialSolving
  case simultaneousConstraintSolver
  case commandInsert
  case commandReplace
  case commandMovePoint
  case commandSetParameter
  case commandDelete
  case atomicTransactions
  case cascadeDeletion
  case undoRedoHistory
}

/// The capabilities implemented by a DynamicGeometry engine release.
public struct GeometryCapabilities: Codable, Equatable, Sendable {
  /// Capabilities supported by this release in stable declaration order.
  public static let current = GeometryCapabilities(supported: GeometryCapability.allCases)

  /// Supported feature identifiers.
  public let supported: [GeometryCapability]

  /// Creates a capability description.
  public init(supported: [GeometryCapability]) {
    self.supported = supported
  }

  /// Returns whether a feature is supported.
  public func supports(_ capability: GeometryCapability) -> Bool {
    supported.contains(capability)
  }
}
