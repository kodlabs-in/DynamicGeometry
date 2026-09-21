import Foundation

extension ScalarConstraintSystem {
  enum ResidualEvaluation {
    case values([Double])
    case undefined(String)
    case unsupported(String)
    case nonconvergent(String)
    case pending(String)

    var outcome: ScalarConstraintSolveOutcome {
      switch self {
      case .values:
        .unsupported(diagnostic: "An internal residual result was used as a failure.")
      case .undefined(let diagnostic):
        .undefined(diagnostic: diagnostic)
      case .unsupported(let diagnostic):
        .unsupported(diagnostic: diagnostic)
      case .nonconvergent(let diagnostic):
        .nonconvergent(best: nil, diagnostic: diagnostic)
      case .pending(let diagnostic):
        .pending(diagnostic: diagnostic)
      }
    }
  }

  enum JacobianEvaluation {
    case matrix([[Double]])
    case failure(ResidualEvaluation)

    var outcome: ScalarConstraintSolveOutcome {
      switch self {
      case .matrix:
        .unsupported(diagnostic: "An internal Jacobian result was used as a failure.")
      case .failure(let failure):
        failure.outcome
      }
    }
  }

  struct SolverState {
    var values: [Double]
    var residuals: [Double]
    var best: ScalarConstraintSolution
    var damping: Double
  }

  enum SolverPreparation {
    case ready(SolverState)
    case finished(ScalarConstraintSolveOutcome)
  }

  enum IterationStep {
    case next(SolverState)
    case finished(ScalarConstraintSolveOutcome)
  }

  func prepareConstraintSolve(
    options: ScalarConstraintSolverOptions
  ) -> SolverPreparation {
    let values = variables.map(\.value)
    let initialEvaluation = evaluateResiduals(at: values)
    guard case .values(let residuals) = initialEvaluation else {
      return .finished(initialEvaluation.outcome)
    }
    guard let best = solution(values: values, residuals: residuals, iterationCount: 0) else {
      return .finished(
        .undefined(diagnostic: "The initial constraint candidate is not finite."))
    }
    guard best.maximumAbsoluteResidual > options.residualTolerance else {
      return .finished(.converged(best))
    }
    return .ready(
      SolverState(
        values: values,
        residuals: residuals,
        best: best,
        damping: options.initialDamping))
  }

  func solveIterations(
    from initialState: SolverState,
    options: ScalarConstraintSolverOptions
  ) -> ScalarConstraintSolveOutcome {
    var state = initialState
    let startTime = Date.timeIntervalSinceReferenceDate
    for iteration in 1...options.maximumIterations {
      if reachedTimeLimit(startTime: startTime, options: options) {
        return .nonconvergent(
          best: state.best,
          diagnostic: "The solver reached its time limit before satisfying every equality.")
      }
      switch performIteration(state: state, iteration: iteration, options: options) {
      case .finished(let outcome):
        return outcome
      case .next(let updatedState):
        state = updatedState
      }
      if state.best.maximumAbsoluteResidual <= options.residualTolerance {
        return .converged(state.best)
      }
    }
    return .nonconvergent(
      best: state.best,
      diagnostic: "The solver reached its iteration limit without satisfying every equality.")
  }

  func performIteration(
    state: SolverState,
    iteration: Int,
    options: ScalarConstraintSolverOptions
  ) -> IterationStep {
    let jacobianEvaluation = numericalJacobian(
      at: state.values,
      baseline: state.residuals,
      relativeStep: options.finiteDifferenceStep)
    guard case .matrix(let jacobian) = jacobianEvaluation else {
      return .finished(jacobianEvaluation.outcome)
    }
    let normal = normalEquations(
      jacobian: jacobian,
      residuals: state.residuals,
      damping: state.damping)
    guard let delta = solveLinearSystem(matrix: normal.matrix, rightHandSide: normal.vector) else {
      return .finished(
        .nonconvergent(
          best: state.best,
          diagnostic: "The local constraint Jacobian is singular at the current candidate."))
    }
    let candidateValues = zip(state.values, delta).map(+)
    guard candidateValues.allSatisfy(\.isFinite) else {
      return .finished(
        .undefined(diagnostic: "A constraint iteration produced a non-finite variable."))
    }
    return evaluateCandidate(
      values: candidateValues,
      previousState: state,
      iteration: iteration)
  }

  func evaluateCandidate(
    values: [Double],
    previousState: SolverState,
    iteration: Int
  ) -> IterationStep {
    let evaluation = evaluateResiduals(at: values)
    guard case .values(let residuals) = evaluation else {
      var state = previousState
      state.damping = increasedDamping(state.damping)
      return .next(state)
    }
    guard
      let candidate = solution(
        values: values,
        residuals: residuals,
        iterationCount: iteration)
    else {
      return .finished(.undefined(diagnostic: "A constraint candidate is not finite."))
    }
    guard candidate.maximumAbsoluteResidual < previousState.best.maximumAbsoluteResidual else {
      var state = previousState
      state.damping = increasedDamping(state.damping)
      return .next(state)
    }
    return .next(
      SolverState(
        values: values,
        residuals: residuals,
        best: candidate,
        damping: max(previousState.damping / 10, 0.000_000_000_001)))
  }

  func reachedTimeLimit(
    startTime: TimeInterval,
    options: ScalarConstraintSolverOptions
  ) -> Bool {
    guard let maximumDuration = options.maximumDurationSeconds else { return false }
    return Date.timeIntervalSinceReferenceDate - startTime >= maximumDuration
  }

  func increasedDamping(_ damping: Double) -> Double {
    min(damping * 10, 1_000_000_000_000)
  }
}
