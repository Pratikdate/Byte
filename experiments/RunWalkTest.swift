import Cocoa
import SceneKit

class WalkTestAppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    
    // Scene nodes
    var petContainer: SCNNode!
    var leftLeg: SCNNode!
    var rightLeg: SCNNode!
    var headNode: SCNNode!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let screenSize = NSScreen.main?.frame.size ?? CGSize(width: 800, height: 600)
        let rect = NSRect(x: screenSize.width/2 - 250, y: screenSize.height/2 - 250, width: 500, height: 500)
        
        window = NSWindow(contentRect: rect,
                          styleMask: [.titled, .closable, .resizable],
                          backing: .buffered,
                          defer: false)
        window.title = "Walk Animation Test"
        
        let scnView = SCNView(frame: rect)
        scnView.allowsCameraControl = true // You can drag to rotate the camera!
        scnView.showsStatistics = true
        scnView.backgroundColor = NSColor.darkGray
        
        window.contentView = scnView
        window.makeKeyAndOrderFront(nil)
        
        setupScene(in: scnView)
    }
    
    func setupScene(in view: SCNView) {
        let scene = SCNScene()
        view.scene = scene
        
        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 10)
        scene.rootNode.addChildNode(cameraNode)
        
        // Light
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light?.type = .omni
        lightNode.position = SCNVector3(0, 10, 10)
        scene.rootNode.addChildNode(lightNode)
        
        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light?.type = .ambient
        ambientLightNode.light?.color = NSColor.darkGray
        scene.rootNode.addChildNode(ambientLightNode)
        
        // Floor grid for reference
        let floor = SCNFloor()
        floor.firstMaterial?.diffuse.contents = NSColor.lightGray
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(0, -3.5, 0)
        scene.rootNode.addChildNode(floorNode)
        
        // --- PET SETUP ---
        petContainer = SCNNode()
        petContainer.eulerAngles = SCNVector3(0, CGFloat.pi / 2, 0) // Rotate 90 degrees to show side profile view!
        scene.rootNode.addChildNode(petContainer)
        
        // Head (just for reference bounce)
        let headGeo = SCNBox(width: 2.0, height: 1.6, length: 1.6, chamferRadius: 0.2)
        headGeo.firstMaterial?.diffuse.contents = NSColor.white
        headNode = SCNNode(geometry: headGeo)
        headNode.position = SCNVector3(0, 0, 0)
        petContainer.addChildNode(headNode)
        
        // Legs
        let legGeo = SCNBox(width: 0.6, height: 0.8, length: 0.6, chamferRadius: 0.1)
        legGeo.firstMaterial?.diffuse.contents = NSColor.black
        
        leftLeg = SCNNode(geometry: legGeo)
        leftLeg.pivot = SCNMatrix4MakeTranslation(0, 0.4, 0)
        leftLeg.position = SCNVector3(-0.8, -1.5, 0)
        petContainer.addChildNode(leftLeg)
        
        rightLeg = SCNNode(geometry: legGeo)
        rightLeg.pivot = SCNMatrix4MakeTranslation(0, 0.4, 0)
        rightLeg.position = SCNVector3(0.8, -1.5, 0)
        petContainer.addChildNode(rightLeg)
        
        // Shoes
        let shoeGeo = SCNBox(width: 1.4, height: 0.3, length: 1.8, chamferRadius: 0.1)
        shoeGeo.firstMaterial?.diffuse.contents = NSColor.orange
        
        let leftShoe = SCNNode(geometry: shoeGeo)
        leftShoe.position = SCNVector3(0, -0.4, 0.4)
        leftLeg.addChildNode(leftShoe)
        
        let rightShoe = SCNNode(geometry: shoeGeo)
        rightShoe.position = SCNVector3(0, -0.4, 0.4)
        rightLeg.addChildNode(rightShoe)
        
        // Start the test animation
        startWalkAnimation()
    }
    
    // ==========================================
    // MARK: - WALK ANIMATION LOGIC TO TWEAK
    // ==========================================
    func startWalkAnimation() {
        let duration: TimeInterval = 0.4
        
        // Head bobbing
        let bobUp = SCNAction.moveBy(x: 0, y: 0.25, z: 0, duration: duration / 2.0)
        bobUp.timingMode = .easeOut
        let bobDown = SCNAction.moveBy(x: 0, y: -0.25, z: 0, duration: duration / 2.0)
        bobDown.timingMode = .easeIn
        headNode.runAction(SCNAction.repeatForever(SCNAction.sequence([bobUp, bobDown])))
        
        // Leg Swings (using pivots)
        let swingRot: CGFloat = 0.8
        
        let swingForward = SCNAction.rotateTo(x: swingRot, y: 0, z: 0, duration: duration)
        swingForward.timingMode = .easeInEaseOut
        
        let swingBackward = SCNAction.rotateTo(x: -swingRot, y: 0, z: 0, duration: duration)
        swingBackward.timingMode = .easeInEaseOut
        
        leftLeg.runAction(SCNAction.repeatForever(SCNAction.sequence([swingForward, swingBackward])))
        rightLeg.runAction(SCNAction.repeatForever(SCNAction.sequence([swingBackward, swingForward])))
    }
}

let app = NSApplication.shared
let delegate = WalkTestAppDelegate()
app.delegate = delegate
app.run()
