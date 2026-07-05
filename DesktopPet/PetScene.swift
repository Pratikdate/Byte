import SceneKit
import SpriteKit
import AppKit
import AVFoundation

class PetScene: SCNScene {
    private var petContainer: SCNNode!
    
    // Robot 3D Parts
    private var headNode: SCNNode!
    private var leftLeg: SCNNode!
    private var rightLeg: SCNNode!
    private var leftHeadphone: SCNNode!
    private var rightHeadphone: SCNNode!
    
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
    private let synthesizer = AVSpeechSynthesizer()
    
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
        EnvironmentMonitor.shared.startMonitoring()
        DesktopEnvironmentManager.shared.startMonitoring()
        setup3DEnvironment()
        setup3DRobot()
        startIdleAnimation()
        
        brain.onThoughtGenerated = { [weak self] thought in
            self?.say(thought)
        }
        
        brain.onStartWalk = { [weak self] targetX, targetY in
            self?.startWalk(toX: targetX, toY: targetY)
        }
        
        // (petContainer Y is already set to groundY in setup3DRobot)
        
        // Setup Update Loop
        let updateNode = SCNNode()
        self.rootNode.addChildNode(updateNode)
        updateNode.runAction(SCNAction.repeatForever(SCNAction.customAction(duration: 0.1, action: { [weak self] node, _ in
            self?.tick(currentTime: Date().timeIntervalSince1970)
        })))
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
        let legGeo = SCNBox(width: 0.55, height: 0.9, length: 0.55, chamferRadius: 0.10)
        legGeo.materials = [darkMaterial]
        
        let jointGeo = SCNSphere(radius: 0.35)
        jointGeo.materials = [shellMaterial]
        
        leftLeg = SCNNode() // HIP pivot
        leftLeg.position = SCNVector3(-0.6, -1.6, 0)
        petContainer.addChildNode(leftLeg)
        
        let leftJoint = SCNNode(geometry: jointGeo)
        leftLeg.addChildNode(leftJoint)
        
        let leftLegGeom = SCNNode(geometry: legGeo)
        leftLegGeom.position = SCNVector3(0, -0.45, 0) // Hang down from hip pivot
        leftLeg.addChildNode(leftLegGeom)
        
        rightLeg = SCNNode() // HIP pivot
        rightLeg.position = SCNVector3(0.6, -1.6, 0)
        petContainer.addChildNode(rightLeg)
        
        let rightJoint = SCNNode(geometry: jointGeo)
        rightLeg.addChildNode(rightJoint)
        
        let rightLegGeom = SCNNode(geometry: legGeo)
        rightLegGeom.position = SCNVector3(0, -0.45, 0)
        rightLeg.addChildNode(rightLegGeom)
        
        // SHOES — small and compact, attached to bottom of leg geometry
        let shoeGeo = SCNBox(width: 1.0, height: 0.3, length: 1.5, chamferRadius: 0.1)
        shoeGeo.materials = [shellMaterial]
        
        let leftShoe = SCNNode(geometry: shoeGeo)
        leftShoe.position = SCNVector3(0, -0.5, 0.35) // Bottom of leg, slight forward poke
        leftLegGeom.addChildNode(leftShoe)
        
        let rightShoe = SCNNode(geometry: shoeGeo)
        rightShoe.position = SCNVector3(0, -0.5, 0.35)
        rightLegGeom.addChildNode(rightShoe)
        
        // SCREEN & GLOWING EYES (2D SKScene wrapped onto 3D)
        setupScreen()
    }
    
    private func setupScreen() {
        let screenWidth: CGFloat = 200
        let screenHeight: CGFloat = 160
        
        screenScene = SKScene(size: CGSize(width: screenWidth, height: screenHeight))
        screenScene.backgroundColor = NSColor.black
        
        // GLOWING EYES
        let eyeColor = NSColor(red: 0.0, green: 0.8, blue: 1.0, alpha: 1.0)
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
        
        // SPEECH BUBBLE (Fix for flipped SceneKit texture mapping)
        speechBubble = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        speechBubble.fontSize = 20
        speechBubble.fontColor = .white
        speechBubble.xScale = -1
        speechBubble.yScale = -1
        speechBubble.position = CGPoint(x: 0, y: -90)
        speechBubble.horizontalAlignmentMode = .center
        speechBubble.verticalAlignmentMode = .center
        speechBubble.numberOfLines = 0 // Allow multiple lines
        speechBubble.preferredMaxLayoutWidth = 320 // Wrap text that's too wide
        speechBubble.alpha = 0
        screenScene.addChild(speechBubble)
        
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
    }
    
    // MARK: - Update Loop
    private func tick(currentTime: TimeInterval) {
        if isDragging { return }
        
        if isFalling {
            velocityY -= 0.04 // Gravity
            petContainer.position.x += velocityX
            petContainer.position.y += velocityY
            
            let screenEdgeX: CGFloat = 35.0
            var screenEdgeYMin: CGFloat = -3.2
            if let screen = NSScreen.main {
                let dockApps = DesktopEnvironmentManager.shared.visibleElements.filter { $0.type == .taskbar }
                if let dock = dockApps.first {
                    let ratioMinX = (dock.frame.minX / screen.frame.width) - 0.5
                    let ratioMaxX = (dock.frame.maxX / screen.frame.width) - 0.5
                    let dockWorldMinX = ratioMinX * 70.0
                    let dockWorldMaxX = ratioMaxX * 70.0
                    
                    if petContainer.position.x < (dockWorldMinX - 1.0) || petContainer.position.x > (dockWorldMaxX + 1.0) {
                        screenEdgeYMin = -(screen.frame.height / 40.0) // Bottom of screen
                    }
                } else {
                    screenEdgeYMin = -(screen.frame.height / 40.0)
                }
            }
            
            if petContainer.position.y <= screenEdgeYMin {
                petContainer.position.y = screenEdgeYMin
                velocityY = -velocityY * 0.6 // Bounce damping
                velocityX *= 0.8 // Friction
                
                if abs(velocityY) < 0.1 && abs(velocityX) < 0.1 {
                    isFalling = false
                    velocityY = 0
                    velocityX = 0
                    brain.applyAction(.idle)
                }
            }
            
            if petContainer.position.x <= -screenEdgeX {
                petContainer.position.x = -screenEdgeX
                velocityX = -velocityX * 0.8
            } else if petContainer.position.x >= screenEdgeX {
                petContainer.position.x = screenEdgeX
                velocityX = -velocityX * 0.8
            }
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
        
        let tickResult = brain.tick(currentTime: currentTime, cursorMoved: cursorMoved)
        
        if tickResult.changed {
            applyEmotion(tickResult.emotion)
            applyAction(tickResult.action)
        }
        
        if ![.sleepy, .thinking, .dizzy].contains(brain.currentEmotion) && Int.random(in: 0...200) > 198 {
            blink()
        }
        
        switch brain.currentAction {
        case .wander, .investigate, .peekWindow, .followCursor, .chaseLaser, .seekTreat:
            let currentX = CGFloat(petContainer.presentation.position.x)
            let currentY = CGFloat(petContainer.presentation.position.y)
            
            var visibleMaxX: CGFloat = 17.0
            if let screen = NSScreen.main {
                let aspect = screen.frame.width / screen.frame.height
                visibleMaxX = 7.0 * aspect // Orthographic scale is 7
            }
            
            // Failsafe: If somehow way out of bounds, forcefully walk back to center
            if abs(currentX) > (visibleMaxX + 1.0) && walkTargetX != 0 {
                walkTargetX = 0
                walkTargetY = currentY
                walkDirectionX = currentX > 0 ? -1 : 1
            }
            
            // Check arrival distance for both X and Y
            let distToTargetX = abs(walkTargetX - currentX)
            let distToTargetY = abs(walkTargetY - currentY)
            
            if (distToTargetX < 0.4 && distToTargetY < 0.4) {
                // Reached destination — stop walk
                if isWalking {
                    isWalking = false
                    petContainer.position = petContainer.presentation.position
                    stopAll()
                    brain.notifyWalkFinished()
                }
            } else {
                // Face the correct direction (turn slightly towards movement direction)
                let targetAngleY: CGFloat = walkDirectionX * (.pi / 4)
                petContainer.eulerAngles.y += (targetAngleY - petContainer.eulerAngles.y) * 0.15
            }
            
            // Keep agent position in sync
            brain.agent.position = vector_float2(x: Float(currentX), y: Float(currentY))
            
        case .idle, .sleep, .sit, .spin, .jump, .sulk, .dizzy, .tickled:
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
            
            // Smoothly move towards the floor if above or below it
            if petContainer.position.y < screenEdgeYMin {
                // Smoothly snap UP to the dock instead of teleporting
                petContainer.position.y += 0.8
                if petContainer.position.y > screenEdgeYMin {
                    petContainer.position.y = screenEdgeYMin
                }
            } else if petContainer.position.y > screenEdgeYMin && !isDragging && brain.currentAction == .idle {
                // If somehow floating above the floor while idle, slowly fall down
                petContainer.position.y -= 0.2
                if petContainer.position.y < screenEdgeYMin {
                    petContainer.position.y = screenEdgeYMin
                }
            }
            
            if brain.currentAction == .idle {
                var visibleMaxX: CGFloat = 17.0
                if let screen = NSScreen.main {
                    let aspect = screen.frame.width / screen.frame.height
                    visibleMaxX = 7.0 * aspect
                }
                
                // Out of bounds safety net for idle pet
                if abs(petContainer.position.x) > (visibleMaxX + 1.0) {
                    brain.applyAction(.wander)
                    startWalk(toX: 0, toY: CGFloat(petContainer.position.y))
                } else {
                    if currentTime - lastLookChangeTime > Double.random(in: 1.0...4.0) {
                        lastLookChangeTime = currentTime
                        randomLookTargetX = CGFloat.random(in: -400...400)
                        randomLookTargetY = CGFloat.random(in: -200...200)
                    }
                    
                    let targetX = CGFloat(petContainer.position.x * 40) + randomLookTargetX
                    let targetY = CGFloat(petContainer.position.y * 40) + randomLookTargetY
                    lookAt(targetX: targetX, targetY: targetY)
                }
            }
            petContainer.eulerAngles.y *= 0.9
            petContainer.eulerAngles.x *= 0.9
        default: break
        }
        
        // Hover Awareness (Overrides looking if mouse is close)
        if distanceToMouse < 3.0 && brain.currentAction != .sleep && brain.currentAction != .dizzy && brain.currentAction != .sulk {
             lookAt(targetX: mouseLocation.x, targetY: mouseLocation.y)
        }
    }
    
    // MARK: - Action Execution
    private func applyAction(_ action: PetAction) {
        targetPosition = nil
        switch action {
        case .idle: startIdleTransition()
        case .wander, .followCursor, .investigate, .chaseLaser, .seekTreat: break // Triggered externally via startWalk(toX:)
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
        }
    }
    
    // Called by PetWanderState to begin a proper step-based walk
    func startWalk(toX requestedX: CGFloat, toY requestedY: CGFloat) {
        var maxX: CGFloat = 15.0
        var maxY: CGFloat = 7.0
        var minY: CGFloat = -7.0
        
        if let screen = NSScreen.main {
            let aspect = screen.frame.width / screen.frame.height
            maxX = 7.0 * aspect - 0.5 // 0.5 margin keeps him barely on screen
            maxY = 7.0 - 0.5
            minY = -7.0 + 0.5
        }
        var finalTargetY = requestedY
        var minX = -maxX
        
        if let screen = NSScreen.main {
            let dockApps = DesktopEnvironmentManager.shared.visibleElements.filter { $0.type == .taskbar }
            if let dock = dockApps.first {
                let ratioMinX = (dock.frame.minX / screen.frame.width) - 0.5
                let ratioMaxX = (dock.frame.maxX / screen.frame.width) - 0.5
                let dockWorldMinX = ratioMinX * 70.0
                let dockWorldMaxX = ratioMaxX * 70.0
                
                if requestedX >= (dockWorldMinX - 1.0) && requestedX <= (dockWorldMaxX + 1.0) {
                    if finalTargetY < -3.2 {
                        finalTargetY = -3.2
                    }
                }
            }
        }
        
        // Expanded to allow reaching the far corners of wide monitors
        let clampedX = max(minX, min(maxX, requestedX))
        let clampedY = max(minY, min(maxY, finalTargetY))
        
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
    
    // MARK: - Paths for Eyes (EMO Robot Style)
    private func getEyePath(for emotion: PetEmotion, isLeft: Bool) -> CGPath {
        let w: CGFloat = 36
        let h: CGFloat = 80
        let r: CGFloat = 14 // Rounded rectangle (EMO style), not a perfect pill, to prevent tangent overlap
        
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
    
    
    // MARK: - Speech
    func say(_ text: String) {
        guard !isMuted else { return }
        
        speechBubble.removeAllActions()
        
        // Show the emotion label in brackets before the text so the user can see what emotion was picked
        let formattedText = "[\(brain.currentEmotion)] \(text)"
        speechBubble.text = formattedText
        speechBubble.alpha = 1.0
        
        synthesizer.stopSpeaking(at: .immediate)
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.volume = 0.8
        
        // Dynamic pitch based on emotion for more genuine feel
        switch brain.currentEmotion {
        case .excited, .happy:
            utterance.pitchMultiplier = 1.15
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        case .sad, .sleepy, .bored:
            utterance.pitchMultiplier = 0.90
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.80
        case .angry, .dizzy:
            utterance.pitchMultiplier = 0.85
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        default:
            utterance.pitchMultiplier = 1.0 // Natural pitch
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85 // Slower, highly conversational
        }
        
        // Dispatch to avoid main thread stutters
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.synthesizer.speak(utterance)
        }
        
        let waitDuration = max(6.5, Double(text.count) * 0.08)
        let fadeOut = SKAction.sequence([
            SKAction.wait(forDuration: waitDuration),
            SKAction.fadeAlpha(to: 0, duration: 0.8)
        ])
        speechBubble.run(fadeOut)
    }
    
    func sayToPet(_ message: String) {
        // Show "thinking..." emotion nodes and query AI with user message!
        applyEmotion(.thinking)
        brain.queryAI(userMessage: message)
    }
    
    func showListeningState(_ listening: Bool) {
        if listening {
            applyEmotion(.curious)
            speechBubble.removeAllActions()
            speechBubble.text = "🎤 Listening..."
            speechBubble.alpha = 1.0
        } else {
            speechBubble.text = "🤔 Thinking..."
        }
    }
    
    func showDictationState(_ dictating: Bool) {
        if dictating {
            applyEmotion(.excited)
            speechBubble.removeAllActions()
            speechBubble.text = "📝 Dictating..."
            speechBubble.alpha = 1.0
        } else {
            let fadeOut = SKAction.sequence([
                SKAction.wait(forDuration: 1.0),
                SKAction.fadeAlpha(to: 0, duration: 0.5)
            ])
            speechBubble.run(fadeOut)
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
        let worldX = ratioX * 30.0
        let worldY = ratioY * 20.0
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
            let worldX = ratioX * 30.0
            let worldY = ratioY * 20.0
            
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
                self.brain.applyAction(.wander)
            } else {
                // Was dragged and dropped - engage falling physics!
                stopAll()
                isFalling = true
                brain.applyAction(.dizzy) // He gets dizzy when thrown!
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.applyAction(self.brain.currentAction)
            }
        }
    }
}
