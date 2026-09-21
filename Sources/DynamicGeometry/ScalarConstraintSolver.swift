import Foundation

/// Structural failures raised before a simultaneous constraint solve begins.
public enum ScalarConstraintSystemError: Error, Equatable, LocalizedError, Sendable {
  /// At least one adjustable variable is required.
  case emptyVariables

  /// At least one equality is required.
  case emptyConstraints

  /// Variable and fixed-parameter identifiers must be unique.
  case duplicateParameterID(ScalarParameterID)

  /// Variable and fixed-parameter names must be unique.
  case duplicateParameterName(String)

  /// An expression references a parameter that is not supplied by the system.
  case missingParameter(ScalarParameterID)

  /// A human-readable description of the invalid system.
  public var errorDescription: String? {
    switch self {
    case .emptyVariables:
      "A constraint system needs at least one adjustable variable."
    case .emptyConstraints:
      "A constraint system needs at least one equality."
    case .duplicateParameterID(let id):
      "Constraint-system parameter identifier \(id) is duplicated."
    case .duplicateParameterName(let name):
      "Constraint-system parameter name \(name) is duplicated."
    case .missingParameter(let id):
      "Constraint expression refers to missing parameter \(id)."
    }
  }
}

/// One semantic scalar equality, represented as `left = right`.
public struct ScalarEqualityConstraint: Codable, Equatable, Sendable {
  /// The expression on the equality's left side.
  public let left: ScalarExpression

  /// The expression on the equality's right side.
  public let right: ScalarExpression

  /// Creates a validated equality.
  public init(left: ScalarExpression, right: ScalarExpression) throws {
    try left.validate()
    try right.validate()
    self.left = left
    self.right = right
  }

  private enum CodingKeys: CodingKey {
    case left
    case right
  }

  /// Decodes and revalidates a stored equality.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      left: container.decode(ScalarExpression.self, forKey: .left),
      right: container.decode(ScalarExpression.self, forKey: .right))
  }

  fileprivate var referencedParameterIDs: [ScalarParameterID] {
    var seen: Set<ScalarParameterID> = []
    return (left.referencedParameterIDs + right.referencedParameterIDs).filter {
      seen.insert($0).inserted
    }
  }
}

/// Bounded controls for the local numerical equality solver.
public struct ScalarConstraintSolverOptions: Codable, Equatable, Sendable {
  /// Maximum damped least-squares iterations.
  public let maximumIterations: Int

  /// Maximum absolute residual accepted as converged.
  public let residualTolerance: Double

  /// Relative finite-difference step used to estimate the Jacobian.
  public let finiteDifferenceStep: Double

  /// Initial diagonal damping applied to the normal equations.
  public let initialDamping: Double

  /// Optional wall-clock budget in seconds; zero stops before the first iteration.
  public let maximumDurationSeconds: Double?

  /// Creates solver controls. Invalid controls produce an unsupported solve outcome.
  public init(
    maximumIterations: Int = 64,
    residualTolerance: Double = 0.000_000_001,
    finiteDifferenceStep: Double = 0.000_001,
    initialDamping: Double = 0.000_001,
    maximumDurationSeconds: Double? = 0.25
  ) {
    self.maximumIterations = maximumIterations
    self.residualTolerance = residualTolerance
    self.finiteDifferenceStep = finiteDifferenceStep
    self.initialDamping = initialDamping
    self.maximumDurationSeconds = maximumDurationSeconds
  }

  fileprivate var isValid: Bool {
    maximumIterations > 0
      && residualTolerance.isFinite && residualTolerance > 0
      && finiteDifferenceStep.isFinite && finiteDifferenceStep > 0
      && initialDamping.isFinite && initialDamping > 0
      && maximumDurationSeconds.map { $0.isFinite && $0 >= 0 } ?? true
  }
}

/// A finite candidate produced by a simultaneous constraint solve.
public struct ScalarConstraintSolution: Equatable, Sendable {
  /// Solved adjustable parameters in the system's stable variable order.
  public let variables: [ScalarParameter]

  /// Signed `left - right` residuals in constraint order.
  public let residuals: [Double]

  /// Number of solver iterations used to produce this candidate.
  public let iterationCount: Int

  /// Largest absolute equality residual.
  public var maximumAbsoluteResidual: Double {
    residuals.map(abs).max() ?? 0
  }

  /// Returns the solved value for a stable variable identifier.
  public func value(for id: ScalarParameterID) -> Double? {
    variables.first(where: { $0.id == id })?.value
  }
}

/// A structured result from the bounded simultaneous equality solver.
public enum ScalarConstraintSolveOutcome: Equatable, Sendable {
  /// Every equality met the requested residual tolerance.
  case converged(ScalarConstraintSolution)

  /// The bounded iteration process ended without reaching the requested tolerance.
  case nonconvergent(best: ScalarConstraintSolution?, diagnostic: String)

  /// An expression was not numerically defined at a required candidate.
  case undefined(diagnostic: String)

  /// The request or an expression is outside the implemented numerical capability.
  case unsupported(diagnostic: String)

  /// Evaluation is intentionally deferred by an optional backend.
  case pending(diagnostic: String)
}

/// An isolated set of simultaneous scalar equalities and adjustable parameters.
///
/// The solver uses initial values to select a local branch. It is a bounded numerical method, not
/// a proof of existence, uniqueness, or global completeness.
public struct ScalarConstraintSystem: Codable, Equatable, Sendable {
  /// Adjustable inputs in deterministic solver order.
  public let variables: [ScalarParameter]

  /// Read-only inputs available to every constraint expression.
  public let fixedParameters: [ScalarParameter]

  /// Equalities evaluated together as one isolated system.
  public let constraints: [ScalarEqualityConstraint]

  /// Creates and structurally validates a simultaneous constraint system.
  public init(
    variables: [ScalarParameter],
    fixedParameters: [ScalarParameter] = [],
    constraints: [ScalarEqualityConstraint]
  ) throws {
    guard !variables.isEmpty else {
      throw ScalarConstraintSystemError.emptyVariables
    }
    guard !constraints.isEmpty else {
      throw ScalarConstraintSystemError.emptyConstraints
    }
    let parameters = variables + fixedParameters
    var identifiers: Set<ScalarParameterID> = []
    var names: Set<String> = []
    for parameter in parameters {
      guard identifiers.insert(parameter.id).inserted else {
        throw ScalarConstraintSystemError.duplicateParameterID(parameter.id)
      }
      guard names.insert(parameter.name).inserted else {
        throw ScalarConstraintSystemError.duplicateParameterName(parameter.name)
      }
    }
    for id in constraints.flatMap(\.referencedParameterIDs)
    where !identifiers.contains(id) {
      throw ScalarConstraintSystemError.missingParameter(id)
    }
    self.variables = variables
    self.fixedParameters = fixedParameters
    self.constraints = constraints
  }

  private enum CodingKeys: CodingKey {
    case variables
    case fixedParameters
    case constraints
  }

  /// Decodes and structurally revalidates a stored simultaneous system.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      variables: container.decode([ScalarParameter].self, forKey: .variables),
      fixedParameters: container.decode([ScalarParameter].self, forKey: .fixedParameters),
      constraints: container.decode([ScalarEqualityConstraint].self, forKey: .constraints))
  }

  /// Solves the equalities locally using damped least squares and numerical Jacobians.
  public func solve(
    options: ScalarConstraintSolverOptions = ScalarConstraintSolverOptions()
  ) -> ScalarConstraintSolveOutcome {
    guard options.isValid else {
      return .unsupported(diagnostic: "Constraint solver options must be finite and positive.")
    }
    switch prepareConstraintSolve(options: options) {
    case .finished(let outcome):
      return outcome
    case .ready(let state):
      return solveIterations(from: state, options: options)
    }
  }
}
