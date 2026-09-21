/// The location within each subinterval used to sample a Riemann rectangle.
public enum RiemannSamplingRule: String, Codable, Equatable, Sendable {
  /// Samples the function at each subinterval's lower bound.
  case left

  /// Samples the function at each subinterval's upper bound.
  case right

  /// Samples the function halfway through each subinterval.
  case midpoint
}

/// A semantic Riemann-sum construction whose rectangles are derived on demand.
public struct RiemannSumDefinition: Codable, Equatable, Sendable {
  /// The function whose signed sum is approximated.
  public let function: ScalarFunction1D

  /// The finite increasing interval split into equal-width rectangles.
  public let interval: ClosedRange<Double>

  /// The positive number of rectangles.
  public let rectangleCount: Int

  /// The point chosen within each rectangle's subinterval.
  public let samplingRule: RiemannSamplingRule

  /// Creates a validated Riemann-sum definition.
  public init(
    function: ScalarFunction1D,
    interval: ClosedRange<Double>,
    rectangleCount: Int,
    samplingRule: RiemannSamplingRule
  ) throws {
    guard interval.lowerBound.isFinite, interval.upperBound.isFinite else {
      throw FunctionConstructionError.nonFiniteBounds
    }
    guard interval.lowerBound < interval.upperBound else {
      throw FunctionConstructionError.invalidBounds
    }
    guard rectangleCount > 0 else {
      throw FunctionConstructionError.invalidSampleCount(minimum: 1)
    }
    self.function = function
    self.interval = interval
    self.rectangleCount = rectangleCount
    self.samplingRule = samplingRule
  }

  /// Derives the rectangles and their signed floating-point sum.
  public func evaluate(parameters: [ScalarParameter] = []) -> RiemannSumResult {
    let width = (interval.upperBound - interval.lowerBound) / Double(rectangleCount)
    var rectangles: [RiemannRectangle2D] = []
    var signedSum = 0.0

    for index in 0..<rectangleCount {
      let lowerBound = interval.lowerBound + Double(index) * width
      let upperBound = lowerBound + width
      let sampleInput: Double
      switch samplingRule {
      case .left:
        sampleInput = lowerBound
      case .right:
        sampleInput = upperBound
      case .midpoint:
        sampleInput = (lowerBound + upperBound) / 2
      }
      let outcome = function.evaluate(at: sampleInput, parameters: parameters)
      guard let height = outcome.value, height.isFinite else {
        return RiemannSumResult(rectangles: [], signedSum: outcome)
      }
      let rectangle = RiemannRectangle2D(
        interval: lowerBound...upperBound,
        sampleInput: sampleInput,
        height: height,
        signedArea: height * width)
      rectangles.append(rectangle)
      signedSum += rectangle.signedArea
    }
    return RiemannSumResult(
      rectangles: rectangles,
      signedSum: .approximate(
        value: signedSum,
        diagnostic: "Finite \(samplingRule.rawValue) Riemann sum."))
  }

  private enum CodingKeys: CodingKey {
    case function
    case interval
    case rectangleCount
    case samplingRule
  }

  /// Decodes and validates a stored Riemann-sum definition.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      function: container.decode(ScalarFunction1D.self, forKey: .function),
      interval: container.decode(ClosedRange<Double>.self, forKey: .interval),
      rectangleCount: container.decode(Int.self, forKey: .rectangleCount),
      samplingRule: container.decode(RiemannSamplingRule.self, forKey: .samplingRule))
  }
}

/// One derived rectangle in a Riemann sum.
public struct RiemannRectangle2D: Equatable, Sendable {
  /// The horizontal subinterval occupied by the rectangle.
  public let interval: ClosedRange<Double>

  /// The input at which the rectangle height was evaluated.
  public let sampleInput: Double

  /// The signed vertical height of the rectangle.
  public let height: Double

  /// The signed product of width and height.
  public let signedArea: Double

  /// Creates a derived Riemann rectangle.
  public init(
    interval: ClosedRange<Double>,
    sampleInput: Double,
    height: Double,
    signedArea: Double
  ) {
    self.interval = interval
    self.sampleInput = sampleInput
    self.height = height
    self.signedArea = signedArea
  }
}

/// Derived Riemann rectangles and their structured signed sum.
public struct RiemannSumResult: Equatable, Sendable {
  /// Rectangles produced when every sample is defined; otherwise empty.
  public let rectangles: [RiemannRectangle2D]

  /// The approximate signed sum or the evaluation failure that prevented it.
  public let signedSum: ScalarEvaluationOutcome

  /// Creates a derived Riemann-sum result.
  public init(
    rectangles: [RiemannRectangle2D],
    signedSum: ScalarEvaluationOutcome
  ) {
    self.rectangles = rectangles
    self.signedSum = signedSum
  }
}
