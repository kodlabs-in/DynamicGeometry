# DynamicGeometry

DynamicGeometry is a small, UI-independent Swift engine for building interactive geometric
constructions from reusable points, circles, segments, lines, rays, and derived points.

The engine stores relationships instead of frozen drawing coordinates. Move a free point or a
point constrained to a circle, and every dependent projection or segment resolves from the new
geometry. A host app remains responsible for rendering, gestures, selection, and persistence UI.

## What it provides

- Finite, Codable two-dimensional geometry values
- Distinct circle, segment, line, and ray semantics
- Free points and points constrained to a circle
- Horizontal and vertical projected points
- A dependency-aware scene with missing-reference and cycle detection
- Drag projection for both Cartesian and screen-y-down coordinate systems
- No UI framework, storage, analytics, or application-specific dependency

## Requirements

- Swift 6.0 or newer
- iOS or iPadOS 17+
- macOS 14+

## Installation

In Xcode, choose **File → Add Package Dependencies** and enter:

```text
https://github.com/kodlabs-in/DynamicGeometry.git
```

Select version `0.1.0` or add it to `Package.swift`:

```swift
dependencies: [
  .package(
    url: "https://github.com/kodlabs-in/DynamicGeometry.git",
    from: "0.1.0"
  )
]
```

Then add `DynamicGeometry` to the target that owns the construction model.

## Minimal construction

```swift
import DynamicGeometry

var scene = GeometryScene()
let center = try scene.addPoint(.free(Point2D(x: 0, y: 0)))
let circle = try scene.addCircle(center: center, radius: 1)
let movingPoint = try scene.addPoint(.onCircle(circle: circle, angleRadians: .pi / 4))
let radius = try scene.addSegment(start: center, end: movingPoint)

let point = try scene.point(movingPoint)
let segment = try scene.segment(radius)
```

For a touch-driven canvas whose y-axis points down, create the scene with
`GeometryScene(coordinateSystem: .screenYDown)`, then project a drag onto the circle with:

```swift
try scene.movePoint(movingPoint, to: dragLocation)
```

See [DynamicGeometrySandbox](https://github.com/kodlabs-in/DynamicGeometrySandbox) for a runnable
unit-circle construction.

## Development

```bash
make format
make check SWIFT_TEST_FLAGS=--disable-sandbox
make release-check SWIFT_TEST_FLAGS=--disable-sandbox
```

## License

DynamicGeometry is available under the [MIT License](LICENSE).
