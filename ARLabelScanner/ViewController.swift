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

class ViewController: UIViewController {
    enum HitTestType: Int {
        case object1 = 0b0100
        case object2 = 0b0010
    }

    var firstBox = true
    var lastRoot: SCNNode? = nil

    @IBOutlet var sceneView: ARSCNView!
    var videoPreviewLayer: CALayer { return view.layer }

    private let templateBoxNode: SCNNode = {
        let box = SCNBox(width: 0.1524, height: 0.1016, length: 0.02, chamferRadius: 0)
        box.firstMaterial?.transparency = 0.5
        let color = UIColor.red.cgColor
        box.firstMaterial?.diffuse.contents = color
        let boxNode = SCNNode(geometry: box)
        boxNode.physicsBody = SCNPhysicsBody(type: .kinematic, shape: nil)
        boxNode.physicsBody?.isAffectedByGravity = false
        return boxNode
    }()

    func getBoxNode() -> SCNNode {
        let boxNode = templateBoxNode.copy() as! SCNNode
        boxNode.geometry = templateBoxNode.geometry?.copy() as? SCNGeometry
        boxNode.geometry?.firstMaterial = templateBoxNode.geometry?.firstMaterial?.copy() as? SCNMaterial
        if let orientation = sceneView.pointOfView?.orientation {
            boxNode.orientation = orientation
        }
        return boxNode
    }

    let startButton = UIButton.init(type: UIButtonType.custom)
    let stopButton = UIButton.init(type: UIButtonType.custom)
    let clearButton = UIButton.init(type: UIButtonType.custom)

    override func viewDidLoad() {
        super.viewDidLoad()
        startButton.frame = CGRect(x: 100, y: view.frame.maxY - 200, width: 100, height: 50)
        startButton.setTitle("Start", for: UIControlState.normal)
        startButton.addTarget(self, action:  #selector(start), for: .touchDown)
        stopButton.frame = CGRect(x: 0, y: view.frame.maxY - 200, width: 100, height: 50)
        stopButton.setTitle("Stop", for: UIControlState.normal)
        stopButton.addTarget(self, action:  #selector(stop), for: .touchDown)
        clearButton.frame = CGRect(x: view.frame.maxX - 200, y: view.frame.maxY - 200, width: 100, height: 50)
        clearButton.setTitle("Clear", for: UIControlState.normal)
        clearButton.addTarget(self, action: #selector(clear), for: .touchDown)


        sceneView.addSubview(startButton)
        sceneView.addSubview(stopButton)
        sceneView.addSubview(clearButton)

//        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.debugOptions = .showPhysicsShapes
        //sceneView.showsStatistics = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .vertical
//        sceneView.debugOptions = ARSCNDebugOptions.showFeaturePoints
        sceneView.session.run(configuration)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        sceneView.session.pause()
    }

//        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
//            let touch = touches.first!
//            let location = touch.location(in: sceneView)
//            let options: [SCNHitTestOption: Any] = [SCNHitTestOption.boundingBoxOnly: 1, SCNHitTestOption.categoryBitMask: HitTestType.object1.rawValue]
//            let hitResults = self.sceneView.hitTest(location, options: options)//.compactMap({$0.node.geometry as? SCNBox})
//            if let result = hitResults.first?.node.geometry {
//                result.firstMaterial?.diffuse.contents = (result.firstMaterial?.diffuse.contents as? UIColor) == UIColor.green
//                    ? UIColor.red
//                    : UIColor.green
//
//            }
//        }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let touch = touches.first!
        let location = touch.location(in: sceneView)
        markLabelAtLocation(location)
    }

    let timeInterval: TimeInterval = 1 / 10
    private var frameAnalysisTimer: Timer?

    var shouldAnalyzeFrame = true {
        didSet {
            if shouldAnalyzeFrame == false {
                frameAnalysisTimer?.invalidate()
                frameAnalysisTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false, block: { [weak self] _ in
                    self?.shouldAnalyzeFrame = true
                })
            }
        }
    }
}

//MARK: - ARSessionDelegate
extension ViewController: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard shouldAnalyzeFrame else {
            return
        }
        shouldAnalyzeFrame = false
        analyzePixelBuffer(frame.capturedImage)
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

        let detectLabelRectangleRequest = VNDetectRectanglesRequest(completionHandler: handleObservations)
        detectLabelRectangleRequest.minimumConfidence = 0.95
        detectLabelRectangleRequest.maximumObservations = 1
        let detectBarcodeRequest = VNDetectBarcodesRequest(completionHandler: handleObservations)
        detectBarcodeRequest.symbologies = [.code39]

        try? imageRequestHandler.perform([detectLabelRectangleRequest, detectBarcodeRequest])
    }

    func handleObservations(_ request: VNRequest, error: Error?) {
        guard let observations = request.results as? [VNDetectedObjectObservation],
            !observations.isEmpty else {
                return
        }

        let normalizedMidpoints: [CGPoint] = observations.map { observation in
            let midX = observation.boundingBox.midX
            let midY = observation.boundingBox.midY
            let midpoint = CGPoint(x: midX, y: midY)
            return midpoint
        }

        let imageMidpoints = normalizedMidpoints.map({VNImagePointForNormalizedPoint($0, Int(view.frame.width), Int(view.frame.height))})

        if observations is [VNBarcodeObservation] {
            handleBarcodeObservations(midPoints: imageMidpoints)
        } else if observations is [VNRectangleObservation] {
            observations.forEach({processForVisualDebugger($0 as! VNRectangleObservation)})
//            handleRectangleObservations(midPoints: imageMidpoints)
        }

    }

    func handleBarcodeObservations(midPoints: [CGPoint]) {
        midPoints.forEach(markLabelAtLocation)
    }

    func handleRectangleObservations(midPoints: [CGPoint]) {
        midPoints.forEach(addLabelAtLocation)
    }

    func markLabelAtLocation(_ point: CGPoint) {
        let bitMaskOption = [SCNHitTestOption.categoryBitMask: HitTestType.object1.rawValue]
        let hits = sceneView.hitTest(point, options: bitMaskOption)
        hits.first?.node.geometry?.firstMaterial?.diffuse.contents = UIColor.green
    }

    func addLabelAtLocation(_ point: CGPoint) {
        if let hit = sceneView.hitTest(point, types: .existingPlaneUsingGeometry).first {
            let position = SCNVector3(hit.worldTransform.columns.3.x, hit.worldTransform.columns.3.y, hit.worldTransform.columns.3.z)
            addBox(position: position)
        }
    }

    @objc func stop()  {
        sceneView.session.delegate = nil
        DispatchQueue.global(qos: .userInitiated).async { [unowned self] in
//            let clone = self.sceneView.scene.rootNode.flattenedClone()
            let clone = self.sceneView.scene.rootNode.clone()
            self.lastRoot = clone
            self.sceneView.scene.rootNode.childNodes.forEach({$0.removeFromParentNode()})
            self.firstBox = true
        }
    }

    @objc func start()  {
        sceneView.session.delegate = self
    }

    @objc func clear() {
        DispatchQueue.main.async {
            self.lastRoot = nil
            self.sceneView.scene.rootNode.childNodes.forEach({$0.removeFromParentNode()})
            self.firstBox = true
        }
    }


    func addBox(position: SCNVector3, debug: Bool = false) {
        let boxNode = getBoxNode()
        boxNode.position = position
        boxNode.categoryBitMask = HitTestType.object1.rawValue
        boxNode.physicsBody?.categoryBitMask = HitTestType.object1.rawValue

        let LOOK_AHEAD_DISTANCE: Float = 0.1
        let behind = SCNMatrix4Translate(boxNode.transform, 0, 0, -LOOK_AHEAD_DISTANCE)
        let upAhead = SCNMatrix4Translate(boxNode.transform, 0, 0, LOOK_AHEAD_DISTANCE)
        let physicsShape = SCNPhysicsShape(geometry: boxNode.geometry!, options: nil)
        let testOptions = [SCNPhysicsWorld.TestOption.collisionBitMask: HitTestType.object1.rawValue]
        let physicalContacts = sceneView.scene.physicsWorld.convexSweepTest(with: physicsShape,
                                                                            from: behind,
                                                                            to: upAhead,
                                                                            options: testOptions)
        guard physicalContacts.isEmpty else {
            return
        }


        if self.firstBox {
            defer { self.firstBox = false }
            self.sceneView.session.setWorldOrigin(relativeTransform: simd_float4x4.init(boxNode.transform))
            boxNode.position = SCNVector3.init(0, 0, 0)
            let firstNode: SCNNode
            if let lastRoot = self.lastRoot {
                firstNode = lastRoot
                firstNode.transform = boxNode.transform
//                let childNodePosition = firstNode.childNodes.first!.position
//                let newPosition = SCNVector3.init(
//                    firstNode.position.x - childNodePosition.x,
//                    firstNode.position.y - childNodePosition.y,
//                    firstNode.position.z - childNodePosition.z
//                )
//                firstNode.localTranslate(by: newPosition)
            } else {
                firstNode = boxNode
            }
            DispatchQueue.main.async {
                self.sceneView.scene.rootNode.addChildNode(firstNode)
            }
        } else {
            DispatchQueue.main.async {
                self.sceneView.scene.rootNode.addChildNode(boxNode)
            }
        }
    }

    private func processForVisualDebugger(_ point: CGPoint) {
        let imagePoint = VNImagePointForNormalizedPoint(point, Int(videoPreviewLayer.bounds.width), Int(videoPreviewLayer.bounds.height))
        let pointRect = rectFromPoint(imagePoint)
        drawRect(pointRect, color: .red, fillColor: .red)
    }

    private func processForVisualDebugger(_ observation: VNRectangleObservation) {
        let normalizedRect = observation.boundingBox
        let labelRect = VNImageRectForNormalizedRect(normalizedRect, Int(videoPreviewLayer.bounds.width), Int(videoPreviewLayer.bounds.height))
        DispatchQueue.main.async {
            self.drawRect(labelRect, color: .cyan)
        }
    }

    func rectFromPoint(_ point: CGPoint) -> CGRect {
        let side: CGFloat = 10
        return CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
    }

    func drawRect(_ rect: CGRect, color: UIColor, fillColor: UIColor? = nil) {
        let layer = CAShapeLayer()
        layer.path = CGPath.init(rect: rect, transform: nil)
        layer.strokeColor = color.cgColor
        layer.fillColor = fillColor?.cgColor ?? UIColor.clear.cgColor
        view.layer.addSublayer(layer)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            layer.removeFromSuperlayer()
        }
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
        planeNode.physicsBody?.collisionBitMask = HitTestType.object2.rawValue
        planeNode.physicsBody?.contactTestBitMask = HitTestType.object2.rawValue
        planeNode.physicsBody?.categoryBitMask = HitTestType.object2.rawValue

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

