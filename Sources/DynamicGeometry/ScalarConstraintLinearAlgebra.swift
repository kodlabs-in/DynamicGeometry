extension ScalarConstraintSystem {
  func evaluateResiduals(at values: [Double]) -> ResidualEvaluation {
    let variableParameters: [ScalarParameter]
    do {
      variableParameters = try zip(variables, values).map { variable, value in
        try ScalarParameter(id: variable.id, name: variable.name, value: value)
      }
    } catch {
      return .undefined("A constraint candidate contains a non-finite variable.")
    }
    let parameters = variableParameters + fixedParameters
    var result: [Double] = []
    for constraint in constraints {
      let left = constraint.left.evaluate(parameters: parameters)
      guard let leftValue = left.value else {
        return failure(from: left)
      }
      let right = constraint.right.evaluate(parameters: parameters)
      guard let rightValue = right.value else {
        return failure(from: right)
      }
      let residual = leftValue - rightValue
      guard residual.isFinite else {
        return .undefined("A constraint residual is non-finite.")
      }
      result.append(residual)
    }
    return .values(result)
  }

  func failure(from outcome: ScalarEvaluationOutcome) -> ResidualEvaluation {
    switch outcome {
    case .exact, .approximate:
      .undefined("A scalar outcome unexpectedly omitted its value.")
    case .undefined(let diagnostic):
      .undefined(diagnostic)
    case .unsupported(let diagnostic):
      .unsupported(diagnostic)
    case .nonconvergent(let diagnostic):
      .nonconvergent(diagnostic)
    case .pending(let diagnostic):
      .pending(diagnostic)
    }
  }

  func numericalJacobian(
    at values: [Double],
    baseline: [Double],
    relativeStep: Double
  ) -> JacobianEvaluation {
    var rows = Array(
      repeating: Array(repeating: 0.0, count: variables.count),
      count: constraints.count)
    for column in variables.indices {
      let step = relativeStep * max(1, abs(values[column]))
      var upperValues = values
      upperValues[column] += step
      var lowerValues = values
      lowerValues[column] -= step
      let columnEvaluation = jacobianColumn(
        upper: evaluateResiduals(at: upperValues),
        lower: evaluateResiduals(at: lowerValues),
        baseline: baseline,
        step: step)
      switch columnEvaluation {
      case .values(let derivatives):
        for row in constraints.indices {
          rows[row][column] = derivatives[row]
        }
      case .failure(let failure):
        return .failure(failure)
      }
    }
    return .matrix(rows)
  }

  func jacobianColumn(
    upper: ResidualEvaluation,
    lower: ResidualEvaluation,
    baseline: [Double],
    step: Double
  ) -> JacobianColumnEvaluation {
    switch (upper, lower) {
    case (.values(let upperResiduals), .values(let lowerResiduals)):
      return .values(zip(upperResiduals, lowerResiduals).map { ($0 - $1) / (2 * step) })
    case (.values(let upperResiduals), _):
      return .values(zip(upperResiduals, baseline).map { ($0 - $1) / step })
    case (_, .values(let lowerResiduals)):
      return .values(zip(baseline, lowerResiduals).map { ($0 - $1) / step })
    case (.undefined(let diagnostic), _), (_, .undefined(let diagnostic)):
      return .failure(.undefined(diagnostic))
    case (.unsupported(let diagnostic), _), (_, .unsupported(let diagnostic)):
      return .failure(.unsupported(diagnostic))
    case (.nonconvergent(let diagnostic), _), (_, .nonconvergent(let diagnostic)):
      return .failure(.nonconvergent(diagnostic))
    case (.pending(let diagnostic), _), (_, .pending(let diagnostic)):
      return .failure(.pending(diagnostic))
    }
  }

  enum JacobianColumnEvaluation {
    case values([Double])
    case failure(ResidualEvaluation)
  }

  func normalEquations(
    jacobian: [[Double]],
    residuals: [Double],
    damping: Double
  ) -> (matrix: [[Double]], vector: [Double]) {
    var matrix = Array(
      repeating: Array(repeating: 0.0, count: variables.count),
      count: variables.count)
    var vector = Array(repeating: 0.0, count: variables.count)
    for row in constraints.indices {
      for column in variables.indices {
        vector[column] -= jacobian[row][column] * residuals[row]
        for otherColumn in variables.indices {
          matrix[column][otherColumn] += jacobian[row][column] * jacobian[row][otherColumn]
        }
      }
    }
    for index in variables.indices {
      matrix[index][index] += damping
    }
    return (matrix, vector)
  }

  func solveLinearSystem(
    matrix: [[Double]],
    rightHandSide: [Double]
  ) -> [Double]? {
    var augmented = zip(matrix, rightHandSide).map { row, value in row + [value] }
    let count = rightHandSide.count
    for column in 0..<count {
      guard
        let pivot = (column..<count).max(by: {
          abs(augmented[$0][column]) < abs(augmented[$1][column])
        }),
        abs(augmented[pivot][column]) > 0.000_000_000_000_001
      else {
        return nil
      }
      augmented.swapAt(column, pivot)
      let divisor = augmented[column][column]
      for entry in column...count {
        augmented[column][entry] /= divisor
      }
      for row in 0..<count where row != column {
        let factor = augmented[row][column]
        for entry in column...count {
          augmented[row][entry] -= factor * augmented[column][entry]
        }
      }
    }
    return augmented.map { $0[count] }
  }

  func solution(
    values: [Double],
    residuals: [Double],
    iterationCount: Int
  ) -> ScalarConstraintSolution? {
    var parameters: [ScalarParameter] = []
    for (variable, value) in zip(variables, values) {
      guard
        let parameter = try? ScalarParameter(
          id: variable.id,
          name: variable.name,
          value: value)
      else {
        return nil
      }
      parameters.append(parameter)
    }
    return ScalarConstraintSolution(
      variables: parameters,
      residuals: residuals,
      iterationCount: iterationCount)
  }
}
