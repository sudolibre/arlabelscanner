//
//  ViewController.swift
//  PointCloud
//
//  Created by Jon Day on 10/27/17.
//  Copyright © 2017 com.metal.preprocessing. All rights reserved.
//

import UIKit
import SceneKit
import ARKit
import Vision

class DetectLabelRectangleRequest: VNDetectRectanglesRequest {
    override init(completionHandler: VNRequestCompletionHandler?) {
        super.init(completionHandler: completionHandler)

        minimumAspectRatio = 1.95
        maximumAspectRatio = 2.2
        maximumObservations = 3
        minimumConfidence = 0.9
    }
}

class LabelDetector {
    var labelHandler: ([CGPoint]) -> Void

    init(labelHandler: @escaping ([CGPoint]) -> Void) {
        self.labelHandler = labelHandler
    }

    func analyzePixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        var width = CVPixelBufferGetWidth(pixelBuffer)
        var height = CVPixelBufferGetHeight(pixelBuffer)

        var requestOptions: [VNImageOption: Any] = [:]

        if let cameraIntrinsics = CMGetAttachment(pixelBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil) {
            requestOptions = [.cameraIntrinsics: cameraIntrinsics]
        }

        let interfaceOrientation = UIApplication.shared.statusBarOrientation
        guard let orientation = CGImagePropertyOrientation(interfaceOrientation: interfaceOrientation) else {
            return
        }

        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: requestOptions)

        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            swap(&width, &height)
        case .up, .upMirrored, .down, .downMirrored:
            break
        }

        let detectLabelRectangleRequest = DetectLabelRectangleRequest(completionHandler: handleRectangleObservations)

        try? imageRequestHandler.perform([detectLabelRectangleRequest])
    }

    func handleRectangleObservations(_ request: VNRequest, error: Error?) {
        guard let observations = request.results?.compactMap({$0 as? VNRectangleObservation}),
            !observations.isEmpty else {
                return
        }
        //            processForVisualDebugger($0)
        let normalizedMidpoints = observations.map(midpoint)
        labelHandler(normalizedMidpoints)
    }

    func midpoint(from observation: VNRectangleObservation) -> CGPoint {
        let boundingBox = observation.boundingBox
        return CGPoint(x: boundingBox.midX, y: boundingBox.midY)
    }

}

class ViewController: UIViewController {
    @IBOutlet var sceneView: ARSCNView!
    var videoPreviewLayer: CALayer { return view.layer }
    lazy var labelDetector = LabelDetector(labelHandler: self.labelHandler)

    private let templateBoxNode: SCNNode = {
        let box = SCNBox(width: 0.10795, height: 0.0508, length: 0.1, chamferRadius: 0)
        box.firstMaterial?.transparency = 0.5
        let color = UIColor.red.cgColor
        box.firstMaterial?.diffuse.contents = color
        let boxNode = SCNNode(geometry: box)
        boxNode.physicsBody = SCNPhysicsBody(type: .kinematic, shape: nil)
        boxNode.physicsBody?.isAffectedByGravity = false
        boxNode.physicsBody?.contactTestBitMask = 1
        boxNode.physicsBody?.categoryBitMask = HitTestType.object1.rawValue
        return boxNode
    }()

    func getBoxNode() -> SCNNode {
        let boxNode = templateBoxNode.clone()
        if let orientation = sceneView.pointOfView?.orientation {
            boxNode.orientation = orientation
        }
        return boxNode
    }

    func labelHandler(normalizedMidpoints: ([CGPoint])) {
        normalizedMidpoints.forEach { normalizedMidpoint in
            let imageMidpoint = VNImagePointForNormalizedPoint(normalizedMidpoint, Int(view.frame.width), Int(view.frame.height))

            if let hit = sceneView.hitTest(imageMidpoint, types: .existingPlaneUsingGeometry).first {
                let position = SCNVector3(hit.worldTransform.columns.3.x, hit.worldTransform.columns.3.y, hit.worldTransform.columns.3.z)
                addBox(position: position)
            }
        }
    }

    func addBox(position: SCNVector3) {
        let boxNode = getBoxNode()
        boxNode.position = position

        let LOOK_AHEAD_DISTANCE: Float = 5.0
        let behind = SCNMatrix4Translate(boxNode.transform, 0, 0, -LOOK_AHEAD_DISTANCE);
        let upAhead = SCNMatrix4Translate(boxNode.transform, 0, 0, LOOK_AHEAD_DISTANCE);

        let physicalContacts = sceneView.scene.physicsWorld.convexSweepTest(with: SCNPhysicsShape(node: boxNode, options: nil), from: behind, to: upAhead, options: nil)

        guard physicalContacts.isEmpty else {
            return
        }

        DispatchQueue.main.async {
            self.sceneView.scene.rootNode.addChildNode(boxNode)
        }
    }

    private func processForVisualDebugger(_ observation: VNRectangleObservation) {
        DispatchQueue.main.async {
            self.barcodeManager(didDetectLabel: observation.boundingBox, corners: [observation.topLeft, observation.topRight, observation.bottomLeft, observation.bottomRight])
        }
    }

    func barcodeManager(didDetectLabel label: CGRect, corners: [CGPoint]) {
        //clearRects()
        let labelRect = normalizeToImageRect(label)
        let cornerPoints = corners.map(normalizeToImagePoint)
        let cornerRects: [CGRect] = cornerPoints.map {
            let side: CGFloat = 10
            return CGRect(x: $0.x - side / 2, y: $0.y - side / 2, width: side, height: side)
        }
        drawRect(labelRect, color: .cyan)
        cornerRects.forEach({drawRect($0, color: .blue, fillColor: .blue)})
    }

    func normalizeToImagePoint(_ point: CGPoint) -> CGPoint {
        return VNImagePointForNormalizedPoint(point, Int(videoPreviewLayer.bounds.width), Int(videoPreviewLayer.bounds.height))
    }

    func normalizeToImageRect(_ rect: CGRect) -> CGRect {
        return VNImageRectForNormalizedRect(rect, Int(videoPreviewLayer.bounds.width), Int(videoPreviewLayer.bounds.height))
    }

    func clearRects(force: Bool = false) {
        view.layer.sublayers?.forEach({if $0 is CAShapeLayer { $0.removeFromSuperlayer()}})
    }

    func drawRect(_ rect: CGRect, color: UIColor, fillColor: UIColor? = nil) {
        let layer = CAShapeLayer()
        layer.path = CGPath.init(rect: rect, transform: nil)
        layer.strokeColor = color.cgColor
        layer.fillColor = fillColor?.cgColor ?? UIColor.clear.cgColor
        view.layer.addSublayer(layer)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            layer.removeFromSuperlayer()
        }
    }
    enum HitTestType: Int {
        case object1 = 0b0001
        case object2 = 0b0010
    }


    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let touch = touches.first!
        let location = touch.location(in: sceneView)
        let options: [SCNHitTestOption: Any] = [SCNHitTestOption.boundingBoxOnly: 1, SCNHitTestOption.categoryBitMask: HitTestType.object1.rawValue]
        let hitResults = self.sceneView.hitTest(location, options: options).compactMap({$0.node.geometry as? SCNBox})
        if let result = hitResults.first {
            result.firstMaterial?.diffuse.contents = UIColor.green
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        sceneView.delegate = self
        sceneView.session.delegate = self
        //sceneView.debugOptions = [SCNDebugOptions(rawValue: ARSCNDebugOptions.showFeaturePoints.rawValue)]
        sceneView.showsStatistics = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .vertical

        sceneView.session.run(configuration)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        sceneView.session.pause()
    }
}

//MARK: - ARSessionDelegate
extension ViewController: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        labelDetector.analyzePixelBuffer(frame.capturedImage)
    }
}

// MARK: - ARSCNViewDelegate
extension ViewController: ARSCNViewDelegate {
    func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard let planeAnchor = anchor as? ARPlaneAnchor,
            planeAnchor.alignment == .vertical else {
                return nil
        }

        let scenePlaneGeometry = ARSCNPlaneGeometry(device: MTLCreateSystemDefaultDevice()!)
        scenePlaneGeometry?.update(from: planeAnchor.geometry)

        let planeNode = SCNNode(geometry: scenePlaneGeometry)
        planeNode.geometry?.firstMaterial?.diffuse.contents = UIColor.cyan.withAlphaComponent(0.5)

        return planeNode
    }

    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor,
            planeAnchor.alignment == .vertical,
            let planeGeometry = node.geometry as? ARSCNPlaneGeometry else {
                return
        }

        planeGeometry.update(from: planeAnchor.geometry)
    }

}

extension CGImagePropertyOrientation {
    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait:
            self = .rightMirrored
        case .portraitUpsideDown:
            self = .leftMirrored
        case .landscapeRight:
            self = .downMirrored
        case .landscapeLeft:
            self = .upMirrored
        case .unknown:
            return nil
        }
    }
}

