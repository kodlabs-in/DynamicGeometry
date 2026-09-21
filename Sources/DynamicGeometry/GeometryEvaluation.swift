/// The observable result of a successful scene mutation.
public struct GeometrySceneChange: Equatable, Sendable {
  /// Scalar inputs changed by the mutation.
  public let changedParameterIDs: [ScalarParameterID]

  /// Changed entities in stable scene order, including transitive dependents.
  public let affectedEntityIDs: [GeometryID]

  /// Creates a mutation report.
  public init(
    changedParameterIDs: [ScalarParameterID] = [],
    affectedEntityIDs: [GeometryID]
  ) {
    self.changedParameterIDs = changedParameterIDs
    self.affectedEntityIDs = affectedEntityIDs
  }
}

/// The current evaluated state of one typed geometry entity.
public enum GeometryEvaluationOutcome<Value: Equatable & Sendable>: Equatable, Sendable {
  case exact(value: Value, diagnostic: String)
  case approximate(value: Value, diagnostic: String)
  case undefined(diagnostic: String)
  case unsupported(diagnostic: String)
  case nonconvergent(diagnostic: String)
  case pending(diagnostic: String)

  /// The evaluated value when one is available.
  public var value: Value? {
    switch self {
    case .exact(let value, _), .approximate(let value, _):
      value
    case .undefined, .unsupported, .nonconvergent, .pending:
      nil
    }
  }
}

enum ResolvedGeometry: Equatable, Sendable {
  case point(Point2D)
  case circle(Circle2D)
  case ellipse(Ellipse2D)
  case segment(Segment2D)
  case line(Line2D)
  case ray(Ray2D)
}

enum GeometryResolutionFailure: Error, Equatable, Sendable {
  case undefined(String)
  case unsupported(String)
  case nonconvergent(String)
  case pending(String)

  func outcome<Value: Equatable & Sendable>() -> GeometryEvaluationOutcome<Value> {
    switch self {
    case .undefined(let diagnostic):
      .undefined(diagnostic: diagnostic)
    case .unsupported(let diagnostic):
      .unsupported(diagnostic: diagnostic)
    case .nonconvergent(let diagnostic):
      .nonconvergent(diagnostic: diagnostic)
    case .pending(let diagnostic):
      .pending(diagnostic: diagnostic)
    }
  }
}
