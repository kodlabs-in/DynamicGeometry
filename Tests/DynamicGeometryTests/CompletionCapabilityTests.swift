import Testing

@testable import DynamicGeometry

@Suite("Completion capabilities")
struct CompletionCapabilityTests {
  @Test("Hosts can discover every first-gate mathematical construction")
  func discoversFirstGateConstructions() {
    let capabilities = GeometryCapabilities.current
    let required: [GeometryCapability] = [
      .scalarParameters,
      .scalarExpressions,
      .recoverableEvaluationStates,
      .explicitCurves,
      .discontinuitySafeSampling,
      .riemannSums,
      .referenceUnitCircle,
    ]

    for capability in required {
      #expect(capabilities.supports(capability))
    }
  }

  @Test("Hosts can discover the advanced mathematics roadmap capabilities")
  func discoversAdvancedMathematics() {
    let capabilities = GeometryCapabilities.current
    let required: [GeometryCapability] = [
      .parametricCurves,
      .polarCurves,
      .implicitCurves,
      .geometry3D,
      .affineTransforms3D,
      .parametricSurfaces,
      .symbolicSimplification,
      .symbolicDifferentiation,
      .polynomialSolving,
      .simultaneousConstraintSolver,
    ]

    for capability in required {
      #expect(capabilities.supports(capability))
    }
  }
}
