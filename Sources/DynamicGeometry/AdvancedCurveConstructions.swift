import Foundation

/// A curve defined by independent horizontal and vertical functions of one parameter.
public struct ParametricCurveDefinition: Codable, Equatable, Sendable {
  /// The function producing each horizontal coordinate.
  public let horizontalFunction: ScalarFunction1D

  /// The function producing each vertical coordinate.
  public let verticalFunction: ScalarFunction1D

  /// The finite increasing parameter interval sampled by the curve.
  public let parameterDomain: ClosedRange<Double>

  /// Creates a validated parametric curve definition.
  public init(
    horizontalFunction: ScalarFunction1D,
    verticalFunction: ScalarFunction1D,
    parameterDomain: ClosedRange<Double>
  ) throws {
    try validateAdvancedCurveDomain(parameterDomain)
    self.horizontalFunction = horizontalFunction
    self.verticalFunction = verticalFunction
    self.parameterDomain = parameterDomain
  }

  /// Samples ordered finite points from the parameter domain.
  public func sample(
    sampleCount: Int,
    parameters: [ScalarParameter] = []
  ) throws -> CurveSampleResult {
    try sampleAdvancedCurve(domain: parameterDomain, sampleCount: sampleCount) { input in
      let horizontalOutcome = horizontalFunction.evaluate(at: input, parameters: parameters)
      let verticalOutcome = verticalFunction.evaluate(at: input, parameters: parameters)
      guard let horizontal = horizontalOutcome.value else {
        return CurvePointEvaluation(failure: horizontalOutcome)
      }
      guard let vertical = verticalOutcome.value else {
        return CurvePointEvaluation(failure: verticalOutcome)
      }
      return CurvePointEvaluation(point: Point2D(x: horizontal, y: vertical))
    }
  }

  private enum CodingKeys: CodingKey {
    case horizontalFunction
    case verticalFunction
    case parameterDomain
  }

  /// Decodes and validates a stored parametric curve.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      horizontalFunction: container.decode(
        ScalarFunction1D.self,
        forKey: .horizontalFunction),
      verticalFunction: container.decode(
        ScalarFunction1D.self,
        forKey: .verticalFunction),
      parameterDomain: container.decode(
        ClosedRange<Double>.self,
        forKey: .parameterDomain))
  }
}

/// A curve defined by a radius function over a finite angle interval.
public struct PolarCurveDefinition: Codable, Equatable, Sendable {
  /// The function producing the signed radius for each angle.
  public let radiusFunction: ScalarFunction1D

  /// The finite increasing angle interval, in radians.
  public let angleDomain: ClosedRange<Double>

  /// The orientation used when converting polar samples to Cartesian points.
  public let coordinateSystem: CoordinateSystem2D

  /// Creates a validated polar curve definition.
  public init(
    radiusFunction: ScalarFunction1D,
    angleDomain: ClosedRange<Double>,
    coordinateSystem: CoordinateSystem2D = .cartesian
  ) throws {
    try validateAdvancedCurveDomain(angleDomain)
    self.radiusFunction = radiusFunction
    self.angleDomain = angleDomain
    self.coordinateSystem = coordinateSystem
  }

  /// Samples ordered finite Cartesian points from the polar definition.
  public func sample(
    sampleCount: Int,
    parameters: [ScalarParameter] = []
  ) throws -> CurveSampleResult {
    let verticalDirection = coordinateSystem == .cartesian ? 1.0 : -1.0
    return try sampleAdvancedCurve(domain: angleDomain, sampleCount: sampleCount) { angle in
      let outcome = radiusFunction.evaluate(at: angle, parameters: parameters)
      guard let radius = outcome.value else {
        return CurvePointEvaluation(failure: outcome)
      }
      return CurvePointEvaluation(
        point: Point2D(
          x: radius * cos(angle),
          y: verticalDirection * radius * sin(angle)))
    }
  }

  private enum CodingKeys: CodingKey {
    case radiusFunction
    case angleDomain
    case coordinateSystem
  }

  /// Decodes and validates a stored polar curve.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      radiusFunction: container.decode(ScalarFunction1D.self, forKey: .radiusFunction),
      angleDomain: container.decode(ClosedRange<Double>.self, forKey: .angleDomain),
      coordinateSystem: container.decode(
        CoordinateSystem2D.self,
        forKey: .coordinateSystem))
  }
}

private func validateAdvancedCurveDomain(_ domain: ClosedRange<Double>) throws {
  guard domain.lowerBound.isFinite, domain.upperBound.isFinite else {
    throw FunctionConstructionError.nonFiniteBounds
  }
  guard domain.lowerBound < domain.upperBound else {
    throw FunctionConstructionError.invalidBounds
  }
}

private struct CurvePointEvaluation {
  let point: Point2D?
  let failure: ScalarEvaluationOutcome?

  init(point: Point2D) {
    self.point = point
    failure = nil
  }

  init(failure: ScalarEvaluationOutcome) {
    point = nil
    self.failure = failure
  }
}

private struct CurveMidpointEvaluation {
  let input: Double
  let evaluation: CurvePointEvaluation
}

private struct AdvancedCurveSamplingState {
  var previousInput: Double?
  private var branches: [CurveSampleBranch] = []
  private var currentPoints: [Point2D] = []
  private var diagnostics: [CurveSamplingDiagnostic] = []

  mutating func append(
    _ evaluation: CurvePointEvaluation,
    input: Double,
    midpoint: CurveMidpointEvaluation?
  ) {
    guard let point = evaluation.point else {
      finishCurrentBranch()
      diagnostics.append(
        CurveSamplingDiagnostic(
          input: input,
          outcome: evaluation.failure ?? missingCurvePointOutcome))
      previousInput = nil
      return
    }
    if let midpoint {
      let branchBreak = currentPoints.last.flatMap { previousPoint in
        branchBreakOutcome(
          midpoint: midpoint.evaluation,
          between: previousPoint,
          and: point)
      }
      if let branchBreak {
        finishCurrentBranch()
        diagnostics.append(
          CurveSamplingDiagnostic(input: midpoint.input, outcome: branchBreak))
      }
    }
    currentPoints.append(point)
    previousInput = input
  }

  mutating func result() -> CurveSampleResult {
    finishCurrentBranch()
    return CurveSampleResult(branches: branches, diagnostics: diagnostics)
  }

  private mutating func finishCurrentBranch() {
    guard !currentPoints.isEmpty else { return }
    branches.append(CurveSampleBranch(points: currentPoints))
    currentPoints = []
  }
}

private func sampleAdvancedCurve(
  domain: ClosedRange<Double>,
  sampleCount: Int,
  evaluate: (Double) -> CurvePointEvaluation
) throws -> CurveSampleResult {
  guard sampleCount >= 2 else {
    throw FunctionConstructionError.invalidSampleCount(minimum: 2)
  }
  let step = (domain.upperBound - domain.lowerBound) / Double(sampleCount - 1)
  var state = AdvancedCurveSamplingState()
  for index in 0..<sampleCount {
    let input = domain.lowerBound + Double(index) * step
    let midpoint = state.previousInput.map { previousInput in
      let midpointInput = (previousInput + input) / 2
      return CurveMidpointEvaluation(
        input: midpointInput,
        evaluation: evaluate(midpointInput))
    }
    state.append(evaluate(input), input: input, midpoint: midpoint)
  }
  return state.result()
}

private func branchBreakOutcome(
  midpoint: CurvePointEvaluation,
  between left: Point2D,
  and right: Point2D
) -> ScalarEvaluationOutcome? {
  guard let midpointPoint = midpoint.point else {
    return midpoint.failure ?? missingCurvePointOutcome
  }
  return curveJumpOutcome(midpoint: midpointPoint, between: left, and: right)
}

private var missingCurvePointOutcome: ScalarEvaluationOutcome {
  .undefined(diagnostic: "A curve evaluation did not produce a finite point.")
}

private func curveJumpOutcome(
  midpoint: Point2D,
  between left: Point2D,
  and right: Point2D
) -> ScalarEvaluationOutcome? {
  let linearMidpoint = Point2D(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
  let endpointScale = max(
    1,
    max(abs(left.x), abs(left.y), abs(right.x), abs(right.y)))
  guard midpoint.distance(to: linearMidpoint) > endpointScale * 8 else {
    return nil
  }
  return .undefined(
    diagnostic: "Sampling detected a discontinuity between adjacent inputs.")
}
