import SceneKit
import SpriteKit
import AppKit
import AVFoundation

// MARK: - Particle Types
enum ParticleType {
    case heart
    case zzz
    case sparkle
    case sweat
    case angryCloud
}

class PetScene: SCNScene {
    private var petContainer: SCNNode!
    
    // Robot 3D Parts
    private var headNode: SCNNode!
    private var leftLeg: SCNNode!
    private var rightLeg: SCNNode!
    private var leftHeadphone: SCNNode!
    private var rightHeadphone: SCNNode!
    private var headphoneBandNode: SCNNode!
    
    // 2D Screen (Mapped to 3D)
    private var screenScene: SKScene!
    private var eyeContainer: SKEffectNode!
    private var leftEye: SKShapeNode!
    private var rightEye: SKShapeNode!
    
    // Emotion specific nodes
    private var leftTear: SKShapeNode!
    private var rightTear: SKShapeNode!
    private var leftBlush: SKShapeNode!
    private var rightBlush: SKShapeNode!
    
    // Speech
    private var speechBubble: SKLabelNode!
    private var speechBubbleBG: SKSpriteNode?
    private var speechContainer: SKNode?
    private var speechBubbleSKScene: SKScene!
    private var speechBubbleNode: SCNNode!
    // Removed local synthesizer; using VoiceInputManager.speak() instead for emotion-aware TTS
    private var pendingSpeechTexts: [String] = []
    
    // Particle Emitter Layer
    private var particleContainer: SKNode?
    
    // State Engine
    var brain = PetBrain()
    private var lastMouseLocation: NSPoint = .zero
    private var mouseScrubDistance: CGFloat = 0
    private var lastScrubTime: TimeInterval = 0
    private var targetPosition: CGPoint?
    
    // Idle looking
    private var randomLookTargetX: CGFloat = 0
    private var randomLookTargetY: CGFloat = 0
    private var lastLookChangeTime: TimeInterval = 0
    
    // Interaction
    var isDragging = false
    private var dragOffset: CGPoint = .zero
    
    // Physics State
    private var isFalling = false
    private var velocityX: CGFloat = 0
    private var velocityY: CGFloat = 0
    private var lastDragWorldLocation: CGPoint = .zero
    private var lastDragTime: TimeInterval = 0
    private var lastClickTime: TimeInterval = 0
    var isMuted = false
    
    // Manual interaction offsets
    private var manualRotationY: CGFloat = 0.0
    
    // Spatial command tracking
    private var pendingSpatialAction: PetAction? = nil
    private var lastIdleReturnTime: TimeInterval = 0
    private var lastSneezeCheckTime: TimeInterval = 0
    
    // Step-based Walk System
    private var walkTargetX: CGFloat = 0
    private var walkTargetY: CGFloat = 0
    private var walkDirectionX: CGFloat = 1
    private var walkDirectionY: CGFloat = 0
    private let groundY: CGFloat = -3.0  // Raised to -3.0 so it stands above the macOS Dock
    private var isWalking = false
    
    // Laser Pointer Game
    var isLaserPointerActive: Bool = false {
        didSet {
            laserNode?.isHidden = !isLaserPointerActive
            if isLaserPointerActive {
                brain.currentAction = .chaseLaser
                brain.currentEmotion = .excited
            } else if brain.currentAction == .chaseLaser {
                brain.applyAction(.idle)
            }
        }
    }
    private var laserNode: SCNNode!
    
    // Virtual Treats
    private var treatNode: SCNNode?
    
    override init() {
        super.init()
        // TTS now handled via VoiceInputManager with emotion awareness
        EnvironmentMonitor.shared.startMonitoring()
        DesktopEnvironmentManager.shared.startMonitoring()
        setup3DEnvironment()
        setup3DRobot()
        startIdleAnimation()
        
        brain.onSentenceGenerated = { [weak self] sentence in
            self?.saySentence(sentence)
        }
        
        brain.onSpeechComplete = { [weak self] in
            self?.finishSpeech()
        }
        
        brain.onStartWalk = { [weak self] targetX, targetY in
            self?.startWalk(toX: targetX, toY: targetY)
        }
        
        // Particle callback from PetBrain
        brain.onShowParticle = { [weak self] type in
            self?.showParticle(type)
        }
        
        // Spatial command callback: walk to target then perform action on arrival
        brain.onSpatialCommand = { [weak self] action, targetX, targetY in
            self?.pendingSpatialAction = action
            self?.startWalk(toX: targetX, toY: targetY)
        }
        
        // (petContainer Y is already set to groundY in setup3DRobot)
        
        // Setup Update Loop on Main Thread (60 FPS) to prevent cross-thread SpriteKit/SceneKit races
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick(currentTime: Date().timeIntervalSince1970)
        }
        RunLoop.main.add(timer, forMode: .common)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setup3DEnvironment() {
        self.background.contents = NSColor.clear
        
        // Ambient Light
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = NSColor(white: 0.25, alpha: 1.0) // Darker ambient for richer shadows
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        rootNode.addChildNode(ambientNode)
        
        // Directional Light with Shadows
        let directionalLight = SCNLight()
        directionalLight.type = .directional
        directionalLight.color = NSColor(white: 0.9, alpha: 1.0)
        directionalLight.castsShadow = true
        directionalLight.shadowMode = .deferred
        directionalLight.shadowSampleCount = 16 // Smoother shadows
        directionalLight.shadowMapSize = CGSize(width: 2048, height: 2048)
        let lightNode = SCNNode()
        lightNode.light = directionalLight
        lightNode.position = SCNVector3(x: -8, y: 15, z: 12) // Angle it better
        lightNode.look(at: SCNVector3(0, 0, 0))
        rootNode.addChildNode(lightNode)
        
        // Camera
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 7 // Adjust scale for desktop
        camera.zNear = 0.1
        camera.zFar = 100
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(x: 0, y: 1, z: 20)
        rootNode.addChildNode(cameraNode)
        
        // Invisible Floor (Only catches shadows)
        let floor = SCNFloor()
        floor.reflectivity = 0
        floor.firstMaterial?.colorBufferWriteMask = [] // Invisible but catches shadows!
        let floorNode = SCNNode(geometry: floor)
        floorNode.position = SCNVector3(0, -3.5, 0)
        rootNode.addChildNode(floorNode)
        
        // Laser Pointer Node
        let laserGeo = SCNSphere(radius: 0.3)
        let laserMat = SCNMaterial()
        laserMat.diffuse.contents = NSColor.red
        laserMat.emission.contents = NSColor.red
        laserGeo.materials = [laserMat]
        laserNode = SCNNode(geometry: laserGeo)
        laserNode.isHidden = true
        rootNode.addChildNode(laserNode)
    }
    
    private func setup3DRobot() {
        petContainer = SCNNode()
        petContainer.position = SCNVector3(x: 0, y: 0, z: 0) // Start in center — always visible!
        petContainer.scale = SCNVector3(0.28, 0.28, 0.28)
        rootNode.addChildNode(petContainer)
        
        let shellMaterial = SCNMaterial()
        shellMaterial.diffuse.contents = NSColor(white: 0.1, alpha: 1.0)
        shellMaterial.specular.contents = NSColor(white: 0.8, alpha: 1.0) // Add shiny reflections
        shellMaterial.shininess = 1.0
        shellMaterial.roughness.contents = 0.2
        
        let darkMaterial = SCNMaterial()
        darkMaterial.diffuse.contents = NSColor(white: 0.05, alpha: 1.0)
        darkMaterial.specular.contents = NSColor(white: 0.5, alpha: 1.0)
        darkMaterial.shininess = 0.5
        darkMaterial.roughness.contents = 0.6
        
        // HEAD (The only body part)
        let headGeo = SCNBox(width: 4.0, height: 3.2, length: 3.2, chamferRadius: 0.6)
        headGeo.materials = [shellMaterial]
        headNode = SCNNode(geometry: headGeo)
        headNode.position = SCNVector3(0, 0, 0)
        petContainer.addChildNode(headNode)
        
        // HEADPHONES (Ears)
        let headphoneGeo = SCNCylinder(radius: 0.85, height: 0.4)
        headphoneGeo.materials = [darkMaterial]
        
        leftHeadphone = SCNNode(geometry: headphoneGeo)
        leftHeadphone.position = SCNVector3(-2.1, 0, 0)
        leftHeadphone.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
        headNode.addChildNode(leftHeadphone)
        
        rightHeadphone = SCNNode(geometry: headphoneGeo)
        rightHeadphone.position = SCNVector3(2.1, 0, 0)
        rightHeadphone.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
        headNode.addChildNode(rightHeadphone)
        
        // BACKPACK / BATTERY
        let backpackGeo = SCNBox(width: 2.2, height: 1.8, length: 0.6, chamferRadius: 0.2)
        backpackGeo.materials = [darkMaterial]
        let backpackNode = SCNNode(geometry: backpackGeo)
        backpackNode.position = SCNVector3(0, -0.2, -1.8) // On the back (z is negative)
        headNode.addChildNode(backpackNode)
        
        // LEGS — built as pivot node (hip) + geometry child below it
        let legGeo = SCNBox(width: 0.2, height: 0.9, length: 0.2, chamferRadius: 0.1) // Minimalistic sleek leg
        legGeo.materials = [darkMaterial]
        
        let jointGeo = SCNSphere(radius: 0.25) // Smaller hip joint
        jointGeo.materials = [shellMaterial]
        
        leftLeg = SCNNode() // HIP pivot
        leftLeg.position = SCNVector3(-1.0, -1.6, 0) // Wider stance
        petContainer.addChildNode(leftLeg)
        
        let leftJoint = SCNNode()
        leftLeg.addChildNode(leftJoint)
        
        let leftLegGeom = SCNNode()
        leftLegGeom.position = SCNVector3(0, -0.1, 0) // Closer to body
        leftLeg.addChildNode(leftLegGeom)
        
        rightLeg = SCNNode() // HIP pivot
        rightLeg.position = SCNVector3(1.0, -1.6, 0) // Wider stance
        petContainer.addChildNode(rightLeg)
        
        let rightJoint = SCNNode()
        rightLeg.addChildNode(rightJoint)
        
        let rightLegGeom = SCNNode()
        rightLegGeom.position = SCNVector3(0, -0.1, 0) // Closer to body
        rightLeg.addChildNode(rightLegGeom)
        
        // SHOES — small and compact, attached to bottom of leg geometry
        let shoeGeo = SCNBox(width: 0.8, height: 0.25, length: 1.2, chamferRadius: 0.125) // Sleeker minimalist shoe
        shoeGeo.materials = [shellMaterial]
        
        let leftShoe = SCNNode(geometry: shoeGeo)
        leftShoe.position = SCNVector3(0, -0.1, 0.35) // Closer to body
        leftLegGeom.addChildNode(leftShoe)
        
        let rightShoe = SCNNode(geometry: shoeGeo)
        rightShoe.position = SCNVector3(0, -0.1, 0.35) // Closer to body
        rightLegGeom.addChildNode(rightShoe)
        
        // ACCESSORIES
        // DJ Headband
        headphoneBandNode = SCNNode()
        
        let topBandGeo = SCNBox(width: 4.6, height: 0.3, length: 0.6, chamferRadius: 0.1)
        topBandGeo.materials = [shellMaterial]
        let topBand = SCNNode(geometry: topBandGeo)
        topBand.position = SCNVector3(0, 1.7, 0)
        
        let leftBandGeo = SCNBox(width: 0.3, height: 1.5, length: 0.6, chamferRadius: 0.1)
        leftBandGeo.materials = [shellMaterial]
        let leftBand = SCNNode(geometry: leftBandGeo)
        leftBand.position = SCNVector3(-2.15, 1.0, 0)
        
        let rightBandGeo = SCNBox(width: 0.3, height: 1.5, length: 0.6, chamferRadius: 0.1)
        rightBandGeo.materials = [shellMaterial]
        let rightBand = SCNNode(geometry: rightBandGeo)
        rightBand.position = SCNVector3(2.15, 1.0, 0)
        
        headphoneBandNode.addChildNode(topBand)
        headphoneBandNode.addChildNode(leftBand)
        headphoneBandNode.addChildNode(rightBand)
        
        headphoneBandNode.isHidden = false
        headNode.addChildNode(headphoneBandNode)
        // SCREEN & GLOWING EYES (2D SKScene wrapped onto 3D)
        setupScreen()
    }
    
    private func setupScreen() {
        let screenWidth: CGFloat = 200
        let screenHeight: CGFloat = 160
        
        screenScene = SKScene(size: CGSize(width: screenWidth, height: screenHeight))
        screenScene.backgroundColor = NSColor.black
        
        // GLOWING EYES
        let eyeColor = NSColor(red: 0.2, green: 0.9, blue: 0.2, alpha: 1.0) // Bright Vector Green
        eyeContainer = SKEffectNode()
        let blur = CIFilter(name: "CIGaussianBlur")
        blur?.setValue(3.0, forKey: kCIInputRadiusKey)
        eyeContainer.filter = blur
        eyeContainer.shouldRasterize = true
        eyeContainer.position = CGPoint(x: screenWidth / 2, y: screenHeight / 2)
        screenScene.addChild(eyeContainer)
        
        leftEye = SKShapeNode(path: getEyePath(for: .normal, isLeft: true))
        leftEye.fillColor = eyeColor
        leftEye.strokeColor = .clear
        leftEye.blendMode = .add
        leftEye.position = CGPoint(x: -40, y: 0)
        
        rightEye = SKShapeNode(path: getEyePath(for: .normal, isLeft: false))
        rightEye.fillColor = eyeColor
        rightEye.strokeColor = .clear
        rightEye.blendMode = .add
        rightEye.position = CGPoint(x: 40, y: 0)
        
        // Tears for Sad (Positive Y is DOWN when mapped to SceneKit material)
        let tearPath = CGPath(ellipseIn: CGRect(x: -8, y: -8, width: 16, height: 16), transform: nil)
        leftTear = SKShapeNode(path: tearPath)
        leftTear.fillColor = NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0)
        leftTear.strokeColor = .clear
        leftTear.alpha = 0
        leftTear.position = CGPoint(x: -40, y: 40)
        
        rightTear = SKShapeNode(path: tearPath)
        rightTear.fillColor = NSColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0)
        rightTear.strokeColor = .clear
        rightTear.alpha = 0
        rightTear.position = CGPoint(x: 40, y: 40)
        
        // Blush for Embarrassed
        let blushPath = CGPath(ellipseIn: CGRect(x: -15, y: -10, width: 30, height: 20), transform: nil)
        leftBlush = SKShapeNode(path: blushPath)
        leftBlush.fillColor = NSColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1.0)
        leftBlush.strokeColor = .clear
        leftBlush.alpha = 0
        leftBlush.position = CGPoint(x: -60, y: 20)
        
        rightBlush = SKShapeNode(path: blushPath)
        rightBlush.fillColor = NSColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1.0)
        rightBlush.strokeColor = .clear
        rightBlush.alpha = 0
        rightBlush.position = CGPoint(x: 60, y: 20)
        
        eyeContainer.addChild(leftEye)
        eyeContainer.addChild(rightEye)
        eyeContainer.addChild(leftTear)
        eyeContainer.addChild(rightTear)
        eyeContainer.addChild(leftBlush)
        eyeContainer.addChild(rightBlush)
        
        // PARTICLE CONTAINER (for hearts, Zzz, sparkles, etc.)
        particleContainer = SKNode()
        particleContainer?.position = CGPoint(x: screenWidth / 2, y: screenHeight / 2)
        if let pc = particleContainer { screenScene.addChild(pc) }
        
        // SPEECH BUBBLE (Dedicated Floating Scene)
        speechBubbleSKScene = SKScene(size: CGSize(width: 800, height: 600))
        speechBubbleSKScene.backgroundColor = .clear
        
        speechContainer = SKNode()
        speechContainer?.position = CGPoint(x: 400, y: 300)
        speechContainer?.alpha = 0
        speechContainer?.xScale = 1
        speechContainer?.yScale = -1
        if let sc = speechContainer { speechBubbleSKScene.addChild(sc) }
        
        speechBubbleBG = SKSpriteNode()
        speechBubbleBG?.zPosition = -1
        if let bg = speechBubbleBG { speechContainer?.addChild(bg) }
        
        speechBubble = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        speechBubble.fontSize = 54
        speechBubble.fontColor = .white
        speechBubble.horizontalAlignmentMode = .center
        speechBubble.verticalAlignmentMode = .center
        speechBubble.numberOfLines = 0
        speechBubble.preferredMaxLayoutWidth = 750
        speechContainer?.addChild(speechBubble)
        
        // Attach to 3D Model (Covering almost the whole front face)
        let screenGeo = SCNPlane(width: 3.6, height: 2.8)
        screenGeo.cornerRadius = 0.2
        let screenMat = SCNMaterial()
        screenMat.diffuse.contents = screenScene // Magic! Live 2D mapped to 3D
        screenMat.emission.contents = screenScene // Make it glow like a real screen
        screenGeo.materials = [screenMat]
        
        let screenNode = SCNNode(geometry: screenGeo)
        screenNode.position = SCNVector3(0, 0, 1.61) // Slightly in front of head box (length 3.2 / 2 = 1.6)
        headNode.addChildNode(screenNode)
        
        // Floating Speech Bubble Billboard Node
        let bubbleGeo = SCNPlane(width: 8.0, height: 6.0)
        let bubbleMat = SCNMaterial()
        bubbleMat.diffuse.contents = speechBubbleSKScene
        bubbleMat.isDoubleSided = true
        bubbleGeo.materials = [bubbleMat]
        
        speechBubbleNode = SCNNode(geometry: bubbleGeo)
        speechBubbleNode.position = SCNVector3(2.5, 3.5, 0) // Closer to the body
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .Y // Allow billboard to track camera only around Y axis, or .all to face fully
        speechBubbleNode.constraints = [billboard]
        petContainer.addChildNode(speechBubbleNode)
    }
    
    // MARK: - Particle Effects
    private func showParticle(_ type: ParticleType) {
        guard particleContainer != nil else { return }  // Not yet initialized
        switch type {
        case .heart:
            showHeartParticles()
        case .zzz:
            showZzzParticles()
        case .sparkle:
            showSparkleParticles()
        case .sweat:
            showSweatParticle()
        case .angryCloud:
            showAngryCloudParticle()
        }
    }
    
    private func showHeartParticles() {
        for i in 0..<3 {
            let heart = SKLabelNode(text: "♥")
            heart.fontSize = 24
            heart.fontColor = NSColor(red: 1.0, green: 0.3, blue: 0.5, alpha: 1.0)
            heart.position = CGPoint(x: CGFloat.random(in: -30...30), y: CGFloat.random(in: -10...10))
            heart.alpha = 1.0
            heart.zPosition = 10
            particleContainer?.addChild(heart)
            
            let floatUp = SKAction.moveBy(x: CGFloat.random(in: -15...15), y: 60, duration: 1.2 + Double(i) * 0.3)
            let fadeOut = SKAction.fadeAlpha(to: 0, duration: 1.0 + Double(i) * 0.3)
            let scale = SKAction.scale(to: 1.5, duration: 1.2)
            heart.run(SKAction.group([floatUp, fadeOut, scale])) {
                heart.removeFromParent()
            }
        }
    }
    
    private func showZzzParticles() {
        let zzz = SKLabelNode(text: "Z")
        zzz.fontSize = 20
        zzz.fontColor = NSColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 0.8)
        zzz.fontName = "HelveticaNeue-Bold"
        zzz.position = CGPoint(x: 30, y: 20)
        zzz.alpha = 0.0
        zzz.zPosition = 10
        particleContainer?.addChild(zzz)
        
        let fadeIn = SKAction.fadeAlpha(to: 0.9, duration: 0.3)
        let floatUp = SKAction.moveBy(x: 15, y: 40, duration: 2.0)
        let grow = SKAction.scale(to: 1.8, duration: 2.0)
        let fadeOut = SKAction.fadeAlpha(to: 0, duration: 0.8)
        zzz.run(SKAction.sequence([fadeIn, SKAction.group([floatUp, grow]), fadeOut])) {
            zzz.removeFromParent()
        }
    }
    
    private func showSparkleParticles() {
        for _ in 0..<5 {
            let sparkle = SKLabelNode(text: "✦")
            sparkle.fontSize = CGFloat.random(in: 14...22)
            sparkle.fontColor = NSColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1.0)
            sparkle.position = CGPoint(x: CGFloat.random(in: -50...50), y: CGFloat.random(in: -30...30))
            sparkle.alpha = 0.0
            sparkle.zPosition = 10
            particleContainer?.addChild(sparkle)
            
            let delay = SKAction.wait(forDuration: Double.random(in: 0...0.4))
            let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 0.2)
            let drift = SKAction.moveBy(x: CGFloat.random(in: -10...10), y: CGFloat.random(in: 10...30), duration: 0.8)
            let fadeOut = SKAction.fadeAlpha(to: 0, duration: 0.3)
            let rotate = SKAction.rotate(byAngle: .pi, duration: 1.0)
            sparkle.run(SKAction.sequence([delay, fadeIn, SKAction.group([drift, rotate]), fadeOut])) {
                sparkle.removeFromParent()
            }
        }
    }
    
    private func showSweatParticle() {
        let sweat = SKLabelNode(text: "💧")
        sweat.fontSize = 16
        sweat.position = CGPoint(x: 35, y: 25)
        sweat.alpha = 0.0
        sweat.zPosition = 10
        particleContainer?.addChild(sweat)
        
        let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 0.15)
        let drop = SKAction.moveBy(x: 3, y: -40, duration: 0.6)
        drop.timingMode = .easeIn
        let fadeOut = SKAction.fadeAlpha(to: 0, duration: 0.2)
        sweat.run(SKAction.sequence([fadeIn, drop, fadeOut])) {
            sweat.removeFromParent()
        }
    }
    
    private func showAngryCloudParticle() {
        let cloud = SKLabelNode(text: "💢")
        cloud.fontSize = 20
        cloud.position = CGPoint(x: CGFloat.random(in: -20...20), y: 30)
        cloud.alpha = 0.0
        cloud.zPosition = 10
        particleContainer?.addChild(cloud)
        
        let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 0.1)
        let puff = SKAction.scale(to: 1.8, duration: 0.4)
        let fadeOut = SKAction.fadeAlpha(to: 0, duration: 0.5)
        cloud.run(SKAction.sequence([fadeIn, puff, fadeOut])) {
            cloud.removeFromParent()
        }
    }
    
    // MARK: - Update Loop
    private func tick(currentTime: TimeInterval) {
        if isDragging { return }
        
        if isFalling {
            velocityY -= 0.04 // Gravity
            petContainer.position.x += velocityX
            petContainer.position.y += velocityY
            
            let aspect = NSScreen.main.map { $0.frame.width / $0.frame.height } ?? 1.6
            let screenEdgeX: CGFloat = 7.0 * aspect
            let screenEdgeYMax: CGFloat = 7.0
            var screenEdgeYMin: CGFloat = -7.0
            if let screen = NSScreen.main {
                let dockApps = DesktopEnvironmentManager.shared.visibleElements.filter { $0.type == .taskbar }
                if let dock = dockApps.first {
                    let ratioMinX = (dock.frame.minX / screen.frame.width) - 0.5
                    let ratioMaxX = (dock.frame.maxX / screen.frame.width) - 0.5
                    let dockWorldMinX = ratioMinX * (14.0 * aspect)
                    let dockWorldMaxX = ratioMaxX * (14.0 * aspect)
                    
                    if petContainer.position.x >= (dockWorldMinX - 1.0) && petContainer.position.x <= (dockWorldMaxX + 1.0) {
                        screenEdgeYMin = -6.0 // Dock height
                    }
                }
            }
            
            if petContainer.position.y <= screenEdgeYMin {
                if petContainer.position.y < screenEdgeYMin - 1.0 {
                    // He was dragged/dropped far below the screen. Let him stay there!
                    velocityY = 0
                    velocityX = 0
                    isFalling = false
                    brain.applyAction(.idle)
                } else {
                    // Normal landing
                    petContainer.position.y = screenEdgeYMin
                    velocityY = 0
                    velocityX = 0
                    isFalling = false
                    brain.applyAction(.idle)
                }
            }
            // Removed left, right, and top ceiling bounces so he can fall off-screen horizontally!
            return
        }
        
        let mouseLocation = NSEvent.mouseLocation
        let cursorMoved = mouseLocation != lastMouseLocation
        let moveDistance = hypot(mouseLocation.x - lastMouseLocation.x, mouseLocation.y - lastMouseLocation.y)
        lastMouseLocation = mouseLocation
        
        // Petting Logic
        let screenW = NSScreen.main?.frame.width ?? 800
        let screenH = NSScreen.main?.frame.height ?? 600
        let ratioX = (mouseLocation.x / screenW) - 0.5
        let ratioY = (mouseLocation.y / screenH) - 0.5
        let worldX = ratioX * 30.0
        let worldY = ratioY * 20.0
        
        let dx = CGFloat(petContainer.position.x) - worldX
        let dy = CGFloat(petContainer.position.y) - worldY
        let distanceToMouse = hypot(dx, dy)
        
        if distanceToMouse < 3.0 && cursorMoved {
            mouseScrubDistance += moveDistance
            lastScrubTime = currentTime
            
            // Fast mouse movement over pet triggers petting
            if mouseScrubDistance > 2000 {
                brain.triggerPetting()
                showParticle(.heart)
                mouseScrubDistance = 0
            }
        }
        
        // Startle logic: cursor moves very fast near pet
        if distanceToMouse < 8.0 && moveDistance > 200 {
            brain.triggerStartle()
        }
        
        if currentTime - lastScrubTime > 0.5 {
            mouseScrubDistance = 0
        }
        
        // Laser Pointer Logic
        if isLaserPointerActive {
            laserNode.position = SCNVector3(worldX, worldY, 0)
            
            if distanceToMouse < 1.5 {
                // Caught it!
                brain.applyAction(.spin)
                brain.currentEmotion = .happy
                isLaserPointerActive = false
            } else {
                // Chase
                walkTargetX = worldX
                walkTargetY = worldY
                let dx = worldX - CGFloat(petContainer.position.x)
                let dy = worldY - CGFloat(petContainer.position.y)
                let dist = sqrt(dx*dx + dy*dy)
                if dist > 0.1 {
                    walkDirectionX = dx / dist
                    walkDirectionY = dy / dist
                }
                
                if brain.currentAction != .chaseLaser {
                    brain.currentAction = .chaseLaser
                    brain.currentEmotion = .excited
                }
                isWalking = true
                
                // Speed up animation slightly for chasing
                if petContainer.action(forKey: "walk") == nil {
                    startWalkAnimation()
                }
            }
        }
        
        // Treat Logic
        if let treat = treatNode {
            if treat.position.y > -3.2 { // Fall
                treat.position.y -= 0.15
            }
            if treat.position.y < -3.2 {
                treat.position.y = -3.2
            }
            
            if brain.currentAction == .seekTreat {
                let dx = CGFloat(treat.position.x) - CGFloat(petContainer.position.x)
                let dy = CGFloat(treat.position.y) - CGFloat(petContainer.position.y)
                if abs(dx) < 1.0 && abs(dy) < 1.0 {
                    // Reached treat
                    treat.removeFromParentNode()
                    treatNode = nil
                    brain.triggerEating() // triggers .bow and adds energy
                }
            }
        }
        
        // Sync agent with physical position before AI tick, unless agent is driving
        if brain.currentAction != .wander {
            brain.agent.position = vector_float2(x: Float(petContainer.position.x), y: Float(petContainer.position.y))
        }
        
        updateAccessories()
        
        let tickResult = brain.tick(currentTime: currentTime, cursorMoved: cursorMoved)
        
        if tickResult.changed {
            applyEmotion(tickResult.emotion)
            applyAction(tickResult.action)
        }
        
        if ![.sleepy, .thinking, .dizzy].contains(brain.currentEmotion) && Int.random(in: 0...blinkChance()) > (blinkChance() - 2) {
            blink()
        }
        
        switch brain.currentAction {
        case .wander, .investigate, .peekWindow, .followCursor, .chaseLaser, .seekTreat:
            let currentX = CGFloat(petContainer.presentation.position.x)
            let currentY = CGFloat(petContainer.presentation.position.y)
            
            let aspect = NSScreen.main.map { $0.frame.width / $0.frame.height } ?? 1.6
            let visibleMaxX = 7.0 * aspect
            
            // Removed wall collision; he can now walk completely off screen!
            
            // Check arrival distance for both X and Y
            let distToTargetX = abs(walkTargetX - currentX)
            let distToTargetY = abs(walkTargetY - currentY)
            
            if (distToTargetX < 0.4 && distToTargetY < 0.4) {
                // Reached destination — stop walk
                if isWalking {
                    isWalking = false
                    petContainer.position = petContainer.presentation.position
                    stopAll()
                    handleWalkArrival()
                }
            } else {
                // Face the correct direction (turn slightly towards movement direction)
                let targetAngleY: CGFloat = walkDirectionX * (.pi / 4)
                petContainer.eulerAngles.y += (targetAngleY - petContainer.eulerAngles.y) * 0.15
            }
            
            // Keep agent position in sync
            brain.agent.position = vector_float2(x: Float(currentX), y: Float(currentY))
            
        case .idle, .sleep, .sit, .spin, .jump, .sulk, .dizzy, .tickled,
             .sneeze, .backflip, .headbang, .trip, .wave,
             .sitOnCorner, .sitOnMenuBar, .climbWindow, .pushWidget, .tapWindow:
            // Calculate dynamic floor based on dock
            var screenEdgeYMin: CGFloat = -3.2 // Default dock height
            
            if let screen = NSScreen.main {
                let dockApps = DesktopEnvironmentManager.shared.visibleElements.filter { $0.type == .taskbar }
                if let dock = dockApps.first {
                    let ratioMinX = (dock.frame.minX / screen.frame.width) - 0.5
                    let ratioMaxX = (dock.frame.maxX / screen.frame.width) - 0.5
                    // Rough mapping for screen width (70 units total)
                    let dockWorldMinX = ratioMinX * 70.0
                    let dockWorldMaxX = ratioMaxX * 70.0
                    
                    if petContainer.position.x < (dockWorldMinX - 1.0) || petContainer.position.x > (dockWorldMaxX + 1.0) {
                        screenEdgeYMin = -(screen.frame.height / 40.0) // Bottom of screen
                    }
                } else {
                    screenEdgeYMin = -(screen.frame.height / 40.0)
                }
            }
            
            // Removed forced snapping to the floor so he can chill off-screen if he wants to
            
            if brain.currentAction == .idle {
                let aspect = NSScreen.main.map { $0.frame.width / $0.frame.height } ?? 1.6
                let visibleMaxX = 7.0 * aspect
                
                // Removed screen teleportation/clamping so he stays exactly where he walked off to
                
                if currentTime - lastLookChangeTime > Double.random(in: 1.0...4.0) {
                    lastLookChangeTime = currentTime
                    randomLookTargetX = CGFloat.random(in: -400...400)
                    randomLookTargetY = CGFloat.random(in: -200...200)
                }
                
                let targetX = CGFloat(petContainer.position.x * 40) + randomLookTargetX
                let targetY = CGFloat(petContainer.position.y * 40) + randomLookTargetY
                lookAt(targetX: targetX, targetY: targetY)
                
                // Random micro-animation triggers while idle
                if currentTime - lastSneezeCheckTime > 5.0 {
                    lastSneezeCheckTime = currentTime
                    let roll = Int.random(in: 0...500)
                    if roll == 0 {
                        brain.triggerSneeze()
                    } else if roll == 1 {
                        brain.triggerWave()
                    }
                }
            }
            // Rotation decay removed so he stays rotated
        default: break
        }
        
        // Hover Awareness (Overrides looking if mouse is close)
        if distanceToMouse < 3.0 && brain.currentAction != .sleep && brain.currentAction != .dizzy && brain.currentAction != .sulk {
             lookAt(targetX: mouseLocation.x, targetY: mouseLocation.y)
        }
    }
    
    private func updateAccessories() {
        
        // DJ Headphones (Music/Spotify or Physical Headphones connected)
        let activeApp = DesktopEnvironmentManager.shared.activeAppTracker.lowercased()
        if activeApp.contains("music") || activeApp.contains("spotify") || AudioMonitor.shared.isHeadphoneConnected {
            headphoneBandNode.isHidden = false
            
            // Make the existing headphones glow neon!
            let neonMat = SCNMaterial()
            neonMat.diffuse.contents = NSColor.green
            neonMat.emission.contents = NSColor.green
            leftHeadphone.geometry?.materials = [neonMat]
            rightHeadphone.geometry?.materials = [neonMat]
        } else {
            headphoneBandNode.isHidden = false
            
            let darkMaterial = SCNMaterial()
            darkMaterial.diffuse.contents = NSColor(white: 0.05, alpha: 1.0)
            darkMaterial.specular.contents = NSColor(white: 0.5, alpha: 1.0)
            darkMaterial.shininess = 0.5
            darkMaterial.roughness.contents = 0.6
            leftHeadphone.geometry?.materials = [darkMaterial]
            rightHeadphone.geometry?.materials = [darkMaterial]
        }
    }
    
    // MARK: - Action Execution
    private func applyAction(_ action: PetAction) {
        targetPosition = nil
        switch action {
        case .idle: startIdleTransition()
        case .wander, .followCursor, .investigate, .chaseLaser, .seekTreat: break // Triggered externally via startWalk(toX:)
        case .sitOnCorner, .sitOnMenuBar, .climbWindow, .pushWidget, .tapWindow: break // Walk first, then animate on arrival
        case .peekWindow: startPeekAnimation()
        case .sitOnTaskbar: startSitOnTaskbarAnimation()
        case .sleep: startSleepAnimation()
        case .sit: startSitAnimation()
        case .jump: startHappyAnimation()
        case .spin: startSpinAnimation()
        case .sulk: startSulkAnimation()
        case .dizzy: startDizzyAnimation()
        case .tickled: startTickledAnimation()
        case .dance: startDanceAnimation()
        case .bow: startBowAnimation()
        case .stretch: startStretchAnimation()
        case .roll: startRollAnimation()
        case .hide: startHideAnimation()
        case .stepBack: startStepBackAnimation()
        // New interactive animations
        case .sneeze: startSneezeAnimation()
        case .backflip: startBackflipAnimation()
        case .headbang: startHeadbangAnimation()
        case .trip: startTripAnimation()
        case .wave: startWaveAnimation()
        }
    }
    
    /// Called when walk finishes — check if there's a pending spatial action to perform
    private func handleWalkArrival() {
        if let pending = pendingSpatialAction {
            pendingSpatialAction = nil
            brain.currentAction = pending
            brain.forceUpdate = true
            
            switch pending {
            case .sitOnCorner: startSitOnCornerAnimation()
            case .sitOnMenuBar: startSitOnMenuBarAnimation()
            case .climbWindow: startClimbWindowAnimation()
            case .pushWidget: startPushWidgetAnimation()
            case .tapWindow: startTapWindowAnimation()
            default: startIdleTransition()
            }
            
            // Proud feeling after successfully completing a command
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.brain.triggerProud()
            }
        } else {
            brain.notifyWalkFinished()
        }
    }
    
    // Called by PetWanderState to begin a proper step-based walk
    func startWalk(toX requestedX: CGFloat, toY requestedY: CGFloat) {
        var maxX: CGFloat = 15.0
        var maxY: CGFloat = 7.0
        var minY: CGFloat = -7.0
        
        if let screen = NSScreen.main {
            let aspect = screen.frame.width / screen.frame.height
            maxX = 7.0 * aspect
            maxY = 7.0
            minY = -7.0
        }
        var finalTargetY = requestedY
        let minX = -maxX
        
        if let screen = NSScreen.main {
            let dockApps = DesktopEnvironmentManager.shared.visibleElements.filter { $0.type == .taskbar }
            if let dock = dockApps.first {
                let aspect = screen.frame.width / screen.frame.height
                let worldWidth = 14.0 * aspect
                let ratioMinX = (dock.frame.minX / screen.frame.width) - 0.5
                let ratioMaxX = (dock.frame.maxX / screen.frame.width) - 0.5
                let dockWorldMinX = ratioMinX * worldWidth
                let dockWorldMaxX = ratioMaxX * worldWidth
                
                if requestedX >= (dockWorldMinX - 1.0) && requestedX <= (dockWorldMaxX + 1.0) {
                    if finalTargetY < -3.2 {
                        finalTargetY = -3.2
                    }
                }
            }
        }
        
        let clampedX = requestedX
        let clampedY = finalTargetY
        
        walkTargetX = clampedX
        walkTargetY = clampedY
        
        let dx = clampedX - CGFloat(petContainer.position.x)
        let dy = clampedY - CGFloat(petContainer.position.y)
        let distance = sqrt(dx*dx + dy*dy)
        
        if distance > 0.1 {
            walkDirectionX = dx / distance
            walkDirectionY = dy / distance
        } else {
            walkDirectionX = 0
            walkDirectionY = 0
        }
        
        isWalking = true
        startWalkAnimation()
    }
    
    private func applyEmotion(_ emotion: PetEmotion) {
        let duration: TimeInterval = 0.3
        
        // Morph the path immediately but hide the abrupt change behind the movement
        leftEye.path = getEyePath(for: emotion, isLeft: true)
        rightEye.path = getEyePath(for: emotion, isLeft: false)
        
        var leftRot: CGFloat = 0
        var rightRot: CGFloat = 0
        var scaleY: CGFloat = 1.0
        var scaleX: CGFloat = 1.0
        
        // Emojis natively handle their shapes, so keep transformations neutral
        switch emotion {
        case .sad:
            scaleY = 0.9
        case .sleepy, .bored:
            scaleY = 0.9
        case .happy, .love, .excited:
            // Slight bounce/scale for positive emotions
            scaleX = 1.1
            scaleY = 1.1
        case .proud:
            // Confident squint + slight upward tilt
            scaleX = 1.15
            scaleY = 0.85
        case .dizzy:
            // Spin the X X around!
            leftRot = .pi
            rightRot = .pi
        default:
            break
        }
        
        leftEye.run(SKAction.group([
            SKAction.rotate(toAngle: leftRot, duration: duration, shortestUnitArc: true),
            SKAction.scaleX(to: scaleX, y: scaleY, duration: duration)
        ]))
        
        rightEye.run(SKAction.group([
            SKAction.rotate(toAngle: rightRot, duration: duration, shortestUnitArc: true),
            SKAction.scaleX(to: scaleX, y: scaleY, duration: duration)
        ]))
        
        // Handle Tears
        if emotion == .sad {
            let cry = SKAction.sequence([
                SKAction.moveBy(x: 0, y: 10, duration: 0.5), // Positive Y is down
                SKAction.fadeAlpha(to: 0, duration: 0.2),
                SKAction.moveBy(x: 0, y: -10, duration: 0),
                SKAction.fadeAlpha(to: 1.0, duration: 0.2)
            ])
            leftTear.run(SKAction.repeatForever(cry))
            rightTear.run(SKAction.repeatForever(cry))
            leftTear.run(SKAction.fadeAlpha(to: 1.0, duration: duration))
            rightTear.run(SKAction.fadeAlpha(to: 1.0, duration: duration))
        } else {
            leftTear.removeAllActions()
            rightTear.removeAllActions()
            leftTear.run(SKAction.fadeAlpha(to: 0, duration: duration))
            rightTear.run(SKAction.fadeAlpha(to: 0, duration: duration))
        }
        
        // Handle Blush
        if emotion == .embarrassed {
            leftBlush.run(SKAction.fadeAlpha(to: 0.8, duration: duration))
            rightBlush.run(SKAction.fadeAlpha(to: 0.8, duration: duration))
        } else {
            leftBlush.run(SKAction.fadeAlpha(to: 0, duration: duration))
            rightBlush.run(SKAction.fadeAlpha(to: 0, duration: duration))
        }
        
        if emotion == .thinking {
            leftEye.run(SKAction.repeatForever(SKAction.sequence([SKAction.fadeAlpha(to: 0.2, duration: 0.5), SKAction.fadeAlpha(to: 1.0, duration: 0.5)])))
            rightEye.run(SKAction.repeatForever(SKAction.sequence([SKAction.fadeAlpha(to: 1.0, duration: 0.5), SKAction.fadeAlpha(to: 0.2, duration: 0.5)])))
        } else {
            leftEye.removeAllActions()
            rightEye.removeAllActions()
            leftEye.alpha = 1.0
            rightEye.alpha = 1.0
        }
        
        // Trigger particles on emotion change
        switch emotion {
        case .love:
            showParticle(.heart)
        case .happy, .excited:
            if Double.random(in: 0...1) < 0.4 { showParticle(.sparkle) }
        case .proud:
            showConfettiParticles()
        case .sleepy:
            showParticle(.zzz)
        case .angry:
            showParticle(.angryCloud)
        default:
            break
        }
    }
    
    private func lookAt(targetX: CGFloat, targetY: CGFloat) {
        let dx = targetX - CGFloat(petContainer.position.x * 40)
        let dy = targetY - CGFloat(petContainer.position.y * 40)
        let maxOffX: CGFloat = 20.0
        let maxOffY: CGFloat = 15.0
        
        let tlx = -40 + max(-maxOffX, min(maxOffX, dx * 0.05))
        let tly = max(-maxOffY, min(maxOffY, dy * 0.05))
        let trx = 40 + max(-maxOffX, min(maxOffX, dx * 0.05))
        let try_ = max(-maxOffY, min(maxOffY, dy * 0.05))
        
        leftEye.position.x += (tlx - leftEye.position.x) * 0.2
        leftEye.position.y += (tly - leftEye.position.y) * 0.2
        rightEye.position.x += (trx - rightEye.position.x) * 0.2
        rightEye.position.y += (try_ - rightEye.position.y) * 0.2
        
        // Eye glow intensity: brighter when cursor is closer
        // Use alpha scaling instead of CIFilter mutation to avoid race condition
        // with SpriteKit's render thread on the rasterized effect node
        let dist = sqrt(dx * dx + dy * dy)
        let glowAlpha = CGFloat(max(0.6, min(1.0, 1.2 - dist * 0.002)))
        eyeContainer.alpha += (glowAlpha - eyeContainer.alpha) * 0.15
    }
    
    private func blink() {
        var targetScaleY: CGFloat = 1.0
        switch brain.currentEmotion {
        case .angry, .sad: targetScaleY = 0.95
        case .sleepy: targetScaleY = 0.9
        case .happy: targetScaleY = 0.95
        case .love: targetScaleY = 1.2
        case .dizzy: targetScaleY = 1.2
        case .bored: targetScaleY = 0.9
        case .embarrassed: targetScaleY = 0.9
        default: targetScaleY = 1.0
        }
        
        let action = SKAction.sequence([SKAction.scaleY(to: 0.1, duration: 0.05), SKAction.scaleY(to: targetScaleY, duration: 0.1)])
        leftEye.run(action)
        rightEye.run(action)
    }
    
    /// Returns an emotion-dependent blink chance per tick.
    /// Higher value = more frequent blinking.
    private func blinkChance() -> Int {
        switch brain.currentEmotion {
        case .excited, .happy, .love:  return 150  // Blink more often
        case .curious:                 return 180
        case .sleepy, .bored:          return 60   // Blink very slowly (long gaps)
        case .angry:                   return 120
        case .normal:                  return 200
        default:                       return 200
        }
    }
    
    // MARK: - Paths for Eyes (EMO Robot Style)
    private func getEyePath(for emotion: PetEmotion, isLeft: Bool) -> CGPath {
        let w: CGFloat = 36
        let h: CGFloat = 80
        let r: CGFloat = 16 // Anki Vector style rounded pills
        
        var topLeft = CGPoint(x: -w/2, y: h/2)
        var topRight = CGPoint(x: w/2, y: h/2)
        var botRight = CGPoint(x: w/2, y: -h/2)
        var botLeft = CGPoint(x: -w/2, y: -h/2)
        
        switch emotion {
        case .angry, .embarrassed:
            if isLeft {
                topRight.y -= 25
                topLeft.y += 5
            } else {
                topLeft.y -= 25
                topRight.y += 5
            }
        case .sad:
            if isLeft {
                topLeft.y -= 25
                topRight.y += 5
                botRight.y += 5
            } else {
                topRight.y -= 25
                topLeft.y += 5
                botLeft.y += 5
            }
        case .bored, .sleepy:
            topLeft.y -= 20
            topRight.y -= 20
            botLeft.y += 5
            botRight.y += 5
        case .happy, .excited:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -25, y: -10))
            path.addQuadCurve(to: CGPoint(x: 25, y: -10), control: CGPoint(x: 0, y: 30))
            path.addQuadCurve(to: CGPoint(x: -25, y: -10), control: CGPoint(x: 0, y: 10))
            path.closeSubpath()
            return path
        case .proud:
            // Confident narrow arc eyes — like a smug cat
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -22, y: 0))
            path.addQuadCurve(to: CGPoint(x: 22, y: 0), control: CGPoint(x: 0, y: 20))
            path.addQuadCurve(to: CGPoint(x: -22, y: 0), control: CGPoint(x: 0, y: 8))
            path.closeSubpath()
            return path
        case .curious:
            if isLeft {
                topLeft.y += 8
                topRight.y += 8
                botLeft.y -= 8
                botRight.y -= 8
            } else {
                topLeft.y -= 10
                topRight.y -= 10
            }
        case .shock:
            return CGPath(ellipseIn: CGRect(x: -30, y: -30, width: 60, height: 60), transform: nil)
        case .thinking:
            return CGPath(ellipseIn: CGRect(x: -12, y: -12, width: 24, height: 24), transform: nil)
        case .love:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: -20))
            path.addCurve(to: CGPoint(x: 25, y: 10), control1: CGPoint(x: 12, y: -10), control2: CGPoint(x: 25, y: 0))
            path.addCurve(to: CGPoint(x: 0, y: 10), control1: CGPoint(x: 25, y: 25), control2: CGPoint(x: 0, y: 25))
            path.addCurve(to: CGPoint(x: -25, y: 10), control1: CGPoint(x: 0, y: 25), control2: CGPoint(x: -25, y: 25))
            path.addCurve(to: CGPoint(x: 0, y: -20), control1: CGPoint(x: -25, y: 0), control2: CGPoint(x: -12, y: -10))
            return path
        case .dizzy:
            if isLeft {
                topLeft.y -= 20
                botRight.y += 20
            } else {
                topRight.y -= 20
                botLeft.y += 20
            }
        case .tictactoe:
            let path = CGMutablePath()
            if isLeft {
                path.move(to: CGPoint(x: -18, y: 18))
                path.addLine(to: CGPoint(x: 18, y: -18))
                path.move(to: CGPoint(x: 18, y: 18))
                path.addLine(to: CGPoint(x: -18, y: -18))
            } else {
                return CGPath(ellipseIn: CGRect(x: -20, y: -20, width: 40, height: 40), transform: nil)
            }
            return path
        case .singing, .dreaming, .dj:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -22, y: 5))
            path.addQuadCurve(to: CGPoint(x: 22, y: 5), control: CGPoint(x: 0, y: 25))
            return path
        case .coffee:
            return CGPath(ellipseIn: CGRect(x: -22, y: -28, width: 44, height: 56), transform: nil)
        case .cold, .rainy, .fishing:
            topLeft.y -= 18
            topRight.y -= 18
            botLeft.y += 10
            botRight.y += 10
        case .working:
            topLeft.y -= 15
            topRight.y -= 15
        case .hot, .batteryLow:
            topLeft.y -= 30
            topRight.y -= 30
        default:
            break
        }
        
        let path = CGMutablePath()
        path.move(to: CGPoint(x: (botLeft.x + botRight.x)/2, y: (botLeft.y + botRight.y)/2))
        path.addArc(tangent1End: botRight, tangent2End: topRight, radius: r)
        path.addArc(tangent1End: topRight, tangent2End: topLeft, radius: r)
        path.addArc(tangent1End: topLeft, tangent2End: botLeft, radius: r)
        path.addArc(tangent1End: botLeft, tangent2End: botRight, radius: r)
        path.closeSubpath()
        return path
    }
    
    func dropTreat() {
        if treatNode != nil { return } // Only one treat at a time
        
        let treatGeo = SCNBox(width: 0.8, height: 0.8, length: 0.8, chamferRadius: 0.1)
        let mat = SCNMaterial()
        mat.diffuse.contents = NSColor.yellow
        mat.emission.contents = NSColor.orange
        treatGeo.materials = [mat]
        
        let treat = SCNNode(geometry: treatGeo)
        treat.position = SCNVector3(CGFloat.random(in: -15...15), 15.0, 0) // Drop from above
        treat.eulerAngles = SCNVector3(CGFloat.random(in: 0...6), CGFloat.random(in: 0...6), 0)
        
        // Add gentle rotation
        treat.runAction(SCNAction.repeatForever(SCNAction.rotateBy(x: 1, y: 1, z: 1, duration: 2.0)))
        
        rootNode.addChildNode(treat)
        treatNode = treat
        
        brain.applyAction(.seekTreat)
        brain.currentEmotion = .happy
        startWalk(toX: CGFloat(treat.position.x), toY: -3.2) // Walk towards it
    }
    
    // MARK: - 3D Animations
    private func stopAll() {
        petContainer.removeAllActions()  // This removes stepMovement too
        headNode.removeAllActions()
        leftLeg.removeAllActions()
        rightLeg.removeAllActions()
        
        petContainer.eulerAngles.x = 0
        petContainer.eulerAngles.z = 0
        
        headNode.position.y = 0
        headNode.eulerAngles = SCNVector3(0, 0, 0)
        leftLeg.eulerAngles = SCNVector3(0, 0, 0)
        rightLeg.eulerAngles = SCNVector3(0, 0, 0)
        leftLeg.position = SCNVector3(-0.55, -1.6, 0)
        rightLeg.position = SCNVector3(0.55, -1.6, 0)
        petContainer.scale = SCNVector3(0.28, 0.28, 0.28)
    }
    
    private func startIdleTransition() {
        stopAll()
        // Final balance step
        let balance = SCNAction.moveBy(x: 0, y: -0.2, z: 0, duration: 0.15)
        balance.timingMode = .easeOut
        let recover = SCNAction.moveBy(x: 0, y: 0.2, z: 0, duration: 0.15)
        recover.timingMode = .easeIn
        
        petContainer.runAction(SCNAction.sequence([
            balance, recover,
            SCNAction.run { [weak self] _ in 
                self?.blink()
                self?.startIdleAnimation() 
            }
        ]))
    }
    
    private func startIdleAnimation() {
        stopAll()
        let breathIn = SCNAction.moveBy(x: 0, y: 0.1, z: 0, duration: 1.5)
        let breathOut = SCNAction.moveBy(x: 0, y: -0.1, z: 0, duration: 1.5)
        breathIn.timingMode = .easeInEaseOut
        breathOut.timingMode = .easeInEaseOut
        headNode.runAction(SCNAction.repeatForever(SCNAction.sequence([breathIn, breathOut])))
        
        let tiltRight = SCNAction.rotateTo(x: 0, y: 0, z: -0.05, duration: 2.0)
        let tiltLeft = SCNAction.rotateTo(x: 0, y: 0, z: 0.05, duration: 2.0)
        tiltRight.timingMode = .easeInEaseOut
        tiltLeft.timingMode = .easeInEaseOut
        headNode.runAction(SCNAction.repeatForever(SCNAction.sequence([tiltRight, tiltLeft])))
    }
    
    private func startWalkAnimation() {
        stopAll()
        
        // Step duration controls leg swing speed — SLOWER = more natural looking walk
        var stepDuration: TimeInterval = 0.50  // One full leg swing (forward or back)
        var bounceHeight: CGFloat = 0.15
        var headWobble: CGFloat = 0.15
        var swingAngle: CGFloat = 0.70  // Leg swing arc in radians
        
        switch brain.currentEmotion {
        case .happy:
            stepDuration = 0.35
            bounceHeight = 0.25
            swingAngle = 0.85
        case .sad:
            stepDuration = 0.75
            bounceHeight = 0.05
            headWobble = 0.04
            swingAngle = 0.45
        case .sleepy:
            stepDuration = 0.85
            bounceHeight = 0.06
            swingAngle = 0.40
        case .excited:
            stepDuration = 0.28
            bounceHeight = 0.35
            swingAngle = 0.95
        case .curious:
            headWobble = 0.30
        default: break
        }
        
        let halfStep = stepDuration / 2.0
        
        // Step distance = how far body advances per leg swing on X and Y
        // Both use 0.35 now since walkDirection is a normalized vector, so speed is constant!
        let stepDistanceX: CGFloat = walkDirectionX * 0.35
        let stepDistanceY: CGFloat = walkDirectionY * 0.35
        
        // --- HEAD BOB — bobs up on each step ---
        let bobUp = SCNAction.moveBy(x: 0, y: bounceHeight, z: 0, duration: halfStep)
        bobUp.timingMode = .easeOut
        let bobDown = SCNAction.moveBy(x: 0, y: -bounceHeight, z: 0, duration: halfStep)
        bobDown.timingMode = .easeIn
        headNode.runAction(SCNAction.repeatForever(SCNAction.sequence([bobUp, bobDown])))
        
        let leanRight = SCNAction.rotateTo(x: 0, y: 0, z: -headWobble, duration: stepDuration)
        let leanLeft = SCNAction.rotateTo(x: 0, y: 0, z: headWobble, duration: stepDuration)
        leanRight.timingMode = .easeInEaseOut
        leanLeft.timingMode = .easeInEaseOut
        headNode.runAction(SCNAction.repeatForever(SCNAction.sequence([leanRight, leanLeft])))
        
        // --- LEGS: swing forward/back AND advance body on each step ---
        let swingAngleVal = swingAngle
        let swingForward = SCNAction.rotateTo(x: swingAngleVal, y: 0, z: 0, duration: stepDuration)
        swingForward.timingMode = .easeInEaseOut
        let swingBackward = SCNAction.rotateTo(x: -swingAngleVal, y: 0, z: 0, duration: stepDuration)
        swingBackward.timingMode = .easeInEaseOut
        
        // Each time a leg swings forward it "pushes" the body forward along both X and Y
        let advanceStep = SCNAction.moveBy(x: stepDistanceX, y: stepDistanceY, z: 0, duration: stepDuration)
        advanceStep.timingMode = .easeInEaseOut
        let walkCycle = SCNAction.repeatForever(SCNAction.sequence([advanceStep, advanceStep]))
        petContainer.runAction(walkCycle, forKey: "stepMovement")
        
        // Left starts forward, right starts backward — alternating gait
        leftLeg.runAction(SCNAction.repeatForever(SCNAction.sequence([swingForward, swingBackward])))
        rightLeg.runAction(SCNAction.repeatForever(SCNAction.sequence([swingBackward, swingForward])))
    }
    
    private func startPeekAnimation() {
        stopAll()
        let peekOut = SCNAction.rotateTo(x: 0, y: 0, z: 0.3, duration: 0.5)
        let peekIn = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.5)
        peekOut.timingMode = .easeInEaseOut
        peekIn.timingMode = .easeInEaseOut
        headNode.runAction(SCNAction.repeatForever(SCNAction.sequence([
            peekOut, SCNAction.wait(duration: 2.0), peekIn, SCNAction.wait(duration: 2.0)
        ])))
    }
    
    private func startSitOnTaskbarAnimation() {
        stopAll()
        leftLeg.runAction(SCNAction.rotateTo(x: -1.0, y: 0, z: 0.2, duration: 0.5))
        leftLeg.runAction(SCNAction.moveBy(x: -0.2, y: 0.8, z: 1.0, duration: 0.5))
        rightLeg.runAction(SCNAction.rotateTo(x: -1.0, y: 0, z: -0.2, duration: 0.5))
        rightLeg.runAction(SCNAction.moveBy(x: 0.2, y: 0.8, z: 1.0, duration: 0.5))
        
        let breatheIn = SCNAction.moveBy(x: 0, y: 0.05, z: 0, duration: 1.5)
        let breatheOut = SCNAction.moveBy(x: 0, y: -0.05, z: 0, duration: 1.5)
        breatheIn.timingMode = .easeInEaseOut
        breatheOut.timingMode = .easeInEaseOut
        headNode.runAction(SCNAction.repeatForever(SCNAction.sequence([breatheIn, breatheOut])))
    }
    
    private func startSleepAnimation() {
        stopAll()
        headNode.runAction(SCNAction.moveBy(x: 0, y: -0.8, z: 0, duration: 1.0))
        headNode.runAction(SCNAction.rotateTo(x: 0.2, y: 0, z: 0.1, duration: 1.0))
        
        // Recurring Zzz particles while sleeping
        let zzzLoop = SCNAction.repeatForever(SCNAction.sequence([
            SCNAction.wait(duration: 3.0),
            SCNAction.run { [weak self] _ in
                self?.showParticle(.zzz)
            }
        ]))
        petContainer.runAction(zzzLoop, forKey: "sleepZzz")
    }
    
    private func startHappyAnimation() {
        stopAll()
        let jumpUp = SCNAction.moveBy(x: 0, y: 2.0, z: 0, duration: 0.25)
        jumpUp.timingMode = .easeOut
        let fallDown = SCNAction.moveBy(x: 0, y: -2.0, z: 0, duration: 0.25)
        fallDown.timingMode = .easeIn
        
        let legsUp = SCNAction.rotateTo(x: -0.5, y: 0, z: 0, duration: 0.25)
        let legsDown = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.25)
        
        leftLeg.runAction(SCNAction.sequence([legsUp, legsDown]))
        rightLeg.runAction(SCNAction.sequence([legsUp, legsDown]))
        petContainer.runAction(SCNAction.sequence([jumpUp, fallDown, jumpUp, fallDown]))
    }
    
    private func startSpinAnimation() {
        stopAll()
        let spin = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 0.5)
        petContainer.runAction(spin)
    }
    
    private func startDanglingAnimation() {
        stopAll()
        let dangle = SCNAction.sequence([
            SCNAction.rotateTo(x: 0, y: 0, z: 0.1, duration: 0.2),
            SCNAction.rotateTo(x: 0, y: 0, z: -0.1, duration: 0.2)
        ])
        petContainer.runAction(SCNAction.repeatForever(dangle))
        
        leftLeg.runAction(SCNAction.rotateTo(x: 0, y: 0, z: 0.2, duration: 0.2))
        rightLeg.runAction(SCNAction.rotateTo(x: 0, y: 0, z: -0.2, duration: 0.2))
        // REMOVED moveBy(y: -0.5) to prevent legs from stretching and permanently drifting
    }
    
    private func startDropAnimation() {
        stopAll()
        
        let bounceUp = SCNAction.moveBy(x: 0, y: 0.5, z: 0, duration: 0.15)
        let bounceDown = SCNAction.moveBy(x: 0, y: -0.5, z: 0, duration: 0.15)
        bounceUp.timingMode = .easeOut; bounceDown.timingMode = .easeIn
        petContainer.runAction(SCNAction.sequence([bounceUp, bounceDown]))
    }
    
    private func startSulkAnimation() {
        stopAll()
        headNode.runAction(SCNAction.rotateTo(x: 0.3, y: 0, z: 0, duration: 1.0))
        petContainer.runAction(SCNAction.rotateTo(x: 0, y: .pi, z: 0, duration: 1.0)) // Turn away
    }
    
    private func startDizzyAnimation() {
        stopAll()
        let spin = SCNAction.rotateBy(x: 0, y: .pi * 4, z: 0, duration: 1.5)
        let wobble = SCNAction.rotateTo(x: 0, y: 0, z: 0.3, duration: 0.2)
        let wobbleBack = SCNAction.rotateTo(x: 0, y: 0, z: -0.3, duration: 0.2)
        headNode.runAction(SCNAction.repeatForever(SCNAction.sequence([wobble, wobbleBack])))
        petContainer.runAction(spin)
    }
    
    private func startTickledAnimation() {
        stopAll()
        let shake = SCNAction.moveBy(x: 0.2, y: 0, z: 0, duration: 0.05)
        let shakeBack = SCNAction.moveBy(x: -0.2, y: 0, z: 0, duration: 0.05)
        let jump = SCNAction.moveBy(x: 0, y: 0.3, z: 0, duration: 0.1)
        let fall = SCNAction.moveBy(x: 0, y: -0.3, z: 0, duration: 0.1)
        headNode.runAction(SCNAction.repeatForever(SCNAction.sequence([shake, shakeBack])))
        petContainer.runAction(SCNAction.repeatForever(SCNAction.sequence([jump, fall])))
    }

    private func startSitAnimation() {
        stopAll()
        
        // Spin around like a dog getting comfortable before sitting!
        let spin = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 0.8)
        spin.timingMode = .easeInEaseOut
        
        petContainer.runAction(spin) { [weak self] in
            guard let self = self else { return }
            
            // Splay legs outward in a V shape (use Z axis for lateral spread before X pitch)
            let sitLeftLeg = SCNAction.rotateTo(x: -CGFloat.pi / 2.2, y: 0, z: -0.4, duration: 0.3)
            let sitRightLeg = SCNAction.rotateTo(x: -CGFloat.pi / 2.2, y: 0, z: 0.4, duration: 0.3)
            self.leftLeg.runAction(sitLeftLeg)
            self.rightLeg.runAction(sitRightLeg)
            
            // Move the body parts down so his bottom rests perfectly on the ground
            let moveDown = SCNAction.moveBy(x: 0, y: -1.4, z: 0, duration: 0.3)
            self.headNode.runAction(moveDown)
            self.leftLeg.runAction(moveDown)
            self.rightLeg.runAction(moveDown)
            
            // Add a gentle breathing animation to the head
            let breatheIn = SCNAction.moveBy(x: 0, y: 0.05, z: 0, duration: 1.5)
            let breatheOut = SCNAction.moveBy(x: 0, y: -0.05, z: 0, duration: 1.5)
            breatheIn.timingMode = .easeInEaseOut
            breatheOut.timingMode = .easeInEaseOut
            self.headNode.runAction(SCNAction.repeatForever(SCNAction.sequence([breatheIn, breatheOut])))
        }
    }

    private func startDanceAnimation() {
        stopAll()
        let spin = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 0.5)
        let jump = SCNAction.moveBy(x: 0, y: 0.5, z: 0, duration: 0.25)
        let fall = SCNAction.moveBy(x: 0, y: -0.5, z: 0, duration: 0.25)
        let jumpCycle = SCNAction.sequence([jump, fall])
        let danceMove = SCNAction.group([spin, jumpCycle])
        petContainer.runAction(SCNAction.repeatForever(SCNAction.sequence([danceMove, SCNAction.wait(duration: 0.2)])))
    }
    
    private func startBowAnimation() {
        stopAll()
        let bowDown = SCNAction.rotateTo(x: 0.5, y: 0, z: 0, duration: 0.5)
        let bowUp = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.5)
        bowDown.timingMode = .easeInEaseOut
        bowUp.timingMode = .easeInEaseOut
        headNode.runAction(SCNAction.sequence([bowDown, SCNAction.wait(duration: 0.5), bowUp]))
    }
    
    private func startStretchAnimation() {
        stopAll()
        // Use container scale to stretch the whole body
        let stretchUp = SCNAction.scale(to: 0.35, duration: 0.5) // Original is 0.25
        let stretchDown = SCNAction.scale(to: 0.25, duration: 0.5)
        stretchUp.timingMode = .easeInEaseOut
        stretchDown.timingMode = .easeInEaseOut
        petContainer.runAction(SCNAction.sequence([stretchUp, stretchDown]))
    }
    
    private func startRollAnimation() {
        stopAll()
        let roll = SCNAction.rotateBy(x: 0, y: 0, z: .pi * 2, duration: 0.8)
        petContainer.runAction(roll)
    }
    
    private func startHideAnimation() {
        stopAll()
        let hideDown = SCNAction.moveBy(x: 0, y: -2.0, z: 0, duration: 0.5)
        hideDown.timingMode = .easeIn
        petContainer.runAction(hideDown)
    }
    
    private func startStepBackAnimation() {
        stopAll()
        // Just make a small step backward (assume facing forward)
        let stepBack = SCNAction.moveBy(x: 0, y: 1.0, z: 0, duration: 0.3) // Using Y for screen space up
        let stepForward = SCNAction.moveBy(x: 0, y: -1.0, z: 0, duration: 0.3)
        petContainer.runAction(SCNAction.sequence([stepBack, SCNAction.wait(duration: 0.5), stepForward]))
    }
    
    // MARK: - New Interactive Animations
    
    /// Sit on a screen corner with legs dangling off the edge
    private func startSitOnCornerAnimation() {
        stopAll()
        
        // Settle down with a little bounce
        let settleDown = SCNAction.moveBy(x: 0, y: -0.3, z: 0, duration: 0.2)
        settleDown.timingMode = .easeIn
        let settleUp = SCNAction.moveBy(x: 0, y: 0.15, z: 0, duration: 0.15)
        settleUp.timingMode = .easeOut
        
        petContainer.runAction(SCNAction.sequence([settleDown, settleUp])) { [weak self] in
            guard let self = self else { return }
            
            // Splay legs outward like sitting on a ledge
            let sitLeftLeg = SCNAction.rotateTo(x: -CGFloat.pi / 2.5, y: 0, z: -0.3, duration: 0.4)
            let sitRightLeg = SCNAction.rotateTo(x: -CGFloat.pi / 2.5, y: 0, z: 0.3, duration: 0.4)
            sitLeftLeg.timingMode = .easeInEaseOut
            sitRightLeg.timingMode = .easeInEaseOut
            self.leftLeg.runAction(sitLeftLeg)
            self.rightLeg.runAction(sitRightLeg)
            
            // Dangle legs gently
            let swingForward = SCNAction.rotateTo(x: -CGFloat.pi / 2.0, y: 0, z: -0.3, duration: 1.5)
            let swingBack = SCNAction.rotateTo(x: -CGFloat.pi / 3.0, y: 0, z: -0.3, duration: 1.5)
            swingForward.timingMode = .easeInEaseOut
            swingBack.timingMode = .easeInEaseOut
            self.leftLeg.runAction(SCNAction.sequence([SCNAction.wait(duration: 0.5), SCNAction.repeatForever(SCNAction.sequence([swingForward, swingBack]))]))
            
            let swingForwardR = SCNAction.rotateTo(x: -CGFloat.pi / 2.0, y: 0, z: 0.3, duration: 1.5)
            let swingBackR = SCNAction.rotateTo(x: -CGFloat.pi / 3.0, y: 0, z: 0.3, duration: 1.5)
            swingForwardR.timingMode = .easeInEaseOut
            swingBackR.timingMode = .easeInEaseOut
            self.rightLeg.runAction(SCNAction.sequence([SCNAction.wait(duration: 0.8), SCNAction.repeatForever(SCNAction.sequence([swingForwardR, swingBackR]))]))
            
            // Head body lowered and gentle breathing
            self.headNode.runAction(SCNAction.moveBy(x: 0, y: -1.0, z: 0, duration: 0.4))
            
            let breatheIn = SCNAction.moveBy(x: 0, y: 0.06, z: 0, duration: 2.0)
            let breatheOut = SCNAction.moveBy(x: 0, y: -0.06, z: 0, duration: 2.0)
            breatheIn.timingMode = .easeInEaseOut
            breatheOut.timingMode = .easeInEaseOut
            self.headNode.runAction(SCNAction.repeatForever(SCNAction.sequence([breatheIn, breatheOut])))
        }
    }
    
    /// Perch on the menu bar at the top of the screen
    private func startSitOnMenuBarAnimation() {
        stopAll()
        
        // Legs dangle straight down
        let sitLeftLeg = SCNAction.rotateTo(x: 0, y: 0, z: -0.15, duration: 0.3)
        let sitRightLeg = SCNAction.rotateTo(x: 0, y: 0, z: 0.15, duration: 0.3)
        leftLeg.runAction(sitLeftLeg)
        rightLeg.runAction(sitRightLeg)
        
        // Gentle swing
        let swingLeft = SCNAction.rotateTo(x: 0, y: 0, z: 0.08, duration: 2.0)
        let swingRight = SCNAction.rotateTo(x: 0, y: 0, z: -0.08, duration: 2.0)
        swingLeft.timingMode = .easeInEaseOut
        swingRight.timingMode = .easeInEaseOut
        petContainer.runAction(SCNAction.repeatForever(SCNAction.sequence([swingLeft, swingRight])))
        
        // Subtle breathing
        let breatheIn = SCNAction.moveBy(x: 0, y: 0.04, z: 0, duration: 1.8)
        let breatheOut = SCNAction.moveBy(x: 0, y: -0.04, z: 0, duration: 1.8)
        breatheIn.timingMode = .easeInEaseOut
        breatheOut.timingMode = .easeInEaseOut
        headNode.runAction(SCNAction.repeatForever(SCNAction.sequence([breatheIn, breatheOut])))
    }
    
    /// Scramble up and sit on top of a window
    private func startClimbWindowAnimation() {
        stopAll()
        
        // Scramble wiggle (simulating climbing effort)
        let wiggleLeft = SCNAction.rotateTo(x: 0, y: 0, z: 0.15, duration: 0.1)
        let wiggleRight = SCNAction.rotateTo(x: 0, y: 0, z: -0.15, duration: 0.1)
        let scramble = SCNAction.repeat(SCNAction.sequence([wiggleLeft, wiggleRight]), count: 4)
        
        // Legs kick while climbing
        let kickForward = SCNAction.rotateTo(x: 0.6, y: 0, z: 0, duration: 0.1)
        let kickBack = SCNAction.rotateTo(x: -0.3, y: 0, z: 0, duration: 0.1)
        let legKick = SCNAction.repeat(SCNAction.sequence([kickForward, kickBack]), count: 4)
        leftLeg.runAction(legKick)
        rightLeg.runAction(SCNAction.sequence([SCNAction.wait(duration: 0.05), legKick]))
        
        // Pull up slightly
        let pullUp = SCNAction.moveBy(x: 0, y: 1.0, z: 0, duration: 0.8)
        pullUp.timingMode = .easeOut
        
        petContainer.runAction(SCNAction.group([scramble, pullUp])) { [weak self] in
            guard let self = self else { return }
            // Now settled on top — do sitting pose
            self.startSitOnCornerAnimation()
            self.showParticle(.sparkle)
        }
    }
    
    /// Lean against a window edge and push
    private func startPushWidgetAnimation() {
        stopAll()
        
        // Turn sideways towards the window
        let turnToWindow = SCNAction.rotateTo(x: 0, y: .pi / 2, z: 0, duration: 0.3)
        turnToWindow.timingMode = .easeInEaseOut
        
        // Lean into it
        let leanIn = SCNAction.rotateTo(x: 0.2, y: .pi / 2, z: 0.3, duration: 0.5)
        leanIn.timingMode = .easeInEaseOut
        let leanBack = SCNAction.rotateTo(x: 0, y: .pi / 2, z: 0.15, duration: 0.5)
        leanBack.timingMode = .easeInEaseOut
        
        // Strain animation — pushing with effort
        let strain = SCNAction.repeatForever(SCNAction.sequence([leanIn, leanBack]))
        
        // Legs push off
        let pushLeg = SCNAction.rotateTo(x: 0.4, y: 0, z: 0, duration: 0.5)
        let resetLeg = SCNAction.rotateTo(x: 0.2, y: 0, z: 0, duration: 0.5)
        pushLeg.timingMode = .easeInEaseOut
        resetLeg.timingMode = .easeInEaseOut
        leftLeg.runAction(SCNAction.repeatForever(SCNAction.sequence([pushLeg, resetLeg])))
        rightLeg.runAction(SCNAction.sequence([SCNAction.wait(duration: 0.25), SCNAction.repeatForever(SCNAction.sequence([pushLeg, resetLeg]))]))
        
        petContainer.runAction(SCNAction.sequence([turnToWindow, strain]))
        
        // Show effort particles
        showParticle(.sweat)
    }
    
    /// Head bonk against a window
    private func startTapWindowAnimation() {
        stopAll()
        
        // Turn towards window
        let turn = SCNAction.rotateTo(x: 0, y: .pi / 4, z: 0, duration: 0.2)
        turn.timingMode = .easeInEaseOut
        petContainer.runAction(turn)
        
        // Head bonk forward
        let bonkForward = SCNAction.rotateTo(x: 0.5, y: 0, z: 0, duration: 0.15)
        let bonkBack = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.25)
        bonkForward.timingMode = .easeIn
        bonkBack.timingMode = .easeOut
        
        let bonkSequence = SCNAction.sequence([
            bonkForward, bonkBack,
            SCNAction.wait(duration: 0.3),
            bonkForward, bonkBack,
            SCNAction.wait(duration: 0.3),
            bonkForward, bonkBack
        ])
        
        headNode.runAction(bonkSequence) { [weak self] in
            // After tapping, look up curiously
            self?.blink()
        }
    }
    
    /// Explosive sneeze — body compresses then launches
    private func startSneezeAnimation() {
        stopAll()
        
        // Wind up — body compresses
        let squash = SCNAction.scale(to: 0.22, duration: 0.5)  // Smaller than normal 0.28
        squash.timingMode = .easeIn
        let tiltDown = SCNAction.rotateTo(x: 0.3, y: 0, z: 0, duration: 0.5)
        tiltDown.timingMode = .easeIn
        
        // ACHOO! — explosive upward
        let explode = SCNAction.scale(to: 0.33, duration: 0.1)
        let jumpUp = SCNAction.moveBy(x: 0, y: 1.5, z: 0, duration: 0.15)
        jumpUp.timingMode = .easeOut
        let tiltBack = SCNAction.rotateTo(x: -0.4, y: 0, z: 0, duration: 0.1)
        
        // Recovery
        let normalScale = SCNAction.scale(to: 0.28, duration: 0.3)
        let fallDown = SCNAction.moveBy(x: 0, y: -1.5, z: 0, duration: 0.2)
        fallDown.timingMode = .easeIn
        let resetTilt = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.3)
        
        // Head shake after sneeze
        let headShake = SCNAction.sequence([
            SCNAction.rotateTo(x: 0, y: 0, z: 0.2, duration: 0.1),
            SCNAction.rotateTo(x: 0, y: 0, z: -0.2, duration: 0.1),
            SCNAction.rotateTo(x: 0, y: 0, z: 0.1, duration: 0.1),
            SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.1)
        ])
        
        petContainer.runAction(SCNAction.sequence([
            SCNAction.group([squash, tiltDown]),
            SCNAction.wait(duration: 0.2),
            SCNAction.group([explode, jumpUp, tiltBack]),
            SCNAction.run { [weak self] _ in
                self?.showParticle(.sparkle)
                self?.blink()
            },
            SCNAction.group([normalScale, fallDown, resetTilt])
        ]))
        
        headNode.runAction(SCNAction.sequence([
            SCNAction.wait(duration: 0.9),
            headShake
        ]))
    }
    
    /// Full forward rotation while jumping — celebratory backflip
    private func startBackflipAnimation() {
        stopAll()
        
        // Crouch first
        let crouch = SCNAction.scale(to: 0.24, duration: 0.2)
        crouch.timingMode = .easeIn
        
        // Launch upward
        let jumpUp = SCNAction.moveBy(x: 0, y: 3.0, z: 0, duration: 0.35)
        jumpUp.timingMode = .easeOut
        
        // Full flip rotation on X axis (forward flip)
        let flip = SCNAction.rotateBy(x: .pi * 2, y: 0, z: 0, duration: 0.5)
        
        // Legs tuck in during flip
        let tuckIn = SCNAction.rotateTo(x: -1.0, y: 0, z: 0, duration: 0.15)
        let tuckOut = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.15)
        leftLeg.runAction(SCNAction.sequence([SCNAction.wait(duration: 0.2), tuckIn, SCNAction.wait(duration: 0.3), tuckOut]))
        rightLeg.runAction(SCNAction.sequence([SCNAction.wait(duration: 0.2), tuckIn, SCNAction.wait(duration: 0.3), tuckOut]))
        
        // Fall down
        let fallDown = SCNAction.moveBy(x: 0, y: -3.0, z: 0, duration: 0.25)
        fallDown.timingMode = .easeIn
        
        // Landing bounce
        let landSquash = SCNAction.scale(to: 0.25, duration: 0.1)
        let landRecover = SCNAction.scale(to: 0.28, duration: 0.15)
        
        petContainer.runAction(SCNAction.sequence([
            crouch,
            SCNAction.group([jumpUp, flip]),
            fallDown,
            SCNAction.run { [weak self] _ in
                self?.showParticle(.sparkle)
            },
            landSquash, landRecover
        ]))
    }
    
    /// Rhythmic head rocking — like rocking to music
    private func startHeadbangAnimation() {
        stopAll()
        
        // Rhythmic head nodding
        let headDown = SCNAction.rotateTo(x: 0.5, y: 0, z: 0, duration: 0.2)
        let headUp = SCNAction.rotateTo(x: -0.2, y: 0, z: 0, duration: 0.2)
        headDown.timingMode = .easeIn
        headUp.timingMode = .easeOut
        
        // Body bounce synced with head
        let bodyDown = SCNAction.moveBy(x: 0, y: -0.15, z: 0, duration: 0.2)
        let bodyUp = SCNAction.moveBy(x: 0, y: 0.15, z: 0, duration: 0.2)
        bodyDown.timingMode = .easeIn
        bodyUp.timingMode = .easeOut
        
        headNode.runAction(SCNAction.repeatForever(SCNAction.sequence([headDown, headUp])))
        petContainer.runAction(SCNAction.repeatForever(SCNAction.sequence([bodyDown, bodyUp])))
        
        // Legs tap with the beat — alternating
        let tapLeft = SCNAction.rotateTo(x: 0.3, y: 0, z: 0, duration: 0.2)
        let untapLeft = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.2)
        let tapRight = SCNAction.rotateTo(x: 0.3, y: 0, z: 0, duration: 0.2)
        let untapRight = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.2)
        leftLeg.runAction(SCNAction.repeatForever(SCNAction.sequence([tapLeft, untapLeft])))
        rightLeg.runAction(SCNAction.repeatForever(SCNAction.sequence([SCNAction.wait(duration: 0.2), tapRight, untapRight])))
    }
    
    /// Comic stumble — legs tangle, face-plant, gets up embarrassed
    private func startTripAnimation() {
        stopAll()
        
        // Phase 1: Walking normally then tripping
        let stumbleForward = SCNAction.moveBy(x: 0.5, y: 0, z: 0, duration: 0.2)
        
        // Phase 2: Legs cross
        let crossLeft = SCNAction.rotateTo(x: 0, y: 0, z: 0.5, duration: 0.15)
        let crossRight = SCNAction.rotateTo(x: 0, y: 0, z: -0.5, duration: 0.15)
        leftLeg.runAction(crossLeft)
        rightLeg.runAction(crossRight)
        
        // Phase 3: Face-plant — tilt forward dramatically
        let facePlant = SCNAction.rotateTo(x: 1.2, y: 0, z: 0.1, duration: 0.3)
        facePlant.timingMode = .easeIn
        let fallDown = SCNAction.moveBy(x: 0, y: -0.8, z: 0, duration: 0.3)
        fallDown.timingMode = .easeIn
        
        // Phase 4: Lie there for a beat (comedy timing!)
        let pause = SCNAction.wait(duration: 1.0)
        
        // Phase 5: Recover slowly, embarrassed
        let getUp = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.6)
        getUp.timingMode = .easeInEaseOut
        let standUp = SCNAction.moveBy(x: 0, y: 0.8, z: 0, duration: 0.4)
        standUp.timingMode = .easeOut
        let resetLegs = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.3)
        
        petContainer.runAction(SCNAction.sequence([
            stumbleForward,
            SCNAction.group([facePlant, fallDown]),
            pause,
            SCNAction.run { [weak self] _ in
                // Show blush/embarrassment during recovery
                self?.applyEmotion(.embarrassed)
            },
            SCNAction.group([getUp, standUp])
        ]))
        
        leftLeg.runAction(SCNAction.sequence([SCNAction.wait(duration: 1.7), resetLegs]))
        rightLeg.runAction(SCNAction.sequence([SCNAction.wait(duration: 1.7), resetLegs]))
    }
    
    /// Friendly wave — headphone ears wiggle side to side
    private func startWaveAnimation() {
        stopAll()
        
        // Headphone ear wiggle (wave substitute since Byte has no arms)
        let wiggleOut = SCNAction.moveBy(x: -0.3, y: 0.2, z: 0, duration: 0.2)
        let wiggleIn = SCNAction.moveBy(x: 0.3, y: -0.2, z: 0, duration: 0.2)
        wiggleOut.timingMode = .easeInEaseOut
        wiggleIn.timingMode = .easeInEaseOut
        
        let wiggleOutR = SCNAction.moveBy(x: 0.3, y: 0.2, z: 0, duration: 0.2)
        let wiggleInR = SCNAction.moveBy(x: -0.3, y: -0.2, z: 0, duration: 0.2)
        wiggleOutR.timingMode = .easeInEaseOut
        wiggleInR.timingMode = .easeInEaseOut
        
        let waveCount = 4
        leftHeadphone.runAction(SCNAction.repeat(SCNAction.sequence([wiggleOut, wiggleIn]), count: waveCount))
        rightHeadphone.runAction(SCNAction.repeat(SCNAction.sequence([wiggleOutR, wiggleInR]), count: waveCount))
        
        // Body leans side to side during wave
        let leanRight = SCNAction.rotateTo(x: 0, y: 0, z: -0.15, duration: 0.4)
        let leanLeft = SCNAction.rotateTo(x: 0, y: 0, z: 0.15, duration: 0.4)
        leanRight.timingMode = .easeInEaseOut
        leanLeft.timingMode = .easeInEaseOut
        petContainer.runAction(SCNAction.repeat(SCNAction.sequence([leanRight, leanLeft]), count: waveCount / 2))
        
        // Small happy bounce
        let bounceUp = SCNAction.moveBy(x: 0, y: 0.2, z: 0, duration: 0.2)
        let bounceDown = SCNAction.moveBy(x: 0, y: -0.2, z: 0, duration: 0.2)
        bounceUp.timingMode = .easeOut
        bounceDown.timingMode = .easeIn
        headNode.runAction(SCNAction.repeat(SCNAction.sequence([bounceUp, bounceDown]), count: waveCount))
    }
    
    // MARK: - Confetti Particles
    private func showConfettiParticles() {
        guard particleContainer != nil else { return }
        
        let confettiEmojis = ["🎉", "✨", "⭐", "🌟", "💫", "🎊"]
        for i in 0..<6 {
            let confetti = SKLabelNode(text: confettiEmojis[i % confettiEmojis.count])
            confetti.fontSize = CGFloat.random(in: 14...22)
            confetti.position = CGPoint(x: CGFloat.random(in: -40...40), y: CGFloat.random(in: -20...20))
            confetti.alpha = 0.0
            confetti.zPosition = 10
            particleContainer?.addChild(confetti)
            
            let delay = SKAction.wait(forDuration: Double(i) * 0.1)
            let fadeIn = SKAction.fadeAlpha(to: 1.0, duration: 0.15)
            let drift = SKAction.moveBy(
                x: CGFloat.random(in: -25...25),
                y: CGFloat.random(in: 20...50),
                duration: 1.2
            )
            let spin = SKAction.rotate(byAngle: CGFloat.random(in: -.pi...(.pi)), duration: 1.2)
            let fadeOut = SKAction.fadeAlpha(to: 0, duration: 0.4)
            confetti.run(SKAction.sequence([delay, fadeIn, SKAction.group([drift, spin]), fadeOut])) {
                confetti.removeFromParent()
            }
        }
    }
    
    
    // MARK: - Speech
    private func updateSpeechBubble(text: String) {
        speechBubble.text = text
        let textFrame = speechBubble.frame
        let padding: CGFloat = 12.0
        let bubbleWidth = max(textFrame.width + padding * 2, 60)
        let bubbleHeight = max(textFrame.height + padding * 2, 30)
        
        speechBubbleBG?.removeFromParent()
        
        let cornerRadius: CGFloat = 8.0
        let imageSize = NSSize(width: bubbleWidth + 40, height: bubbleHeight + 40)
        let image = NSImage(size: imageSize)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            let bubblePath = CGMutablePath()
            let rect = CGRect(x: 20, y: 30, width: bubbleWidth, height: bubbleHeight)
            bubblePath.addRoundedRect(in: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius)
            
            // Pointer tail pointing down-left toward the robot
            bubblePath.move(to: CGPoint(x: 40, y: 30))
            bubblePath.addLine(to: CGPoint(x: 30, y: 5))
            bubblePath.addLine(to: CGPoint(x: 60, y: 30))
            
            ctx.addPath(bubblePath)
            ctx.setFillColor(NSColor(white: 0.1, alpha: 0.85).cgColor)
            ctx.fillPath()
            
            ctx.addPath(bubblePath)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(3.0)
            ctx.strokePath()
        }
        image.unlockFocus()
        
        let newBG = SKSpriteNode(texture: SKTexture(image: image))
        newBG.zPosition = -1
        // Offset slightly to match the drawn rect position relative to center
        newBG.position = CGPoint(x: 0, y: -5)
        
        speechContainer?.addChild(newBG)
        speechBubbleBG = newBG
        
        speechContainer?.alpha = 1.0
    }
    
    // Speech lifecycle now handled by VoiceInputManager.onSpeakingFinished callback
    // No longer need synthesizer delegate methods
    
    func say(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.speechContainer?.removeAllActions()
            self.pendingSpeechTexts.removeAll()

            // Split into sentences
            var sentences: [String] = []
            text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { (substring, _, _, _) in
                if let s = substring { sentences.append(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
            }
            if sentences.isEmpty { sentences = [text] }

            let voiceManager = VoiceInputManager.shared
            let emotionStr = self.brain.currentEmotion.rawValue

            if self.isMuted {
                // Text-only display
                var actions: [SKAction] = []
                for (index, sentence) in sentences.enumerated() {
                    let displaySentence = index == 0 ? "[\(self.brain.currentEmotion)] \(sentence)" : sentence
                    actions.append(SKAction.run { [weak self] in
                        self?.updateSpeechBubble(text: displaySentence)
                    })
                    let waitDuration = max(2.5, Double(displaySentence.count) * 0.08)
                    actions.append(SKAction.wait(forDuration: waitDuration))
                }
                actions.append(SKAction.fadeAlpha(to: 0, duration: 0.8))
                self.speechContainer?.run(SKAction.sequence(actions))
            } else {
                // Speak the WHOLE utterance in a single TTS call.
                // (AudioManager drops overlapping speak() calls, so per-sentence looping
                //  silently lost every sentence after the first — felt like queueing/cutting.)
                let allowedCharacters = CharacterSet.alphanumerics.union(.whitespacesAndNewlines).union(CharacterSet(charactersIn: ".,!?'\"-"))
                let spokenText = String(text.unicodeScalars.filter { allowedCharacters.contains($0) }).trimmingCharacters(in: .whitespacesAndNewlines)

                let displayText = "[\(self.brain.currentEmotion)] \(sentences.first ?? text)"
                self.pendingSpeechTexts = [displayText]
                self.updateSpeechBubble(text: displayText)

                if !spokenText.isEmpty {
                    voiceManager.speak(spokenText, emotion: emotionStr)
                }

                // Fade out after speaking
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                    let fadeOut = SKAction.sequence([
                        SKAction.wait(forDuration: 1.0),
                        SKAction.fadeAlpha(to: 0, duration: 0.8)
                    ])
                    self.speechContainer?.run(fadeOut)
                }
            }
        }
    }
    
    func saySentence(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.speechContainer?.removeAllActions()
            let voiceManager = VoiceInputManager.shared
            let emotionStr = self.brain.currentEmotion.rawValue
            
            let displayText = "[\(self.brain.currentEmotion)] \(text)"
            self.updateSpeechBubble(text: displayText)
            self.speechContainer?.alpha = 1.0
            
            if !self.isMuted {
                let allowedCharacters = CharacterSet.alphanumerics.union(.whitespacesAndNewlines).union(CharacterSet(charactersIn: ".,!?'\"-"))
                let spokenText = String(text.unicodeScalars.filter { allowedCharacters.contains($0) }).trimmingCharacters(in: .whitespacesAndNewlines)
                
                if !spokenText.isEmpty {
                    voiceManager.speak(spokenText, emotion: emotionStr)
                }
            } else {
                let waitDuration = max(2.5, Double(text.count) * 0.08)
                self.speechContainer?.run(SKAction.wait(forDuration: waitDuration))
            }
        }
    }
    
    func finishSpeech() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // If the TTS is still playing, AudioManager manages its own queue and lifecycle,
            // but we can just schedule a fadeOut that won't interrupt TTS playback.
            // When AudioManager finishes its whole queue, it sets isSpeaking = false.
            let fadeOut = SKAction.sequence([
                SKAction.wait(forDuration: 3.5),
                SKAction.fadeAlpha(to: 0, duration: 0.8)
            ])
            self.speechContainer?.run(fadeOut)
        }
    }
    
    func sayToPet(_ message: String) {
        FeedbackLogger.shared.logExplicit(comment: message, context: "User explicitly spoke to Byte while he was doing: \(brain.currentAction.rawValue)")
        
        // Show "thinking..." emotion nodes and query AI with user message!
        applyEmotion(.thinking)
        brain.queryAI(userMessage: message)
    }
    
    func showListeningState(_ listening: Bool) {
        if listening {
            // STOP speaking when user wants to talk!
            AudioManager.shared.stopSpeaking()
            self.pendingSpeechTexts.removeAll()

            applyEmotion(.curious)
            speechContainer?.removeAllActions()
            updateSpeechBubble(text: "🎤 Listening...")
        } else {
            updateSpeechBubble(text: "🤔 Thinking...")
        }
    }

    func showDictationState(_ dictating: Bool) {
        if dictating {
            self.pendingSpeechTexts.removeAll()

            applyEmotion(.excited)
            speechContainer?.removeAllActions()
            updateSpeechBubble(text: "📝 Dictating...")
        } else {
            let fadeOut = SKAction.sequence([
                SKAction.wait(forDuration: 1.0),
                SKAction.fadeAlpha(to: 0, duration: 0.5)
            ])
            speechContainer?.run(fadeOut)
        }
    }
    

    // MARK: - Event Handling for Drag
    private var isActuallyDragged = false
    
    func handleMouseDown(at location: CGPoint, viewSize: CGSize) {
        let now = Date().timeIntervalSince1970
        let timeSinceLastClick = now - lastClickTime
        lastClickTime = now

        if timeSinceLastClick < 0.3 {
            // Rapid Clicks / Double Click
            brain.annoyance += 10
            if brain.annoyance > 50 {
                brain.triggerDizzy()
                applyEmotion(.dizzy)
                say("So dizzy!!")
                isDragging = false
                return
            } else {
                brain.triggerTickle()
                applyEmotion(.happy)
                say("Hahaha! Stop!")
                isDragging = false
                return
            }
        }
        
        if brain.currentAction == .sleep {
            brain.triggerStartle()
            applyEmotion(.shock)
            say("AH!")
        }
        
        isDragging = true
        isActuallyDragged = false
        brain.setDragged(true)
        applyEmotion(.angry)
        
        // CRITICAL: Stop all running animations immediately!
        // The walk stepMovement action fights with drag position updates,
        // causing legs to visually separate from the body.
        stopAll()
        isWalking = false
        // Reset legs to neutral hanging position
        leftLeg.eulerAngles = SCNVector3Zero
        rightLeg.eulerAngles = SCNVector3Zero
        
        let ratioX = (location.x / viewSize.width) - 0.5
        let ratioY = (location.y / viewSize.height) - 0.5
        let aspect = viewSize.width / viewSize.height
        let worldX = ratioX * (14.0 * aspect)
        let worldY = ratioY * 14.0
        dragOffset = CGPoint(x: CGFloat(petContainer.position.x) - worldX, y: CGFloat(petContainer.position.y) - worldY)
    }
    
    func handleMouseDragged(at location: CGPoint, viewSize: CGSize) {
        if isDragging {
            if !isActuallyDragged {
                isActuallyDragged = true
                startDanglingAnimation()
                brain.annoyance += 20
                if brain.annoyance > 80 {
                    say("Put me down!")
                } else if brain.annoyance > 40 {
                    say("Hey!")
                }
            }
            
            let ratioX = (location.x / viewSize.width) - 0.5
            let ratioY = (location.y / viewSize.height) - 0.5
            let aspect = viewSize.width / viewSize.height
            let worldX = ratioX * (14.0 * aspect)
            let worldY = ratioY * 14.0
            
            // Removed drag clamping so the user can drag him off screen
            let newX = worldX + dragOffset.x
            let newY = worldY + dragOffset.y
            
            // Calculate velocity for throw physics
            velocityX = (newX - CGFloat(petContainer.position.x)) * 0.3
            velocityY = (newY - CGFloat(petContainer.position.y)) * 0.3
            
            // Cap velocity
            velocityX = max(-2.0, min(2.0, velocityX))
            velocityY = max(-2.0, min(2.0, velocityY))
            
            petContainer.position = SCNVector3(newX, newY, 0)
        }
    }
    
    func handleScroll(deltaX: CGFloat, deltaY: CGFloat) {
        // Rotate the pet container based on scroll delta (support both trackpad and standard mouse wheel)
        let amount = abs(deltaX) > abs(deltaY) ? deltaX : deltaY
        petContainer.eulerAngles.y += amount * 0.05
    }
    
    func handleMouseUp() {
        let wasClick = !isActuallyDragged
        
        if isDragging {
            isDragging = false
            brain.setDragged(false)
            
            if wasClick {
                // If it was just a click and not a drag, make him walk away!
                self.brain.annoyance += 10
                self.applyEmotion(.shock)
                self.say("Hey, don't poke me!")
                FeedbackLogger.shared.logNegative(context: "User poked Byte to interrupt him while he was doing: \(brain.currentAction.rawValue)")
                self.brain.applyAction(.wander)
            } else {
                let speed = sqrt(velocityX * velocityX + velocityY * velocityY)
                stopAll()
                
                if speed > 0.1 {
                    // Was thrown — let him fall!
                    FeedbackLogger.shared.logNegative(context: "User grabbed and threw Byte away while he was doing: \(brain.currentAction.rawValue)")
                    isFalling = true
                    brain.applyAction(.dizzy) // Make him dizzy while falling
                } else {
                    // Was carefully placed — stay put (no falling)
                    isFalling = false
                    velocityX = 0
                    velocityY = 0
                    brain.applyAction(.idle)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if !self.isFalling {
                    self.applyAction(self.brain.currentAction)
                }
            }
        }
    }
}
