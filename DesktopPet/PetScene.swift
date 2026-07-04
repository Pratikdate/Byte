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
    
    // Speech
    private var speechBubble: SKLabelNode!
    private let synthesizer = AVSpeechSynthesizer()
    
    // State Engine
    private var brain = PetBrain()
    private var lastMouseLocation: NSPoint = .zero
    private var targetPosition: CGPoint?
    
    // Interaction
    var isDragging = false
    private var dragOffset: CGPoint = .zero
    private var lastClickTime: TimeInterval = 0
    
    override init() {
        super.init()
        EnvironmentMonitor.shared.startMonitoring()
        DesktopEnvironmentManager.shared.startMonitoring()
        setup3DEnvironment()
        setup3DRobot()
        startIdleAnimation()
        
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
    }
    
    private func setup3DRobot() {
        petContainer = SCNNode()
        petContainer.position = SCNVector3(x: 0, y: 0, z: 0)
        petContainer.scale = SCNVector3(0.25, 0.25, 0.25) // Make it small and compact!
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
        
        // HEADPHONES
        let headphoneGeo = SCNCylinder(radius: 0.8, height: 0.4)
        headphoneGeo.materials = [darkMaterial]
        
        leftHeadphone = SCNNode(geometry: headphoneGeo)
        leftHeadphone.position = SCNVector3(-2.1, 0, 0)
        leftHeadphone.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
        headNode.addChildNode(leftHeadphone)
        
        rightHeadphone = SCNNode(geometry: headphoneGeo)
        rightHeadphone.position = SCNVector3(2.1, 0, 0)
        rightHeadphone.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
        headNode.addChildNode(rightHeadphone)
        
        // TINY LEGS
        let legGeo = SCNBox(width: 0.6, height: 0.8, length: 0.6, chamferRadius: 0.1)
        legGeo.materials = [darkMaterial]
        
        leftLeg = SCNNode(geometry: legGeo)
        leftLeg.position = SCNVector3(-0.8, -1.9, 0)
        petContainer.addChildNode(leftLeg)
        
        rightLeg = SCNNode(geometry: legGeo)
        rightLeg.position = SCNVector3(0.8, -1.9, 0)
        petContainer.addChildNode(rightLeg)
        
        // TINY SHOES
        let shoeGeo = SCNBox(width: 1.4, height: 0.3, length: 1.8, chamferRadius: 0.1)
        shoeGeo.materials = [shellMaterial]
        let leftShoe = SCNNode(geometry: shoeGeo)
        leftShoe.position = SCNVector3(0, -0.4, 0.4)
        leftLeg.addChildNode(leftShoe)
        
        let rightShoe = SCNNode(geometry: shoeGeo)
        rightShoe.position = SCNVector3(0, -0.4, 0.4)
        rightLeg.addChildNode(rightShoe)
        
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
        
        leftEye = SKShapeNode(path: getEyePath(for: .normal))
        leftEye.fillColor = eyeColor
        leftEye.strokeColor = .clear
        leftEye.blendMode = .add
        leftEye.position = CGPoint(x: -40, y: 0)
        
        rightEye = SKShapeNode(path: getEyePath(for: .normal))
        rightEye.fillColor = eyeColor
        rightEye.strokeColor = .clear
        rightEye.blendMode = .add
        rightEye.position = CGPoint(x: 40, y: 0)
        
        eyeContainer.addChild(leftEye)
        eyeContainer.addChild(rightEye)
        
        // SPEECH BUBBLE
        speechBubble = SKLabelNode(fontNamed: "HelveticaNeue-Bold")
        speechBubble.fontSize = 24
        speechBubble.fontColor = .white
        speechBubble.position = CGPoint(x: screenWidth / 2, y: screenHeight - 30)
        speechBubble.horizontalAlignmentMode = .center
        speechBubble.verticalAlignmentMode = .center
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
        
        let mouseLocation = NSEvent.mouseLocation
        let cursorMoved = mouseLocation != lastMouseLocation
        lastMouseLocation = mouseLocation
        
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
        case .wander:
            // Agent is driving! Update physical position from agent
            petContainer.position.x = CGFloat(brain.agent.position.x)
            petContainer.position.y = CGFloat(brain.agent.position.y)
            
            // Clamp position so it doesn't leave the screen (agent might try to wander off)
            petContainer.position.x = max(-15, min(15, petContainer.position.x))
            petContainer.position.y = max(-10, min(10, petContainer.position.y))
            brain.agent.position = vector_float2(x: Float(petContainer.position.x), y: Float(petContainer.position.y))
            
            // Turn towards walking direction (velocity)
            let vx = CGFloat(brain.agent.velocity.x)
            let vy = CGFloat(brain.agent.velocity.y)
            
            if abs(vx) > 0.1 || abs(vy) > 0.1 {
                let targetAngleY: CGFloat = vx >= 0 ? (.pi / 2) : (-.pi / 2)
                
                // Slow down if turn is sharp to simulate a pivot before walking
                let angleDiff = abs(targetAngleY - petContainer.eulerAngles.y)
                if angleDiff > 0.5 {
                    brain.agent.maxSpeed = 1.0 // Slow pivot
                } else {
                    // Adjust speed based on emotion (Reduced speeds)
                    var speed: Float = 4.0
                    if brain.currentEmotion == .happy { speed = 5.5 }
                    if brain.currentEmotion == .sad || brain.currentEmotion == .sleepy { speed = 2.0 }
                    brain.agent.maxSpeed = speed
                }
                
                petContainer.eulerAngles.y += (targetAngleY - petContainer.eulerAngles.y) * 0.08
                
                // Tilt based on vertical movement
                let targetAngleX: CGFloat = vy > 0 ? -0.1 : (vy < 0 ? 0.1 : 0)
                petContainer.eulerAngles.x += (targetAngleX - petContainer.eulerAngles.x) * 0.1
                
                lookAt(targetX: CGFloat(brain.agent.position.x * 40) + vx * 20, targetY: CGFloat(brain.agent.position.y * 40) + vy * 20)
            }
            
        case .idle, .sleep, .sit, .spin, .jump, .sulk, .dizzy, .tickled:
            if brain.currentAction == .idle {
                let dx = CGFloat(petContainer.position.x) + CGFloat(sin(currentTime) * 5)
                let dy = CGFloat(petContainer.position.y) + CGFloat(cos(currentTime) * 2)
                lookAt(targetX: dx * 40, targetY: dy * 40)
            }
            petContainer.eulerAngles.y *= 0.9
            petContainer.eulerAngles.x *= 0.9
        default: break
        }
        
        // Hover Awareness (Overrides looking if mouse is close)
        let screenW = NSScreen.main?.frame.width ?? 800
        let screenH = NSScreen.main?.frame.height ?? 600
        let ratioX = (mouseLocation.x / screenW) - 0.5
        let ratioY = (mouseLocation.y / screenH) - 0.5
        let worldX = ratioX * 30.0
        let worldY = ratioY * 20.0
        
        let dx = CGFloat(petContainer.position.x) - worldX
        let dy = CGFloat(petContainer.position.y) - worldY
        let distanceToMouse = hypot(dx, dy)
        
        if distanceToMouse < 3.0 && brain.currentAction != .sleep && brain.currentAction != .dizzy && brain.currentAction != .sulk {
             lookAt(targetX: mouseLocation.x, targetY: mouseLocation.y)
        }
    }
    
    // MARK: - Action Execution
    private func applyAction(_ action: PetAction) {
        targetPosition = nil
        switch action {
        case .idle: startIdleTransition()
        case .wander, .followCursor, .investigate: startWalkAnimation()
        case .peekWindow: startPeekAnimation()
        case .sitOnTaskbar: startSitOnTaskbarAnimation()
        case .sleep: startSleepAnimation()
        case .sit: startIdleAnimation()
        case .jump: startHappyAnimation()
        case .spin: startSpinAnimation()
        case .sulk: startSulkAnimation()
        case .dizzy: startDizzyAnimation()
        case .tickled: startTickledAnimation()
        }
    }
    
    private func applyEmotion(_ emotion: PetEmotion) {
        let duration: TimeInterval = 0.3
        
        // If it's a special shape (love, shock), snap to it. Otherwise, use normal shape and scale it smoothly.
        if emotion == .love || emotion == .shock || emotion == .thinking {
            leftEye.path = getEyePath(for: emotion)
            rightEye.path = getEyePath(for: emotion)
        } else {
            leftEye.path = getEyePath(for: .normal)
            rightEye.path = getEyePath(for: .normal)
        }
        
        var leftRot: CGFloat = 0
        var rightRot: CGFloat = 0
        var scaleY: CGFloat = 1.0
        var scaleX: CGFloat = 1.0
        
        switch emotion {
        case .angry:
            leftRot = -0.4; rightRot = 0.4
            scaleY = 0.8
        case .sad:
            leftRot = 0.3; rightRot = -0.3
            scaleY = 0.8
            scaleX = 0.9
        case .sleepy:
            scaleY = 0.2
        case .happy:
            scaleY = 0.6
            scaleX = 1.2
        case .love:
            scaleY = 1.2
            scaleX = 1.2
        case .dizzy:
            leftRot = 0.8; rightRot = -0.8
            scaleX = 0.5
            scaleY = 1.5
        case .bored:
            scaleY = 0.4
            scaleX = 0.9
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
        let action = SKAction.sequence([SKAction.scaleY(to: 0.1, duration: 0.05), SKAction.scaleY(to: 1.0, duration: 0.1)])
        leftEye.run(action)
        rightEye.run(action)
    }
    
    // MARK: - Paths for Eyes (Scaled up for 2D texture)
    private func getEyePath(for emotion: PetEmotion) -> CGPath {
        let rect = CGRect(x: -20, y: -30, width: 40, height: 60)
        switch emotion {
        case .normal, .happy, .sad, .angry, .sleepy, .bored, .dizzy, .excited, .curious:
            // Use the same base shape for most emotions so they morph smoothly via SKAction.scale
            return CGPath(roundedRect: rect, cornerWidth: 20, cornerHeight: 20, transform: nil)
        case .shock: return CGPath(ellipseIn: CGRect(x: -25, y: -25, width: 50, height: 50), transform: nil)
        case .thinking: return CGPath(ellipseIn: CGRect(x: -12, y: -12, width: 24, height: 24), transform: nil)
        case .love:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: -20))
            path.addCurve(to: CGPoint(x: 25, y: 10), control1: CGPoint(x: 12, y: -10), control2: CGPoint(x: 25, y: 0))
            path.addCurve(to: CGPoint(x: 0, y: 10), control1: CGPoint(x: 25, y: 25), control2: CGPoint(x: 0, y: 25))
            path.addCurve(to: CGPoint(x: -25, y: 10), control1: CGPoint(x: 0, y: 25), control2: CGPoint(x: -25, y: 25))
            path.addCurve(to: CGPoint(x: 0, y: -20), control1: CGPoint(x: -25, y: 0), control2: CGPoint(x: -12, y: -10))
            return path
        }
    }
    
    // MARK: - 3D Animations
    private func stopAll() {
        petContainer.removeAllActions()
        headNode.removeAllActions()
        leftLeg.removeAllActions()
        rightLeg.removeAllActions()
        
        petContainer.eulerAngles.x = 0
        petContainer.eulerAngles.z = 0
        
        headNode.position.y = 0
        headNode.eulerAngles = SCNVector3(0, 0, 0)
        leftLeg.position = SCNVector3(-0.8, -1.9, 0)
        leftLeg.eulerAngles = SCNVector3(0, 0, 0)
        rightLeg.position = SCNVector3(0.8, -1.9, 0)
        rightLeg.eulerAngles = SCNVector3(0, 0, 0)
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
        
        var duration: TimeInterval = 0.4
        var bounceHeight: CGFloat = 0.25
        var headWobble: CGFloat = 0.2
        
        switch brain.currentEmotion {
        case .happy:
            duration *= 0.7
            bounceHeight = 0.4
        case .sad:
            duration *= 1.5
            bounceHeight = 0.05
            headWobble = 0.05
        case .sleepy:
            duration *= 1.5
            bounceHeight = 0.1
        case .excited:
            duration *= 0.5
            bounceHeight = 0.5
        case .curious:
            headWobble = 0.4
        default: break
        }
        
        let halfStep = duration / 2.0
        
        // --- HEAD ANIMATION ---
        let bobUp = SCNAction.moveBy(x: 0, y: bounceHeight, z: 0, duration: halfStep)
        bobUp.timingMode = .easeOut
        let bobDown = SCNAction.moveBy(x: 0, y: -bounceHeight, z: 0, duration: halfStep)
        bobDown.timingMode = .easeIn
        headNode.runAction(SCNAction.repeatForever(SCNAction.sequence([bobUp, bobDown])))
        
        let leanRight = SCNAction.rotateTo(x: 0, y: 0, z: -headWobble, duration: duration)
        let leanLeft = SCNAction.rotateTo(x: 0, y: 0, z: headWobble, duration: duration)
        leanRight.timingMode = .easeInEaseOut
        leanLeft.timingMode = .easeInEaseOut
        headNode.runAction(SCNAction.repeatForever(SCNAction.sequence([leanRight, leanLeft])))
        
        // --- 8-POSE LEG CYCLE (Lift, Plant, Slide) ---
        let lSwingUp = SCNAction.group([
            SCNAction.moveBy(x: 0, y: 0.6, z: 1.4, duration: halfStep),
            SCNAction.rotateTo(x: 0.4, y: 0, z: 0, duration: halfStep)
        ])
        lSwingUp.timingMode = .easeOut
        
        let lPlant = SCNAction.group([
            SCNAction.moveBy(x: 0, y: -0.6, z: 0.4, duration: halfStep),
            SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: halfStep)
        ])
        lPlant.timingMode = .easeIn
        
        let lSlide = SCNAction.moveBy(x: 0, y: 0, z: -1.8, duration: duration)
        lSlide.timingMode = .linear
        
        let rSwingUp = SCNAction.group([
            SCNAction.moveBy(x: 0, y: 0.6, z: 1.4, duration: halfStep),
            SCNAction.rotateTo(x: 0.4, y: 0, z: 0, duration: halfStep)
        ])
        rSwingUp.timingMode = .easeOut
        
        let rPlant = SCNAction.group([
            SCNAction.moveBy(x: 0, y: -0.6, z: 0.4, duration: halfStep),
            SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: halfStep)
        ])
        rPlant.timingMode = .easeIn
        
        let rSlide = SCNAction.moveBy(x: 0, y: 0, z: -1.8, duration: duration)
        rSlide.timingMode = .linear
        
        leftLeg.runAction(SCNAction.repeatForever(SCNAction.sequence([lSwingUp, lPlant, lSlide])))
        rightLeg.runAction(SCNAction.repeatForever(SCNAction.sequence([rSlide, rSwingUp, rPlant])))
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
        let wiggleRight = SCNAction.rotateTo(x: 0, y: 0.3, z: -0.15, duration: 0.1)
        let wiggleLeft = SCNAction.rotateTo(x: 0, y: -0.3, z: 0.15, duration: 0.1)
        petContainer.runAction(SCNAction.sequence([wiggleRight, wiggleLeft, wiggleRight, wiggleLeft, SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.1)]))
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
        leftLeg.runAction(SCNAction.moveBy(x: 0, y: -0.5, z: 0, duration: 0.2))
        rightLeg.runAction(SCNAction.moveBy(x: 0, y: -0.5, z: 0, duration: 0.2))
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
    
    // MARK: - Speech
    func say(_ text: String) {
        speechBubble.removeAllActions()
        speechBubble.text = text
        speechBubble.alpha = 1.0
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.volume = 0.5
        
        // Dispatch to avoid main thread stutters
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.synthesizer.speak(utterance)
        }
        
        let fadeOut = SKAction.sequence([
            SKAction.wait(forDuration: 3.0),
            SKAction.fadeAlpha(to: 0, duration: 0.5)
        ])
        speechBubble.run(fadeOut)
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
            
            petContainer.position = SCNVector3(worldX + dragOffset.x, worldY + dragOffset.y, 0)
        }
    }
    
    func handleMouseUp() {
        let wasClick = !isActuallyDragged
        
        if isDragging {
            isDragging = false
            brain.setDragged(false)
            
            if wasClick {
                // If it was just a click and not a drag, bounce in place!
                self.startDropAnimation()
                self.brain.mood = min(100, self.brain.mood + 10)
                self.brain.annoyance = 0
                self.applyEmotion(.happy)
                self.say("Petted!")
            } else {
                // Was dragged and dropped
                self.startDropAnimation()
                self.brain.mood = 100
                self.applyEmotion(.normal)
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.applyAction(self.brain.currentAction)
            }
        }
    }
}
