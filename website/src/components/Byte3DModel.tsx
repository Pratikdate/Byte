import React, { useEffect, useRef } from 'react';
import * as THREE from 'three';

export default function Byte3DModel() {
  const mountRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!mountRef.current) return;
    
    // Scene Setup
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(50, mountRef.current.clientWidth / mountRef.current.clientHeight, 0.1, 1000);
    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    
    renderer.setSize(mountRef.current.clientWidth, mountRef.current.clientHeight);
    renderer.setClearColor(0x000000, 0);
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = THREE.PCFShadowShadowMap;
    mountRef.current.appendChild(renderer.domElement);
    
    camera.position.set(0, 2, 20);
    camera.lookAt(0, 0, 0);

    // Orbit/Mouse Controls
    let rotation = { x: 0, y: 0 };
    
    const onMouseMove = (e: MouseEvent) => {
      // Normalize mouse coordinates for subtle look around effect (-1 to 1)
      rotation.y = (e.clientX / window.innerWidth) * 2 - 1;
      rotation.x = -((e.clientY / window.innerHeight) * 2 - 1);
    };
    
    window.addEventListener('mousemove', onMouseMove);

    // Lights
    const ambientLight = new THREE.AmbientLight(0xffffff, 0.4);
    scene.add(ambientLight);
    const directionalLight = new THREE.DirectionalLight(0xffffff, 1.2);
    directionalLight.position.set(-8, 15, 12);
    directionalLight.castShadow = true;
    directionalLight.shadow.mapSize.set(2048, 2048);
    scene.add(directionalLight);

    // Materials
    const shellMat = new THREE.MeshStandardMaterial({
        color: 0x1a1a1a,
        metalness: 0.8,
        roughness: 0.2
    });
    const darkMat = new THREE.MeshStandardMaterial({
        color: 0x0d0d0d,
        metalness: 0.5,
        roughness: 0.6
    });

    const petContainer = new THREE.Group();
    scene.add(petContainer);

    const SCALE = 2.5;

    // HEAD
    const headGeo = new THREE.BoxGeometry(4.0 * SCALE, 3.2 * SCALE, 3.2 * SCALE);
    const headMesh = new THREE.Mesh(headGeo, shellMat);
    petContainer.add(headMesh);

    // HEADPHONES
    const headphoneGeo = new THREE.CylinderGeometry(0.85 * SCALE, 0.85 * SCALE, 0.4 * SCALE, 32);
    const leftHeadphone = new THREE.Mesh(headphoneGeo, darkMat);
    leftHeadphone.position.set(-2.1 * SCALE, 0, 0);
    leftHeadphone.rotation.z = Math.PI / 2;
    headMesh.add(leftHeadphone);

    const rightHeadphone = new THREE.Mesh(headphoneGeo, darkMat);
    rightHeadphone.position.set(2.1 * SCALE, 0, 0);
    rightHeadphone.rotation.z = Math.PI / 2;
    headMesh.add(rightHeadphone);

    // BACKPACK
    const backpackGeo = new THREE.BoxGeometry(2.2 * SCALE, 1.8 * SCALE, 0.6 * SCALE);
    const backpackMesh = new THREE.Mesh(backpackGeo, darkMat);
    backpackMesh.position.set(0, -0.2 * SCALE, -1.8 * SCALE);
    headMesh.add(backpackMesh);

    // LEGS
    const legGeo = new THREE.BoxGeometry(0.55 * SCALE, 0.9 * SCALE, 0.55 * SCALE);
    const jointGeo = new THREE.SphereGeometry(0.35 * SCALE, 32, 32);

    const leftLegPivot = new THREE.Group();
    leftLegPivot.position.set(-0.6 * SCALE, -1.6 * SCALE, 0);
    petContainer.add(leftLegPivot);

    const leftJoint = new THREE.Mesh(jointGeo, shellMat);
    leftJoint.castShadow = true;
    leftLegPivot.add(leftJoint);

    const leftLegMesh = new THREE.Mesh(legGeo, darkMat);
    leftLegMesh.position.set(0, -0.45 * SCALE, 0);
    leftLegMesh.castShadow = true;
    leftLegPivot.add(leftLegMesh);

    const rightLegPivot = new THREE.Group();
    rightLegPivot.position.set(0.6 * SCALE, -1.6 * SCALE, 0);
    petContainer.add(rightLegPivot);

    const rightJoint = new THREE.Mesh(jointGeo, shellMat);
    rightJoint.castShadow = true;
    rightLegPivot.add(rightJoint);

    const rightLegMesh = new THREE.Mesh(legGeo, darkMat);
    rightLegMesh.position.set(0, -0.45 * SCALE, 0);
    rightLegMesh.castShadow = true;
    rightLegPivot.add(rightLegMesh);

    // SHOES
    const shoeGeo = new THREE.BoxGeometry(1.0 * SCALE, 0.3 * SCALE, 1.5 * SCALE);
    const leftShoe = new THREE.Mesh(shoeGeo, shellMat);
    leftShoe.position.set(0, -0.5 * SCALE, 0.35 * SCALE);
    leftShoe.castShadow = true;
    leftLegMesh.add(leftShoe);

    const rightShoe = new THREE.Mesh(shoeGeo, shellMat);
    rightShoe.position.set(0, -0.5 * SCALE, 0.35 * SCALE);
    rightShoe.castShadow = true;
    rightLegMesh.add(rightShoe);

    // DJ HEADBAND
    const topBandGeo = new THREE.BoxGeometry(4.6 * SCALE, 0.3 * SCALE, 0.6 * SCALE);
    const topBand = new THREE.Mesh(topBandGeo, shellMat);
    topBand.position.set(0, 1.7 * SCALE, 0);
    headMesh.add(topBand);

    const leftBandGeo = new THREE.BoxGeometry(0.3 * SCALE, 1.5 * SCALE, 0.6 * SCALE);
    const leftBand = new THREE.Mesh(leftBandGeo, shellMat);
    leftBand.position.set(-2.15 * SCALE, 1.0 * SCALE, 0);
    headMesh.add(leftBand);

    const rightBand = new THREE.Mesh(leftBandGeo, shellMat);
    rightBand.position.set(2.15 * SCALE, 1.0 * SCALE, 0);
    headMesh.add(rightBand);

    // SCREEN (Canvas texture for eyes)
    const screenCanvas = document.createElement('canvas');
    screenCanvas.width = 512;
    screenCanvas.height = 512;
    const screenCtx = screenCanvas.getContext('2d')!;

    const screenTexture = new THREE.CanvasTexture(screenCanvas);
    screenTexture.magFilter = THREE.LinearFilter;
    screenTexture.minFilter = THREE.LinearFilter;

    const screenMat = new THREE.MeshStandardMaterial({
        map: screenTexture,
        emissiveMap: screenTexture,
        emissive: 0x0066ff,
        emissiveIntensity: 0.8,
        metalness: 0.1,
        roughness: 0.2
    });

    const screenGeo = new THREE.PlaneGeometry(3.6 * SCALE, 2.8 * SCALE);
    const screenMesh = new THREE.Mesh(screenGeo, screenMat);
    screenMesh.position.set(0, 0, 1.61 * SCALE);
    headMesh.add(screenMesh);

    function getEyePath(emotion: string, isLeft: boolean) {
        const w = 36;
        const h = 80;
        const r = 14;
        let path = new Path2D();

        let topLeft = { x: -w/2, y: h/2 };
        let topRight = { x: w/2, y: h/2 };
        let botRight = { x: w/2, y: -h/2 };
        let botLeft = { x: -w/2, y: -h/2 };

        switch (emotion) {
            case 'happy':
            case 'excited':
                path.moveTo(-25, -10);
                path.quadraticCurveTo(0, 30, 25, -10);
                path.quadraticCurveTo(0, 10, -25, -10);
                path.closePath();
                return path;
            case 'love':
                path.moveTo(0, -20);
                path.bezierCurveTo(12, -10, 25, 0, 25, 10);
                path.bezierCurveTo(25, 25, 0, 25, 0, 10);
                path.bezierCurveTo(0, 25, -25, 25, -25, 10);
                path.bezierCurveTo(-25, 0, -12, -10, 0, -20);
                path.closePath();
                return path;
            case 'curious':
                if (isLeft) {
                    topLeft.y += 8; topRight.y += 8;
                    botLeft.y -= 8; botRight.y -= 8;
                } else {
                    topLeft.y -= 10; topRight.y -= 10;
                }
                break;
            case 'sad':
                if (isLeft) {
                    topLeft.y -= 25; topRight.y += 5; botRight.y += 5;
                } else {
                    topRight.y -= 25; topLeft.y += 5; botLeft.y += 5;
                }
                break;
            case 'dizzy':
                if (isLeft) {
                    topLeft.y -= 20; botRight.y += 20;
                } else {
                    topRight.y -= 20; botLeft.y += 20;
                }
                break;
            case 'normal':
            default:
                break;
        }

        const midBotX = (botLeft.x + botRight.x) / 2;
        const midBotY = (botLeft.y + botRight.y) / 2;

        path.moveTo(midBotX, midBotY);
        path.lineTo(botRight.x - r, botRight.y);
        path.quadraticCurveTo(botRight.x, botRight.y, botRight.x, botRight.y + r);
        path.lineTo(topRight.x, topRight.y - r);
        path.quadraticCurveTo(topRight.x, topRight.y, topRight.x - r, topRight.y);
        path.lineTo(topLeft.x + r, topLeft.y);
        path.quadraticCurveTo(topLeft.x, topLeft.y, topLeft.x, topLeft.y - r);
        path.lineTo(botLeft.x, botLeft.y + r);
        path.quadraticCurveTo(botLeft.x, botLeft.y, botLeft.x + r, botLeft.y);
        path.closePath();
        return path;
    }

    function drawEyes(emotion: string, blinkScale: number) {
        screenCtx.fillStyle = '#000000';
        screenCtx.fillRect(0, 0, 512, 512);

        const eyeColor = ['sad'].includes(emotion) ? '#4a90e2' :
            (['love', 'excited', 'happy'].includes(emotion) ? '#00ff88' : '#4a90e2');

        screenCtx.fillStyle = eyeColor;
        screenCtx.shadowColor = eyeColor;
        screenCtx.shadowBlur = 20;
        screenCtx.shadowOffsetX = 0;
        screenCtx.shadowOffsetY = 0;

        const scale = 2.5;
        const centerX = 256;
        const centerY = 256;

        screenCtx.save();
        screenCtx.translate(centerX - 128, centerY);
        screenCtx.scale(scale * 1.2, scale * 1.2 * blinkScale);
        screenCtx.fill(getEyePath(emotion, true));
        screenCtx.restore();

        screenCtx.save();
        screenCtx.translate(centerX + 128, centerY);
        screenCtx.scale(scale * 1.2, scale * 1.2 * blinkScale);
        screenCtx.fill(getEyePath(emotion, false));
        screenCtx.restore();

        screenTexture.needsUpdate = true;
    }

    let animationId: number;
    let time = 0;
    
    // Blinking State
    let blinkScale = 1.0;
    let isBlinking = false;
    let blinkTimer = 0;

    const animate = () => {
        animationId = requestAnimationFrame(animate);
        time += 0.03;

        // Handle Blinking (Blink every ~3-5 seconds)
        blinkTimer++;
        if (!isBlinking && blinkTimer > 150 + Math.random() * 100) {
            isBlinking = true;
            blinkTimer = 0;
        }
        if (isBlinking) {
            blinkScale -= 0.3; // Close eyes fast
            if (blinkScale <= 0.1) {
                blinkScale = 0.1;
                isBlinking = false; // Start opening
            }
        } else if (blinkScale < 1.0) {
            blinkScale += 0.2; // Open eyes fast
            if (blinkScale > 1.0) blinkScale = 1.0;
        }

        // Update Screen (Always normal emotion, just blinking)
        drawEyes('normal', blinkScale);

        // Mouse look effect
        const targetRadius = 20;
        const currentY = camera.position.y;
        
        camera.position.x += (Math.sin(rotation.y * 0.5) * targetRadius - camera.position.x) * 0.05;
        camera.position.y += ((2 + Math.tan(rotation.x * 0.2) * 5) - currentY) * 0.05;
        camera.position.z += (Math.cos(rotation.y * 0.5) * targetRadius - camera.position.z) * 0.05;
        camera.lookAt(0, 0, 0);

        // Reset transforms
        petContainer.position.set(0, 0, 0);
        petContainer.rotation.set(0, 0, 0);
        petContainer.scale.set(1, 1, 1);
        headMesh.position.set(0, 0, 0);
        headMesh.rotation.set(0, 0, 0);
        leftLegPivot.rotation.set(0, 0, 0);
        rightLegPivot.rotation.set(0, 0, 0);

        // Pure Idle floating animation
        petContainer.position.y = Math.sin(time * 0.5) * (0.2 * SCALE);
        // Look around animation mixed with idle
        headMesh.position.y = Math.sin(time * 2) * (0.05 * SCALE);
        headMesh.rotation.z = Math.sin(time * 0.5) * 0.05;
        headMesh.rotation.y = Math.sin(time * 0.3) * 0.1;

        renderer.render(scene, camera);
    };

    animate();

    // Handle resize
    const handleResize = () => {
      if (!mountRef.current) return;
      const width = mountRef.current.clientWidth;
      const height = mountRef.current.clientHeight;
      renderer.setSize(width, height);
      camera.aspect = width / height;
      camera.updateProjectionMatrix();
    };
    
    window.addEventListener('resize', handleResize);

    // Cleanup
    return () => {
      window.removeEventListener('mousemove', onMouseMove);
      window.removeEventListener('resize', handleResize);
      cancelAnimationFrame(animationId);
      if (mountRef.current) {
        mountRef.current.removeChild(renderer.domElement);
      }
      
      // Dispose materials/geometries
      headGeo.dispose();
      headphoneGeo.dispose();
      backpackGeo.dispose();
      legGeo.dispose();
      jointGeo.dispose();
      shoeGeo.dispose();
      topBandGeo.dispose();
      leftBandGeo.dispose();
      screenGeo.dispose();
      
      shellMat.dispose();
      darkMat.dispose();
      screenMat.dispose();
      screenTexture.dispose();
      renderer.dispose();
    };
  }, []);

  return <div ref={mountRef} style={{ width: '100%', height: '400px', maxWidth: '600px', margin: '0 auto', cursor: 'crosshair', filter: 'drop-shadow(0 20px 30px rgba(0,0,0,0.15))' }} />;
}
