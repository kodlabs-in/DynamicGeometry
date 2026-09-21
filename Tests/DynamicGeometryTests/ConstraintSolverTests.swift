import Foundation
import Testing

@testable import DynamicGeometry

@Suite("Simultaneous scalar constraints")
struct ConstraintSolverTests {
  @Test("Two coupled linear equalities converge as one isolated system")
  func solvesCoupledLinearEqualities() throws {
    let xID = ScalarParameterID()
    let yID = ScalarParameterID()
    let x = ScalarExpression.parameter(.identified(xID))
    let y = ScalarExpression.parameter(.identified(yID))
    let system = try ScalarConstraintSystem(
      variables: [
        ScalarParameter(id: xID, name: "x", value: 0),
        ScalarParameter(id: yID, name: "y", value: 0),
      ],
      constraints: [
        ScalarEqualityConstraint(
          left: .arithmetic(left: x, operation: .addition, right: y),
          right: .constant(3)),
        ScalarEqualityConstraint(
          left: .arithmetic(left: x, operation: .subtraction, right: y),
          right: .constant(1)),
      ])

    let outcome = system.solve()
    guard case .converged(let solution) = outcome else {
      Issue.record("Expected a converged solution, received \(outcome)")
      return
    }

    let solvedX = try #require(solution.value(for: xID))
    let solvedY = try #require(solution.value(for: yID))
    #expect(abs(solvedX - 2) <= 0.000_001)
    #expect(abs(solvedY - 1) <= 0.000_001)
    #expect(solution.maximumAbsoluteResidual <= 0.000_001)
  }

  @Test("A nonlinear circle-line intersection follows the initial local branch")
  func solvesNonlinearCircleLineIntersection() throws {
    let xID = ScalarParameterID()
    let yID = ScalarParameterID()
    let x = ScalarExpression.parameter(.identified(xID))
    let y = ScalarExpression.parameter(.identified(yID))
    let square: (ScalarExpression) -> ScalarExpression = {
      .arithmetic(left: $0, operation: .power, right: .constant(2))
    }
    let system = try ScalarConstraintSystem(
      variables: [
        ScalarParameter(id: xID, name: "x", value: 0.8),
        ScalarParameter(id: yID, name: "y", value: 0.6),
      ],
      constraints: [
        ScalarEqualityConstraint(
          left: .arithmetic(left: square(x), operation: .addition, right: square(y)),
          right: .constant(1)),
        ScalarEqualityConstraint(left: x, right: y),
      ])

    let outcome = system.solve()
    guard case .converged(let solution) = outcome else {
      Issue.record("Expected the positive local intersection, received \(outcome)")
      return
    }
    let expected = sqrt(0.5)

    let solvedX = try #require(solution.value(for: xID))
    let solvedY = try #require(solution.value(for: yID))
    #expect(abs(solvedX - expected) <= 0.000_001)
    #expect(abs(solvedY - expected) <= 0.000_001)
    #expect(solution.iterationCount > 0)
  }

  @Test("A zero time budget stops with the finite initial candidate")
  func respectsTimeBudget() throws {
    let xID = ScalarParameterID()
    let x = ScalarExpression.parameter(.identified(xID))
    let system = try ScalarConstraintSystem(
      variables: [ScalarParameter(id: xID, name: "x", value: 100)],
      constraints: [ScalarEqualityConstraint(left: x, right: .constant(0))])
    let options = ScalarConstraintSolverOptions(maximumDurationSeconds: 0)

    let outcome = system.solve(options: options)
    guard case .nonconvergent(let best, let diagnostic) = outcome else {
      Issue.record("Expected the time limit to stop the solve, received \(outcome)")
      return
    }

    #expect(best?.value(for: xID) == 100)
    #expect(diagnostic.localizedCaseInsensitiveContains("time"))
  }

  @Test("Decoding cannot bypass unique variable names")
  func decodingRevalidatesConstraintSystem() throws {
    let xID = ScalarParameterID()
    let yID = ScalarParameterID()
    let system = try ScalarConstraintSystem(
      variables: [
        ScalarParameter(id: xID, name: "x", value: 0),
        ScalarParameter(id: yID, name: "y", value: 0),
      ],
      constraints: [
        ScalarEqualityConstraint(
          left: .parameter(.identified(xID)),
          right: .parameter(.identified(yID)))
      ])
    var object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(system)) as? [String: Any])
    var variables = try #require(object["variables"] as? [[String: Any]])
    variables[1]["name"] = "x"
    object["variables"] = variables
    let invalidData = try JSONSerialization.data(withJSONObject: object)

    do {
      _ = try JSONDecoder().decode(ScalarConstraintSystem.self, from: invalidData)
      Issue.record("Expected decoded duplicate names to be rejected")
    } catch let error as ScalarConstraintSystemError {
      #expect(error == .duplicateParameterName("x"))
    }
  }

  @Test("An undefined initial domain is reported instead of replaced with zero")
  func reportsUndefinedInitialDomain() throws {
    let xID = ScalarParameterID()
    let system = try ScalarConstraintSystem(
      variables: [ScalarParameter(id: xID, name: "x", value: -1)],
      constraints: [
        ScalarEqualityConstraint(
          left: .function(
            .naturalLogarithm,
            argument: .parameter(.identified(xID))),
          right: .constant(0))
      ])

    let outcome = system.solve()
    guard case .undefined(let diagnostic) = outcome else {
      Issue.record("Expected an undefined logarithm domain, received \(outcome)")
      return
    }

    #expect(diagnostic.localizedCaseInsensitiveContains("positive"))
  }

  @Test("An impossible real equality returns the best finite candidate")
  func reportsNonconvergence() throws {
    let xID = ScalarParameterID()
    let x = ScalarExpression.parameter(.identified(xID))
    let system = try ScalarConstraintSystem(
      variables: [ScalarParameter(id: xID, name: "x", value: 0)],
      constraints: [
        ScalarEqualityConstraint(
          left: .arithmetic(left: x, operation: .power, right: .constant(2)),
          right: .constant(-1))
      ])
    let options = ScalarConstraintSolverOptions(
      maximumIterations: 4,
      maximumDurationSeconds: nil)

    let outcome = system.solve(options: options)
    guard case .nonconvergent(let best, let diagnostic) = outcome else {
      Issue.record("Expected a bounded nonconvergent result, received \(outcome)")
      return
    }

    #expect(best?.maximumAbsoluteResidual == 1)
    #expect(diagnostic.localizedCaseInsensitiveContains("iteration"))
  }
}
