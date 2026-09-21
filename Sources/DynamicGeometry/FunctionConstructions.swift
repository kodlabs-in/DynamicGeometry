import Foundation

/// Validation failures for reusable one-dimensional functions and constructions.
public enum FunctionConstructionError: Error, Equatable, LocalizedError, Sendable {
  /// The independent variable has no usable display name.
  case emptyIndependentVariableName

  /// A domain or interval contains a non-finite bound.
  case nonFiniteBounds

  /// A domain or interval does not increase from its lower to upper bound.
  case invalidBounds

  /// A sampling count is too small for the requested operation.
  case invalidSampleCount(minimum: Int)

  /// A human-readable explanation of the validation failure.
  public var errorDescription: String? {
    switch self {
    case .emptyIndependentVariableName:
      "An independent variable name cannot be empty."
    case .nonFiniteBounds:
      "Function construction bounds must be finite."
    case .invalidBounds:
      "The lower bound must be smaller than the upper bound."
    case .invalidSampleCount(let minimum):
      "The sample count must be at least \(minimum)."
    }
  }
}

/// A Codable real-valued function with one independent variable.
public struct ScalarFunction1D: Codable, Equatable, Sendable {
  /// The stable identity used by expressions that reference the independent variable.
  public let independentVariableID: ScalarParameterID

  /// The name used by expressions that reference the independent variable by name.
  public let independentVariableName: String

  /// The expression evaluated by this function.
  public let expression: ScalarExpression

  /// Creates a validated single-variable function.
  public init(
    independentVariableID: ScalarParameterID = ScalarParameterID(),
    independentVariableName: String = "x",
    expression: ScalarExpression
  ) throws {
    guard !independentVariableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw FunctionConstructionError.emptyIndependentVariableName
    }
    try expression.validate()
    self.independentVariableID = independentVariableID
    self.independentVariableName = independentVariableName
    self.expression = expression
  }

  /// Evaluates the function at one finite input with optional additional parameters.
  public func evaluate(
    at input: Double,
    parameters: [ScalarParameter] = []
  ) -> ScalarEvaluationOutcome {
    guard input.isFinite else {
      return .undefined(diagnostic: "The independent variable must be finite.")
    }
    guard
      !parameters.contains(where: {
        $0.id == independentVariableID || $0.name == independentVariableName
      })
    else {
      return .undefined(
        diagnostic: "An additional parameter conflicts with the independent variable.")
    }
    do {
      let variable = try ScalarParameter(
        id: independentVariableID,
        name: independentVariableName,
        value: input)
      return expression.evaluate(parameters: [variable] + parameters)
    } catch {
      return .undefined(diagnostic: error.localizedDescription)
    }
  }

  private enum CodingKeys: CodingKey {
    case independentVariableID
    case independentVariableName
    case expression
  }

  /// Decodes and validates a stored function.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      independentVariableID: container.decode(
        ScalarParameterID.self,
        forKey: .independentVariableID),
      independentVariableName: container.decode(
        String.self,
        forKey: .independentVariableName),
      expression: container.decode(ScalarExpression.self, forKey: .expression))
  }
}

/// An explicit curve `y = f(x)` over a finite increasing domain.
public struct ExplicitCurveDefinition: Codable, Equatable, Sendable {
  /// The function that supplies each vertical coordinate.
  public let function: ScalarFunction1D

  /// The closed interval sampled along the horizontal axis.
  public let domain: ClosedRange<Double>

  /// Creates a validated explicit curve.
  public init(function: ScalarFunction1D, domain: ClosedRange<Double>) throws {
    try Self.validate(domain)
    self.function = function
    self.domain = domain
  }

  /// Samples finite points while preserving undefined gaps as separate branches.
  public func sample(
    sampleCount: Int,
    parameters: [ScalarParameter] = []
  ) throws -> CurveSampleResult {
    guard sampleCount >= 2 else {
      throw FunctionConstructionError.invalidSampleCount(minimum: 2)
    }
    let step = (domain.upperBound - domain.lowerBound) / Double(sampleCount - 1)
    var branches: [CurveSampleBranch] = []
    var currentPoints: [Point2D] = []
    var diagnostics: [CurveSamplingDiagnostic] = []
    var previousPoint: Point2D?

    for index in 0..<sampleCount {
      let input = domain.lowerBound + Double(index) * step
      let outcome = function.evaluate(at: input, parameters: parameters)
      if let value = outcome.value, value.isFinite {
        let point = Point2D(x: input, y: value)
        let diagnostic = previousPoint.flatMap {
          discontinuityDiagnostic(from: $0, to: point, parameters: parameters)
        }
        if let diagnostic {
          if !currentPoints.isEmpty {
            branches.append(CurveSampleBranch(points: currentPoints))
          }
          currentPoints = [point]
          diagnostics.append(diagnostic)
        } else {
          currentPoints.append(point)
        }
        previousPoint = point
      } else {
        if !currentPoints.isEmpty {
          branches.append(CurveSampleBranch(points: currentPoints))
          currentPoints = []
        }
        diagnostics.append(CurveSamplingDiagnostic(input: input, outcome: outcome))
        previousPoint = nil
      }
    }
    if !currentPoints.isEmpty {
      branches.append(CurveSampleBranch(points: currentPoints))
    }
    return CurveSampleResult(branches: branches, diagnostics: diagnostics)
  }

  private func discontinuityDiagnostic(
    from left: Point2D,
    to right: Point2D,
    parameters: [ScalarParameter]
  ) -> CurveSamplingDiagnostic? {
    let midpointInput = (left.x + right.x) / 2
    let midpointOutcome = function.evaluate(at: midpointInput, parameters: parameters)
    guard let midpointValue = midpointOutcome.value, midpointValue.isFinite else {
      return CurveSamplingDiagnostic(input: midpointInput, outcome: midpointOutcome)
    }
    let linearMidpoint = (left.y + right.y) / 2
    let endpointScale = max(1, max(abs(left.y), abs(right.y)))
    guard abs(midpointValue - linearMidpoint) > endpointScale * 8 else {
      return nil
    }
    return CurveSamplingDiagnostic(
      input: midpointInput,
      outcome: .undefined(
        diagnostic: "Sampling detected a discontinuity between adjacent inputs."))
  }

  private static func validate(_ domain: ClosedRange<Double>) throws {
    guard domain.lowerBound.isFinite, domain.upperBound.isFinite else {
      throw FunctionConstructionError.nonFiniteBounds
    }
    guard domain.lowerBound < domain.upperBound else {
      throw FunctionConstructionError.invalidBounds
    }
  }

  private enum CodingKeys: CodingKey {
    case function
    case domain
  }

  /// Decodes and validates a stored explicit curve.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      function: container.decode(ScalarFunction1D.self, forKey: .function),
      domain: container.decode(ClosedRange<Double>.self, forKey: .domain))
  }
}

/// One continuous run of finite samples from a curve.
public struct CurveSampleBranch: Equatable, Sendable {
  /// Ordered points that a renderer may connect within this branch.
  public let points: [Point2D]

  /// Creates a sampled curve branch.
  public init(points: [Point2D]) {
    self.points = points
  }
}

/// A structured record of an input that could not join a curve branch.
public struct CurveSamplingDiagnostic: Equatable, Sendable {
  /// The independent-variable value where sampling failed.
  public let input: Double

  /// The function evaluation explaining the gap.
  public let outcome: ScalarEvaluationOutcome

  /// Creates a diagnostic for an omitted curve input.
  public init(input: Double, outcome: ScalarEvaluationOutcome) {
    self.input = input
    self.outcome = outcome
  }
}

/// Sampled curve branches plus explicit diagnostics for omitted inputs.
public struct CurveSampleResult: Equatable, Sendable {
  /// Continuous finite branches; renderers must not connect separate entries.
  public let branches: [CurveSampleBranch]

  /// Undefined or non-finite evaluations encountered while sampling.
  public let diagnostics: [CurveSamplingDiagnostic]

  /// Creates a sampled curve result.
  public init(
    branches: [CurveSampleBranch],
    diagnostics: [CurveSamplingDiagnostic]
  ) {
    self.branches = branches
    self.diagnostics = diagnostics
  }
}
