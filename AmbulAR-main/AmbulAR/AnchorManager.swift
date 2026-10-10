// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu
// Licensed under AGPL-3.0-or-later with an additional permission
// under Section 7. See LICENSE for details.

import ARKit
import simd

final class AnchorManager {

    private(set) var anchors: [(anchor: ARAnchor, type: MarkerType, view: MarkerView, position: simd_float3)] = []

    @discardableResult
    func createAnchor(at position: simd_float3, type: MarkerType, in session: ARSession) -> ARAnchor {
        var transform = matrix_identity_float4x4
        transform.columns.3 = simd_float4(position.x, position.y, position.z, 1)

        let anchor = ARAnchor(transform: transform)
        session.add(anchor: anchor)
        let view = MarkerView()
        view.markerType = type
        anchors.append((anchor, type, view, position))

        print("[AnchorManager] Created \(type) anchor at position: (\(String(format: "%.3f", position.x)), \(String(format: "%.3f", position.y)), \(String(format: "%.3f", position.z)))")

        return anchor
    }

    func updateMarkerPositions(for frame: ARFrame, in view: UIView) {
        for (anchor, _, markerView, _) in anchors {
            let worldPosition = simd_float3(
                anchor.transform.columns.3.x,
                anchor.transform.columns.3.y,
                anchor.transform.columns.3.z
            )

            let projectedPoint: CGPoint
            if #available(iOS 27.0, *) {
                projectedPoint = frame.camera.projectPoint(
                    worldPosition,
                    viewRotationAngle: 0,
                    viewportSize: view.bounds.size
                )
            } else {
                projectedPoint = frame.camera.projectPoint(
                    worldPosition,
                    orientation: .landscapeRight,
                    viewportSize: view.bounds.size
                )
            }

            let cameraPosition = frame.camera.transform.columns.3
            let toAnchor = worldPosition - simd_float3(cameraPosition.x, cameraPosition.y, cameraPosition.z)
            let distance = length(toAnchor)

            let isInFront = toAnchor.z > 0
            let isInBounds = view.bounds.contains(CGPoint(x: projectedPoint.x, y: projectedPoint.y))

            if isInFront && isInBounds {
                markerView.center = CGPoint(x: projectedPoint.x, y: projectedPoint.y)
                markerView.isHidden = false
                markerView.debugText = "\(String(format: "%.1f", distance))m"
            } else {
                markerView.isHidden = true
            }
        }
    }

    func attachMarkers(to view: UIView) {
        for (_, _, markerView, _) in anchors {
            if markerView.superview == nil {
                view.addSubview(markerView)
            }
        }
    }

    func clearAll() {
        for (_, _, markerView, _) in anchors {
            markerView.removeFromSuperview()
        }
        anchors.removeAll()
    }
}
