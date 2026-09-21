import Foundation

/// Validation failures specific to two-variable functions and implicit curves.
public enum ImplicitCurveError: Error, Equatable, LocalizedError, Sendable {
  /// Both independent variables use the same identity or name.
  case conflictingIndependentVariables

  /// A human-readable explanation of the validation failure.
  public var errorDescription: String? {
    switch self {
    case .conflictingIndependentVariables:
      "The horizontal and vertical variables must have distinct identities and names."
    }
  }
}

/// A Codable real-valued function with two independent variables.
public struct ScalarFunction2D: Codable, Equatable, Sendable {
  /// The stable identity used for the horizontal variable.
  public let horizontalVariableID: ScalarParameterID

  /// The name used for the horizontal variable.
  public let horizontalVariableName: String

  /// The stable identity used for the vertical variable.
  public let verticalVariableID: ScalarParameterID

  /// The name used for the vertical variable.
  public let verticalVariableName: String

  /// The expression evaluated by this function.
  public let expression: ScalarExpression

  /// Creates a validated two-variable function.
  public init(
    horizontalVariableID: ScalarParameterID = ScalarParameterID(),
    horizontalVariableName: String = "x",
    verticalVariableID: ScalarParameterID = ScalarParameterID(),
    verticalVariableName: String = "y",
    expression: ScalarExpression
  ) throws {
    guard
      horizontalVariableID != verticalVariableID,
      horizontalVariableName != verticalVariableName
    else {
      throw ImplicitCurveError.conflictingIndependentVariables
    }
    guard
      !horizontalVariableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !verticalVariableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw FunctionConstructionError.emptyIndependentVariableName
    }
    try expression.validate()
    self.horizontalVariableID = horizontalVariableID
    self.horizontalVariableName = horizontalVariableName
    self.verticalVariableID = verticalVariableID
    self.verticalVariableName = verticalVariableName
    self.expression = expression
  }

  /// Evaluates the function at one finite point with optional additional parameters.
  public func evaluate(
    at point: Point2D,
    parameters: [ScalarParameter] = []
  ) -> ScalarEvaluationOutcome {
    guard point.isFinite else {
      return .undefined(diagnostic: "Both independent variables must be finite.")
    }
    guard !parameters.contains(where: conflictsWithIndependentVariable) else {
      return .undefined(
        diagnostic: "An additional parameter conflicts with an independent variable.")
    }
    do {
      let horizontal = try ScalarParameter(
        id: horizontalVariableID,
        name: horizontalVariableName,
        value: point.x)
      let vertical = try ScalarParameter(
        id: verticalVariableID,
        name: verticalVariableName,
        value: point.y)
      return expression.evaluate(parameters: [horizontal, vertical] + parameters)
    } catch {
      return .undefined(diagnostic: error.localizedDescription)
    }
  }

  private func conflictsWithIndependentVariable(_ parameter: ScalarParameter) -> Bool {
    parameter.id == horizontalVariableID
      || parameter.id == verticalVariableID
      || parameter.name == horizontalVariableName
      || parameter.name == verticalVariableName
  }

  private enum CodingKeys: CodingKey {
    case horizontalVariableID
    case horizontalVariableName
    case verticalVariableID
    case verticalVariableName
    case expression
  }

  /// Decodes and validates a stored two-variable function.
  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      horizontalVariableID: container.decode(
        ScalarParameterID.self,
        forKey: .horizontalVariableID),
      horizontalVariableName: container.decode(
        String.self,
        forKey: .horizontalVariableName),
      verticalVariableID: container.decode(
        ScalarParameterID.self,
        forKey: .verticalVariableID),
      verticalVariableName: container.decode(
        String.self,
        forKey: .verticalVariableName),
      expression: container.decode(ScalarExpression.self, forKey: .expression))
  }
}
