//
//  LuckyChestScene.swift
//  Provikart
//
//  SceneKit Lucky Box: 3D lucky chest, kosočtvercová aréna a otáčení tahem.
//

import Metal
import SceneKit
import SwiftUI
import UIKit

@MainActor
final class LuckyChestController: NSObject, ObservableObject {
    static let shared = LuckyChestController()
    static let stageBackground = UIColor(red: 0.10, green: 0.26, blue: 0.46, alpha: 1)

    let scene: LuckyChestScene
    fileprivate let stageView: SCNView
    private var warmupWindow: UIWindow?

    @Published private(set) var previewImage: UIImage?
    @Published private(set) var isLive = false

    nonisolated(unsafe) private var didReportLive = false
    nonisolated(unsafe) private var lastRenderTime: CFTimeInterval = 0
    private var renderedHostFrames = 0
    private var warmupFrames = 0
    private var isHosted = false
    private var hostedAt: CFTimeInterval = 0
    private var appActiveObserver: NSObjectProtocol?
    private var appForegroundObserver: NSObjectProtocol?
    private var resumeWork: Task<Void, Never>?
    private var playWatchdog: Task<Void, Never>?

    private override init() {
        scene = LuckyChestScene()
        stageView = SCNView(frame: .zero)
        super.init()
        configureStageView()
        let resume: (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in
                self?.resumeIfNeeded()
            }
        }
        appActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main,
            using: resume
        )
        appForegroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main,
            using: resume
        )
    }

    /// Připraví stálý SCNView, Metal náhled a shadery, ať Lucky Box nezačíná černou obrazovkou.
    func prepareIfNeeded() {
        scene.ensureParticles()
        if previewImage == nil || isPreviewMostlyBlack(previewImage) {
            let image = renderPreviewImage()
            if !isPreviewMostlyBlack(image) {
                previewImage = image
            }
        }
        guard !isHosted else { return }
        installWarmupWindow()
        resumeRendering()
    }

    func attach(to host: UIView) {
        let moved = stageView.superview !== host
        isHosted = true
        hostedAt = CACurrentMediaTime()
        prepareIfNeeded()
        if moved {
            renderedHostFrames = 0
            didReportLive = false
            isLive = false
            lastRenderTime = 0
            stageView.removeFromSuperview()
            host.addSubview(stageView)
        }
        stageView.frame = host.bounds
        stageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let needsKick = moved || scene.scnScene.isPaused || stageView.scene?.isPaused == true || !stageView.isPlaying
        if needsKick {
            resumeRendering()
            scene.resumeIdleIfNeeded()
        }
        startPlayWatchdog()
    }

    func park() {
        isHosted = false
        didReportLive = false
        isLive = false
        resumeWork?.cancel()
        resumeWork = nil
        playWatchdog?.cancel()
        playWatchdog = nil
        stageView.isPlaying = false
        stageView.rendersContinuously = false
        installWarmupWindow()
    }

    /// Po návratu z pozadí / Face ID SceneKit často usne, dokud nepřijde dotyk.
    func resumeIfNeeded() {
        scene.scnScene.isPaused = false
        if isHosted || stageView.superview != nil {
            kickDisplayLink(reinstallIdle: true)
            scheduleResumeKicks()
            if isHosted {
                startPlayWatchdog()
            }
        } else {
            prepareIfNeeded()
        }
    }

    private func scheduleResumeKicks() {
        resumeWork?.cancel()
        resumeWork = Task { @MainActor [weak self] in
            // Display link se po Face ID / overlayi často nahoďí až v dalších runloop cyklech.
            for delayNs in [80_000_000, 250_000_000, 700_000_000, 1_400_000_000] as [UInt64] {
                try? await Task.sleep(nanoseconds: delayNs)
                guard let self, !Task.isCancelled else { return }
                guard self.isHosted || self.stageView.superview != nil else { return }
                self.kickIfStalled(reinstallIdle: self.isHosted)
            }
        }
    }

    private func startPlayWatchdog() {
        playWatchdog?.cancel()
        playWatchdog = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.isHosted {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard self.isHosted, !Task.isCancelled else { return }
                self.kickIfStalled(reinstallIdle: true)
            }
        }
    }

    private var isDisplayLinkStalled: Bool {
        if scene.scnScene.isPaused || stageView.scene?.isPaused == true || !stageView.isPlaying {
            return true
        }
        if lastRenderTime == 0 {
            return hostedAt > 0 && CACurrentMediaTime() - hostedAt > 0.45
        }
        return CACurrentMediaTime() - lastRenderTime > 0.4
    }

    private func kickIfStalled(reinstallIdle: Bool) {
        guard isDisplayLinkStalled else { return }
        kickDisplayLink(reinstallIdle: reinstallIdle)
    }

    private func kickDisplayLink(reinstallIdle: Bool) {
        resumeRendering()
        if reinstallIdle {
            scene.resumeIdleIfNeeded()
        }
    }

    private func resumeRendering() {
        scene.scnScene.isPaused = false
        stageView.scene?.isPaused = false
        stageView.rendersContinuously = true
        stageView.preferredFramesPerSecond = 60
        stageView.setNeedsLayout()
        stageView.layoutIfNeeded()
        // Vypnutí a zapnutí znovu vytvoří CADisplayLink, který po backgroundu často umře.
        stageView.isPlaying = false
        stageView.isPlaying = true
        stageView.sceneTime += 1.0 / 60.0
    }

    private func configureStageView() {
        stageView.scene = scene.scnScene
        stageView.pointOfView = scene.cameraNode
        stageView.backgroundColor = Self.stageBackground
        stageView.isOpaque = true
        stageView.autoenablesDefaultLighting = true
        stageView.allowsCameraControl = false
        stageView.antialiasingMode = .multisampling2X
        stageView.preferredFramesPerSecond = 60
        stageView.rendersContinuously = true
        stageView.isJitteringEnabled = false
        stageView.delegate = self
    }

    private func handleRenderedFrame() {
        if stageView.window === warmupWindow {
            warmupFrames += 1
            if previewImage == nil || isPreviewMostlyBlack(previewImage) {
                let snapshot = stageView.snapshot()
                if !isPreviewMostlyBlack(snapshot) {
                    previewImage = snapshot
                }
            }
            if warmupFrames >= 2, !isHosted {
                stageView.isPlaying = false
                stageView.rendersContinuously = false
            }
            return
        }
        guard !isLive else { return }
        renderedHostFrames += 1
        if renderedHostFrames >= 3 {
            didReportLive = true
            isLive = true
            warmupWindow?.isHidden = true
        }
    }

    private func renderPreviewImage() -> UIImage {
        let size = Self.previewSize
        let scale = min(2, UITraitCollection.current.displayScale)
        let pixelSize = CGSize(
            width: min(900, max(2, (size.width * scale).rounded())),
            height: min(1600, max(2, (size.height * scale).rounded()))
        )
        let renderer = SCNRenderer(device: stageView.device ?? MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene.scnScene
        renderer.pointOfView = scene.cameraNode
        return renderer.snapshot(atTime: 0, with: pixelSize, antialiasingMode: .multisampling2X)
    }

    private func isPreviewMostlyBlack(_ image: UIImage?) -> Bool {
        guard let image, let cgImage = image.cgImage else { return true }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 8, height > 8 else { return true }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return true }
        context.interpolationQuality = .none
        context.draw(
            cgImage,
            in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
        )
        // Prázdné navy pozadí bez truhly v centru zahodíme.
        return Int(pixel[0]) + Int(pixel[1]) + Int(pixel[2]) < 90
    }

    private func installWarmupWindow() {
        guard stageView.superview == nil || stageView.window === warmupWindow else { return }
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }

        let bounds = windowScene.coordinateSpace.bounds
        let window = warmupWindow ?? UIWindow(windowScene: windowScene)
        window.frame = bounds
        window.windowLevel = UIWindow.Level(rawValue: -1)
        window.backgroundColor = Self.stageBackground
        window.isUserInteractionEnabled = false
        window.isHidden = false
        warmupWindow = window
        warmupFrames = 0

        if stageView.superview !== window {
            window.addSubview(stageView)
        }
        stageView.frame = window.bounds
        stageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first
    }

    private static var previewSize: CGSize {
        let screen = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        if let screen {
            return screen.coordinateSpace.bounds.size
        }
        return CGSize(width: 390, height: 844)
    }
}

extension LuckyChestController: SCNSceneRendererDelegate {
    nonisolated func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
        lastRenderTime = CACurrentMediaTime()
        if scene.isPaused {
            scene.isPaused = false
        }
        if didReportLive { return }
        Task { @MainActor in
            self.handleRenderedFrame()
        }
    }
}

private final class LuckyChestStageContainer: UIView {
    override func layoutSubviews() {
        super.layoutSubviews()
        subviews.first { $0 is SCNView }?.frame = bounds
    }
}

struct LuckyChestStageView: UIViewRepresentable {
    let controller: LuckyChestController
    var onTap: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller, onTap: onTap)
    }

    func makeUIView(context: Context) -> UIView {
        let container = LuckyChestStageContainer()
        container.backgroundColor = LuckyChestController.stageBackground
        container.isOpaque = true
        container.clipsToBounds = true
        controller.attach(to: container)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        container.addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.require(toFail: pan)
        container.addGestureRecognizer(tap)

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.controller = controller
        controller.attach(to: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.controller.park()
    }

    final class Coordinator: NSObject {
        var controller: LuckyChestController
        var onTap: () -> Void
        private var lastTranslation: CGPoint = .zero

        init(controller: LuckyChestController, onTap: @escaping () -> Void) {
            self.controller = controller
            self.onTap = onTap
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            switch gesture.state {
            case .began:
                lastTranslation = .zero
                controller.scene.beginUserRotate()
            case .changed:
                let dx = Float(translation.x - lastTranslation.x)
                let dy = Float(translation.y - lastTranslation.y)
                lastTranslation = translation
                controller.scene.userRotate(dx: dx, dy: dy)
            default:
                controller.scene.endUserRotate()
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            onTap()
        }
    }
}

struct LuckyChestPlaceholderView: View {
    var rarity: LuckyBoxRarity = .common

    var body: some View {
        GeometryReader { geo in
            let w = min(geo.size.width * 0.34, 148)
            let h = w * 0.92
            ZStack {
                Image(uiImage: LuckyChestScene.diamondImage(for: rarity))
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                Ellipse()
                    .fill(Color.black.opacity(0.38))
                    .frame(width: w * 1.35, height: w * 0.32)
                    .offset(y: h * 0.42)
                    .blur(radius: 10)

                chestShape(width: w, height: h)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }

    private func chestShape(width w: CGFloat, height h: CGFloat) -> some View {
        let crystal = rarity.enamel
        let bronze = Color(red: 0.82, green: 0.54, blue: 0.22)
        let wood = Color(red: 0.58, green: 0.34, blue: 0.16)

        return ZStack {
            RoundedRectangle(cornerRadius: w * 0.06, style: .continuous)
                .fill(wood)
                .frame(width: w, height: h * 0.48)
                .offset(y: h * 0.18)

            HStack(spacing: w * 0.42) {
                RoundedRectangle(cornerRadius: 4).fill(bronze).frame(width: w * 0.16, height: h * 0.16)
                RoundedRectangle(cornerRadius: 4).fill(bronze).frame(width: w * 0.16, height: h * 0.16)
            }
            .offset(y: h * 0.36)

            UnevenRoundedRectangle(
                topLeadingRadius: w * 0.48,
                bottomLeadingRadius: w * 0.06,
                bottomTrailingRadius: w * 0.06,
                topTrailingRadius: w * 0.48,
                style: .continuous
            )
            .fill(crystal)
            .shadow(color: crystal.opacity(0.7), radius: 8)
            .frame(width: w * 1.02, height: h * 0.38)
            .offset(y: -h * 0.14)

            HStack(spacing: w * 0.22) {
                Capsule().fill(bronze).frame(width: w * 0.11)
                Capsule().fill(bronze).frame(width: w * 0.11)
                Capsule().fill(bronze).frame(width: w * 0.11)
            }
            .frame(height: h * 0.50)
            .offset(y: -h * 0.12)

            RoundedRectangle(cornerRadius: 3)
                .fill(wood)
                .frame(width: w * 1.04, height: h * 0.07)
                .offset(y: h * 0.04)

            RoundedRectangle(cornerRadius: 6)
                .fill(bronze)
                .frame(width: w * 0.28, height: h * 0.28)
                .overlay {
                    Capsule().fill(Color.black.opacity(0.55)).frame(width: 7, height: 16)
                }
                .offset(y: h * 0.12)

            HStack(spacing: w * 0.42) {
                Rectangle().fill(crystal).rotationEffect(.degrees(45)).frame(width: w * 0.09, height: w * 0.09)
                Rectangle().fill(crystal).rotationEffect(.degrees(45)).frame(width: w * 0.09, height: w * 0.09)
            }
            .shadow(color: crystal.opacity(0.8), radius: 4)
            .offset(y: h * 0.22)
        }
    }
}

final class LuckyChestScene {

    let scnScene = SCNScene()
    let cameraNode = SCNNode()

    private let stageRoot = SCNNode()
    private let orbitNode = SCNNode()
    private let spinNode = SCNNode()
    private let chestRoot = SCNNode()
    private let lidPivot = SCNNode()
    private let innerLightNode = SCNNode()
    private let interiorGlowNode = SCNNode()
    private let floorGlowNode = SCNNode()
    private let rarityGlowNode = SCNNode()
    private let keyLightNode = SCNNode()
    private let fillLightNode = SCNNode()
    private let rimLightNode = SCNNode()
    private let ambientNode = SCNNode()

    private var bodyMaterial = SCNMaterial()
    private var barrelMaterial = SCNMaterial()
    private var panelMaterial = SCNMaterial()
    private var goldMaterial = SCNMaterial()
    private var lockMaterial = SCNMaterial()
    private var darkWoodMaterial = SCNMaterial()
    private var floorMaterial = SCNMaterial()
    private var glowMaterial = SCNMaterial()
    private var rarityGlowMaterial = SCNMaterial()
    private var interiorMaterial = SCNMaterial()

    private var atmosphere: SCNParticleSystem?
    private var sparkles: SCNParticleSystem?
    private var idleRunning = false
    private var isRevealed = false
    private var isUserRotating = false
    private var currentRarity: LuckyBoxRarity = .common
    private var userYaw: Float = 0.08
    private var userPitch: Float = -0.16

    private let bronzeTint = UIColor(red: 0.82, green: 0.54, blue: 0.22, alpha: 1)
    private let bronzeDark = UIColor(red: 0.38, green: 0.20, blue: 0.08, alpha: 1)
    private let displayScale: Float = 0.42
    private let restY: Float = 0.04
    private let lidHinge = SCNVector3(0, 0.35, -0.50)

    init() {
        buildWorld()
        applyRarity(.common, revealed: false)
        applyOrbit()
        startIdleIfNeeded()
    }

    func applyRarity(_ rarity: LuckyBoxRarity, revealed: Bool) {
        currentRarity = rarity
        isRevealed = revealed
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.45
        paintRarity(rarity)
        if revealed {
            stopIdle()
            chestRoot.opacity = 0
            chestRoot.isHidden = true
            atmosphere?.birthRate = 6
            sparkles?.birthRate = 0
            innerLightNode.light?.intensity = 0
            rarityGlowNode.opacity = 0
        } else if chestRoot.isHidden {
            chestRoot.isHidden = false
            chestRoot.opacity = 1
            innerLightNode.light?.intensity = innerGlowIntensity(for: currentRarity)
            startIdleIfNeeded()
        }
        SCNTransaction.commit()
    }

    func playHit(upgraded: Bool) async {
        guard !isRevealed else { return }
        stopIdle()
        spinNode.removeAllActions()
        chestRoot.removeAllActions()
        resetPose(keepOrbit: true)
        boostParticles(upgraded)

        await runAsync(squash(mulX: 1.08, y: 0.9, z: 1.08, duration: 0.08), on: chestRoot)
        await runAsync(squash(mulX: 1, y: 1, z: 1, duration: 0.1), on: chestRoot)
        guard !Task.isCancelled else {
            resetPose(keepOrbit: true)
            startIdleIfNeeded()
            return
        }

        let turns: CGFloat = upgraded ? 2 : 1
        let spin = SCNAction.rotateBy(x: 0, y: .pi * 2 * turns, z: 0, duration: upgraded ? 0.7 : 0.5)
        spin.timingMode = .easeInEaseOut
        let hop = SCNAction.sequence([
            SCNAction.moveBy(x: 0, y: upgraded ? 0.14 : 0.08, z: 0, duration: (upgraded ? 0.7 : 0.5) * 0.45),
            SCNAction.moveBy(x: 0, y: upgraded ? -0.14 : -0.08, z: 0, duration: (upgraded ? 0.7 : 0.5) * 0.55)
        ])
        hop.timingMode = .easeInEaseOut

        async let spinWait: Void = runAsync(spin, on: spinNode)
        async let hopWait: Void = runAsync(hop, on: stageRoot)
        _ = await (spinWait, hopWait)
        guard !Task.isCancelled else {
            resetPose(keepOrbit: true)
            startIdleIfNeeded()
            return
        }

        if upgraded {
            spawnBurst(count: 18, speed: 1.3)
            await runAsync(squash(mulX: 1.06, y: 1.06, z: 1.06, duration: 0.1), on: chestRoot)
            await runAsync(squash(mulX: 1, y: 1, z: 1, duration: 0.18), on: chestRoot)
        }

        resetPose(keepOrbit: true)
        restoreParticles()
        startIdleIfNeeded()
    }

    func playOpenAnticipation() async {
        guard !isRevealed else { return }
        stopIdle()
        faceForOpening()
        boostParticles(true)
        spawnBurst(count: 8, speed: 0.6)

        for i in 0..<4 {
            guard !Task.isCancelled else { return }
            let sign: CGFloat = i.isMultiple(of: 2) ? -1 : 1
            let tilt = SCNAction.rotateTo(
                x: 0,
                y: CGFloat(sign) * 0.12,
                z: CGFloat(sign) * 0.06,
                duration: 0.07
            )
            await runAsync(
                .group([
                    tilt,
                    squash(mulX: i.isMultiple(of: 2) ? 1.04 : 0.96, y: i.isMultiple(of: 2) ? 0.96 : 1.04, z: 1, duration: 0.07)
                ]),
                on: chestRoot
            )
        }

        await runAsync(
            .group([
                .rotateTo(x: 0, y: 0, z: 0, duration: 0.08),
                squash(mulX: 1, y: 1, z: 1, duration: 0.08)
            ]),
            on: chestRoot
        )
    }

    /// Odklopí víko a nechá otevřenou bednu chvíli svítit, ať je otevření vidět.
    func playLidOpen() async {
        guard !isRevealed else { return }
        stopIdle()
        faceForOpening()
        boostParticles(true)

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.18
        innerLightNode.light?.intensity = 90
        innerLightNode.light?.color = UIColor(currentRarity.enamel)
        interiorGlowNode.opacity = 0.22
        SCNTransaction.commit()

        let creak = SCNAction.rotateTo(x: -0.32, y: 0, z: 0, duration: 0.22)
        creak.timingMode = .easeOut
        await runAsync(creak, on: lidPivot)
        guard !Task.isCancelled else { return }

        let settle = SCNAction.rotateTo(x: -0.08, y: 0, z: 0, duration: 0.12)
        settle.timingMode = .easeIn
        await runAsync(settle, on: lidPivot)
        guard !Task.isCancelled else { return }

        spawnBurst(count: 22, speed: 1.15)
        sparkles?.birthRate = 16
        atmosphere?.birthRate = 18

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.35
        innerLightNode.light?.intensity = 260
        interiorGlowNode.opacity = 0.95
        rarityGlowNode.opacity = min(0.7, CGFloat(currentRarity.glowStrength) + 0.28)
        SCNTransaction.commit()

        let openLid = SCNAction.rotateTo(x: -1.78, y: 0, z: 0, duration: 0.78)
        openLid.timingMode = .easeOut
        let lift = SCNAction.moveBy(x: 0, y: 0.05, z: -0.04, duration: 0.78)
        lift.timingMode = .easeOut
        await runAsync(.group([openLid, lift]), on: lidPivot)
        guard !Task.isCancelled else { return }

        let bounce = SCNAction.rotateTo(x: -1.62, y: 0, z: 0, duration: 0.12)
        bounce.timingMode = .easeInEaseOut
        await runAsync(bounce, on: lidPivot)

        spawnBurst(count: 14, speed: 0.85)
        try? await Task.sleep(nanoseconds: 700_000_000)
    }

    /// Pokračování: otevřená bedna zmizí, ať může nastoupit karta.
    func playOpenExit() async {
        spawnBurst(count: 18, speed: 1.4)
        await runAsync(
            .sequence([
                squash(mulX: 1.08, y: 1.08, z: 1.08, duration: 0.16),
                .group([
                    .fadeOut(duration: 0.38),
                    squash(mulX: 0.78, y: 0.78, z: 0.78, duration: 0.38)
                ])
            ]),
            on: chestRoot
        )
        hideChestInstantly()
    }

    func playRevealBurst() async {
        await playLidOpen()
        guard !Task.isCancelled else { return }
        await playOpenExit()
    }

    func hideChestInstantly() {
        isRevealed = true
        stopIdle()
        chestRoot.removeAllActions()
        lidPivot.removeAllActions()
        chestRoot.isHidden = true
        chestRoot.opacity = 0
        interiorGlowNode.opacity = 0
        atmosphere?.birthRate = 6
        sparkles?.birthRate = 0
        innerLightNode.light?.intensity = 0
        rarityGlowNode.opacity = 0
    }

    func resetToClosed() {
        isRevealed = false
        isUserRotating = false
        userYaw = 0.08
        userPitch = -0.16
        stageRoot.removeAllActions()
        spinNode.removeAllActions()
        chestRoot.removeAllActions()
        lidPivot.removeAllActions()
        resetPose(keepOrbit: false)
        lidPivot.eulerAngles = SCNVector3Zero
        lidPivot.position = lidHinge
        interiorGlowNode.opacity = 0
        chestRoot.isHidden = false
        chestRoot.opacity = 1
        innerLightNode.light?.intensity = innerGlowIntensity(for: currentRarity)
        restoreParticles()
        paintRarity(currentRarity)
        startIdleIfNeeded()
    }

    func beginUserRotate() {
        guard !isRevealed else { return }
        isUserRotating = true
        stopIdle()
        spinNode.removeAllActions()
    }

    func userRotate(dx: Float, dy: Float) {
        guard !isRevealed, isUserRotating else { return }
        userYaw += dx * 0.012
        userPitch = max(-0.45, min(0.32, userPitch + dy * 0.008))
        applyOrbit()
    }

    func endUserRotate() {
        isUserRotating = false
        startIdleIfNeeded()
    }

    private func faceForOpening() {
        isUserRotating = false
        spinNode.removeAllActions()
        chestRoot.removeAllActions()
        lidPivot.removeAllActions()
        spinNode.eulerAngles = SCNVector3Zero
        chestRoot.eulerAngles = SCNVector3Zero
        chestRoot.scale = SCNVector3(displayScale, displayScale, displayScale)
        chestRoot.opacity = 1
        chestRoot.isHidden = false
        lidPivot.eulerAngles = SCNVector3Zero
        lidPivot.position = lidHinge
        stageRoot.position = SCNVector3(0, restY, 0)
        userYaw = 0.22
        userPitch = -0.30
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.28
        applyOrbit()
        SCNTransaction.commit()
    }

    // MARK: - World

    private func buildWorld() {
        scnScene.background.contents = Self.diamondImage(for: .common)
        scnScene.lightingEnvironment.contents = nil
        scnScene.lightingEnvironment.intensity = 0
        scnScene.fogStartDistance = 3.2
        scnScene.fogEndDistance = 9.5
        scnScene.fogColor = UIColor(red: 0.08, green: 0.20, blue: 0.36, alpha: 1)

        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 32
        cameraNode.camera?.wantsHDR = false
        cameraNode.camera?.wantsExposureAdaptation = false
        cameraNode.camera?.bloomIntensity = 0
        cameraNode.position = SCNVector3(0, 1.08, 3.35)
        cameraNode.look(at: SCNVector3(0, 0.04, 0))
        scnScene.rootNode.addChildNode(cameraNode)

        buildArenaFloor()
        buildLights()
        buildChest()

        stageRoot.addChildNode(orbitNode)
        orbitNode.addChildNode(spinNode)
        spinNode.addChildNode(chestRoot)
        scnScene.rootNode.addChildNode(stageRoot)
        stageRoot.position = SCNVector3(0, restY, 0)
        chestRoot.scale = SCNVector3(displayScale, displayScale, displayScale)

        ensureParticles()
    }

    func ensureParticles() {
        guard atmosphere == nil else { return }
        buildParticles()
        restoreParticles()
    }

    private func buildArenaFloor() {
        floorMaterial = SCNMaterial()
        floorMaterial.lightingModel = .constant
        floorMaterial.diffuse.contents = Self.diamondTile(for: .common)
        floorMaterial.emission.contents = UIColor.black
        floorMaterial.locksAmbientWithDiffuse = true
        floorMaterial.diffuse.wrapS = .repeat
        floorMaterial.diffuse.wrapT = .repeat
        floorMaterial.diffuse.contentsTransform = SCNMatrix4MakeScale(9, 11, 1)
        floorMaterial.diffuse.magnificationFilter = .linear
        floorMaterial.diffuse.minificationFilter = .linear

        let floor = SCNPlane(width: 12, height: 14)
        floor.firstMaterial = floorMaterial
        let floorNode = SCNNode(geometry: floor)
        floorNode.eulerAngles.x = -.pi / 2
        floorNode.position = SCNVector3(0, -0.17, 0.15)
        scnScene.rootNode.addChildNode(floorNode)

        glowMaterial = unlitMaterial(UIColor.black)
        glowMaterial.diffuse.contents = Self.shadowImage
        glowMaterial.writesToDepthBuffer = false
        glowMaterial.blendMode = .alpha
        let shadow = SCNPlane(width: 1.15, height: 0.82)
        shadow.firstMaterial = glowMaterial
        floorGlowNode.geometry = shadow
        floorGlowNode.eulerAngles.x = -.pi / 2
        floorGlowNode.position = SCNVector3(0, -0.162, 0.06)
        floorGlowNode.opacity = 0.5
        floorGlowNode.castsShadow = false
        scnScene.rootNode.addChildNode(floorGlowNode)

        rarityGlowMaterial = unlitMaterial(UIColor(red: 0.25, green: 0.7, blue: 1, alpha: 1))
        rarityGlowMaterial.diffuse.contents = Self.blobImage
        rarityGlowMaterial.emission.contents = UIColor.black
        rarityGlowMaterial.writesToDepthBuffer = false
        rarityGlowMaterial.blendMode = .add
        let halo = SCNPlane(width: 1.55, height: 1.1)
        halo.firstMaterial = rarityGlowMaterial
        rarityGlowNode.geometry = halo
        rarityGlowNode.eulerAngles.x = -.pi / 2
        rarityGlowNode.position = SCNVector3(0, -0.158, 0.06)
        rarityGlowNode.opacity = 0.28
        rarityGlowNode.castsShadow = false
        scnScene.rootNode.addChildNode(rarityGlowNode)
    }

    private func buildLights() {
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 320
        ambient.color = UIColor(red: 0.55, green: 0.68, blue: 0.82, alpha: 1)
        ambientNode.light = ambient
        scnScene.rootNode.addChildNode(ambientNode)

        let key = SCNLight()
        key.type = .directional
        key.intensity = 920
        key.color = UIColor(red: 1.0, green: 0.97, blue: 0.92, alpha: 1)
        key.castsShadow = false
        keyLightNode.light = key
        keyLightNode.eulerAngles = SCNVector3(-0.55, 0.25, 0)
        scnScene.rootNode.addChildNode(keyLightNode)

        let fill = SCNLight()
        fill.type = .omni
        fill.intensity = 240
        fill.color = UIColor(red: 0.45, green: 0.78, blue: 1.0, alpha: 1)
        fill.attenuationEndDistance = 16
        fillLightNode.light = fill
        fillLightNode.position = SCNVector3(-2.2, 1.5, 2.8)
        scnScene.rootNode.addChildNode(fillLightNode)

        let rim = SCNLight()
        rim.type = .omni
        rim.intensity = 280
        rim.color = bronzeTint
        rim.attenuationEndDistance = 14
        rimLightNode.light = rim
        rimLightNode.position = SCNVector3(1.5, 1.7, -2.6)
        scnScene.rootNode.addChildNode(rimLightNode)

        let inner = SCNLight()
        inner.type = .omni
        inner.intensity = innerGlowIntensity(for: .common)
        inner.color = UIColor(LuckyBoxRarity.common.enamel)
        inner.attenuationEndDistance = 3.5
        innerLightNode.light = inner
        innerLightNode.position = SCNVector3(0, 0.18, 0.08)
        chestRoot.addChildNode(innerLightNode)
    }

    private func buildChest() {
        bodyMaterial = woodMaterial()
        darkWoodMaterial = woodMaterial()
        darkWoodMaterial.diffuse.contents = UIColor(red: 0.32, green: 0.18, blue: 0.08, alpha: 1)
        darkWoodMaterial.multiply.contents = UIColor(red: 0.32, green: 0.18, blue: 0.08, alpha: 1)
        barrelMaterial = crystalMaterial(UIColor(LuckyBoxRarity.common.enamel))
        panelMaterial = crystalMaterial(UIColor(LuckyBoxRarity.common.enamel))
        goldMaterial = metalMaterial(bronzeTint)
        lockMaterial = metalMaterial(bronzeDark)

        let bodyW: CGFloat = 1.48
        let bodyH: CGFloat = 0.70
        let bodyD: CGFloat = 1.00
        let barrelR: CGFloat = 0.48

        let body = box(bodyW, bodyH, bodyD, chamfer: 0.05, material: bodyMaterial)
        body.position = SCNVector3(0, 0, 0)
        chestRoot.addChildNode(body)

        for offset: Float in [-0.20, -0.02, 0.16] {
            let plank = box(bodyW - 0.12, 0.03, 0.04, chamfer: 0.01, material: darkWoodMaterial)
            plank.position = SCNVector3(0, offset, Float(bodyD / 2) + 0.01)
            chestRoot.addChildNode(plank)
        }

        for x in [-0.76, 0.76] as [Float] {
            let wall = box(0.08, bodyH - 0.02, bodyD - 0.08, chamfer: 0.02, material: bodyMaterial)
            wall.position = SCNVector3(x, 0, 0)
            chestRoot.addChildNode(wall)

            let frame = box(0.05, bodyH + 0.02, bodyD - 0.02, chamfer: 0.02, material: goldMaterial)
            frame.position = SCNVector3(x * 1.04, 0, 0)
            chestRoot.addChildNode(frame)

            for offset: Float in [-0.20, -0.02, 0.16] {
                let sidePlank = box(0.04, 0.03, bodyD - 0.18, chamfer: 0.01, material: darkWoodMaterial)
                sidePlank.position = SCNVector3(x * 1.08, offset, 0)
                chestRoot.addChildNode(sidePlank)
            }
        }

        let seat = box(bodyW + 0.06, 0.08, bodyD + 0.06, chamfer: 0.03, material: goldMaterial)
        seat.position = SCNVector3(0, Float(bodyH / 2), 0)
        chestRoot.addChildNode(seat)

        for x in [-0.66, 0.66] as [Float] {
            for z in [-0.44, 0.44] as [Float] {
                let corner = box(0.28, 0.18, 0.28, chamfer: 0.05, material: goldMaterial)
                corner.position = SCNVector3(x, -0.38, z)
                chestRoot.addChildNode(corner)
                addRivet(at: SCNVector3(x, -0.30, z * 1.12))
            }
        }

        for x in [-0.66, 0.66] as [Float] {
            let shoulder = box(0.30, 0.22, 0.28, chamfer: 0.07, material: goldMaterial)
            shoulder.position = SCNVector3(x, 0.26, 0.42)
            chestRoot.addChildNode(shoulder)
            addRivet(at: SCNVector3(x, 0.30, 0.56))
        }

        for x in [-0.42, 0.42] as [Float] {
            let latch = box(0.10, 0.36, 0.08, chamfer: 0.02, material: goldMaterial)
            latch.position = SCNVector3(x, 0.22, 0.54)
            chestRoot.addChildNode(latch)
            addRivet(at: SCNVector3(x, 0.32, 0.59))
            addRivet(at: SCNVector3(x, 0.12, 0.59))
        }

        addGem(at: SCNVector3(-0.34, -0.08, 0.53))
        addGem(at: SCNVector3(0.34, -0.08, 0.53))

        interiorMaterial = unlitMaterial(UIColor(LuckyBoxRarity.common.enamel))
        interiorMaterial.diffuse.contents = Self.blobImage
        interiorMaterial.multiply.contents = UIColor(LuckyBoxRarity.common.enamel)
        interiorMaterial.blendMode = .add
        interiorMaterial.writesToDepthBuffer = false
        let well = SCNPlane(width: 1.18, height: 0.78)
        well.firstMaterial = interiorMaterial
        interiorGlowNode.geometry = well
        interiorGlowNode.eulerAngles.x = -.pi / 2
        interiorGlowNode.position = SCNVector3(0, 0.20, 0.06)
        interiorGlowNode.opacity = 0
        interiorGlowNode.castsShadow = false
        chestRoot.addChildNode(interiorGlowNode)

        lidPivot.position = lidHinge
        chestRoot.addChildNode(lidPivot)

        let vaultWidth: CGFloat = 1.28
        let vault = SCNShape(path: lidDPath(radius: barrelR, lift: 0, steps: 16), extrusionDepth: vaultWidth)
        paintGeometry(vault, with: barrelMaterial)
        let vaultNode = SCNNode(geometry: vault)
        vaultNode.eulerAngles.y = .pi / 2
        vaultNode.position = SCNVector3(0, 0, 0.50)
        lidPivot.addChildNode(vaultNode)

        addLidSidePlate(x: -0.72, radius: barrelR)
        addLidSidePlate(x: 0.72, radius: barrelR)

        let strapXs: [Float] = [-0.40, 0, 0.40]
        for x in strapXs {
            addLidBand(x: x, radius: barrelR)
        }

        addLidFrontPlate()

        let lidWood = box(bodyW + 0.02, 0.15, bodyD + 0.04, chamfer: 0.03, material: bodyMaterial)
        lidWood.position = SCNVector3(0, 0.04, 0.50)
        lidPivot.addChildNode(lidWood)

        let lidLip = box(bodyW + 0.06, 0.055, 0.09, chamfer: 0.02, material: goldMaterial)
        lidLip.position = SCNVector3(0, 0.01, 1.03)
        lidPivot.addChildNode(lidLip)

        buildLock()
    }

    private func lidDPath(radius: CGFloat, lift: CGFloat, steps: Int) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: -radius, y: lift))
        path.addLine(to: CGPoint(x: radius, y: lift))
        for index in 0...steps {
            let theta = CGFloat(index) / CGFloat(steps) * .pi
            path.addLine(to: CGPoint(x: radius * cos(theta), y: lift + radius * sin(theta)))
        }
        path.close()
        path.flatness = 0.006
        return path
    }

    private func lidStrapPath(radius: CGFloat, thickness: CGFloat) -> UIBezierPath {
        let outer = radius + thickness
        let inner = radius
        let steps = 24
        let path = UIBezierPath()
        path.move(to: CGPoint(x: outer, y: 0))
        for index in 0...steps {
            let theta = CGFloat(index) / CGFloat(steps) * .pi
            path.addLine(to: CGPoint(x: outer * cos(theta), y: outer * sin(theta)))
        }
        for index in (0...steps).reversed() {
            let theta = CGFloat(index) / CGFloat(steps) * .pi
            path.addLine(to: CGPoint(x: inner * cos(theta), y: inner * sin(theta)))
        }
        path.close()
        path.flatness = 0.005
        return path
    }

    private func paintGeometry(_ geometry: SCNGeometry, with material: SCNMaterial) {
        geometry.firstMaterial = material
        let count = max(1, geometry.materials.count)
        geometry.materials = Array(repeating: material, count: count)
    }

    private func addLidBand(x: Float, radius: CGFloat) {
        let thickness: CGFloat = 0.085
        let band = SCNShape(path: lidStrapPath(radius: radius, thickness: thickness), extrusionDepth: 0.16)
        paintGeometry(band, with: goldMaterial)
        let bandNode = SCNNode(geometry: band)
        bandNode.eulerAngles.y = .pi / 2
        bandNode.position = SCNVector3(x, 0, 0.50)
        lidPivot.addChildNode(bandNode)

        let rivetR = Float(radius) + Float(thickness) * 0.55
        let angles: [Float] = [0.22, 0.55, 0.90, 1.25, 1.57, 1.89, 2.24, 2.59, 2.92]
        for theta in angles {
            addRivet(
                at: SCNVector3(x, rivetR * sin(theta), 0.50 + rivetR * cos(theta)),
                parent: lidPivot
            )
        }
    }

    private func addLidFrontPlate() {
        let shield = UIBezierPath()
        shield.move(to: CGPoint(x: 0, y: 0.11))
        shield.addLine(to: CGPoint(x: 0.08, y: 0.05))
        shield.addLine(to: CGPoint(x: 0.07, y: -0.04))
        shield.addLine(to: CGPoint(x: 0, y: -0.10))
        shield.addLine(to: CGPoint(x: -0.07, y: -0.04))
        shield.addLine(to: CGPoint(x: -0.08, y: 0.05))
        shield.close()

        let plate = SCNShape(path: shield, extrusionDepth: 0.055)
        paintGeometry(plate, with: goldMaterial)
        let plateNode = SCNNode(geometry: plate)
        plateNode.position = SCNVector3(0, 0.18, 0.99)
        lidPivot.addChildNode(plateNode)
        addRivet(at: SCNVector3(0, 0.22, 1.03), parent: lidPivot)
    }

    private func addLidSidePlate(x: Float, radius: CGFloat) {
        let outer = radius + 0.05
        let frame = SCNShape(path: lidDPath(radius: outer, lift: 0, steps: 20), extrusionDepth: 0.12)
        paintGeometry(frame, with: bodyMaterial)
        let frameNode = SCNNode(geometry: frame)
        frameNode.eulerAngles.y = .pi / 2
        frameNode.position = SCNVector3(x, 0, 0.50)
        lidPivot.addChildNode(frameNode)

        let inner = radius - 0.08
        let crystal = SCNShape(path: lidDPath(radius: inner, lift: 0.05, steps: 16), extrusionDepth: 0.07)
        paintGeometry(crystal, with: barrelMaterial)
        let crystalNode = SCNNode(geometry: crystal)
        crystalNode.eulerAngles.y = .pi / 2
        crystalNode.position = SCNVector3(x + (x > 0 ? 0.045 : -0.045), 0, 0.50)
        lidPivot.addChildNode(crystalNode)

        let cap = box(0.12, 0.10, 0.14, chamfer: 0.03, material: goldMaterial)
        cap.position = SCNVector3(x + (x > 0 ? 0.04 : -0.04), Float(outer) + 0.02, 0.50)
        lidPivot.addChildNode(cap)
        addRivet(
            at: SCNVector3(x + (x > 0 ? 0.07 : -0.07), Float(outer) + 0.06, 0.50),
            parent: lidPivot
        )
    }

    private func addRivet(at position: SCNVector3, parent: SCNNode? = nil) {
        let sphere = SCNSphere(radius: 0.045)
        sphere.segmentCount = 10
        sphere.firstMaterial = goldMaterial
        let node = SCNNode(geometry: sphere)
        node.position = position
        (parent ?? chestRoot).addChildNode(node)
    }

    private func addGem(at position: SCNVector3) {
        let gem = box(0.13, 0.13, 0.07, chamfer: 0.01, material: panelMaterial)
        gem.eulerAngles.z = .pi / 4
        gem.position = position
        chestRoot.addChildNode(gem)
    }

    private func buildLock() {
        let plate = box(0.36, 0.42, 0.12, chamfer: 0.05, material: goldMaterial)
        plate.position = SCNVector3(0, 0.06, 0.56)
        chestRoot.addChildNode(plate)
        addRivet(at: SCNVector3(-0.12, 0.20, 0.63))
        addRivet(at: SCNVector3(0.12, 0.20, 0.63))
        addRivet(at: SCNVector3(-0.12, -0.08, 0.63))
        addRivet(at: SCNVector3(0.12, -0.08, 0.63))

        let hole = SCNCylinder(radius: 0.055, height: 0.08)
        hole.firstMaterial = lockMaterial
        let holeNode = SCNNode(geometry: hole)
        holeNode.eulerAngles.x = .pi / 2
        holeNode.position = SCNVector3(0, 0.12, 0.63)
        chestRoot.addChildNode(holeNode)

        let slot = box(0.06, 0.12, 0.06, chamfer: 0.015, material: lockMaterial)
        slot.position = SCNVector3(0, 0.02, 0.63)
        chestRoot.addChildNode(slot)
    }

    private func buildParticles() {
        let blob = Self.blobImage

        let air = SCNParticleSystem()
        air.particleImage = blob
        air.birthRate = 7
        air.particleLifeSpan = 4.8
        air.particleLifeSpanVariation = 1.6
        air.particleSize = 0.05
        air.particleSizeVariation = 0.025
        air.particleColor = UIColor(red: 0.7, green: 0.88, blue: 1, alpha: 0.38)
        air.emitterShape = SCNSphere(radius: 2.2)
        air.birthLocation = .volume
        air.spreadingAngle = 0
        air.particleVelocity = 0.05
        air.acceleration = SCNVector3(0, 0.05, 0)
        air.blendMode = .additive
        air.loops = true
        air.isLightingEnabled = false
        scnScene.rootNode.addParticleSystem(air)
        atmosphere = air

        let spark = SCNParticleSystem()
        spark.particleImage = blob
        spark.birthRate = 0
        spark.particleLifeSpan = 1.1
        spark.particleLifeSpanVariation = 0.3
        spark.particleSize = 0.04
        spark.particleSizeVariation = 0.02
        spark.particleColor = UIColor(LuckyBoxRarity.common.enamel).withAlphaComponent(0.75)
        spark.emitterShape = SCNSphere(radius: 0.75)
        spark.birthLocation = .surface
        spark.spreadingAngle = 70
        spark.particleVelocity = 0.18
        spark.acceleration = SCNVector3(0, 0.22, 0)
        spark.blendMode = .additive
        spark.loops = true
        spark.isLightingEnabled = false
        chestRoot.addParticleSystem(spark)
        sparkles = spark
    }

    // MARK: - Look

    private func paintRarity(_ rarity: LuckyBoxRarity) {
        let crystal = UIColor(rarity.enamel)
        let arena = UIColor(rarity.arenaTint)
        let spark = UIColor(rarity.particleSecondary)
        let glow = max(0.16, min(0.5, CGFloat(rarity.glowStrength)))
        let emit = glowColor(crystal, amount: 0.18 + CGFloat(rarity.glowStrength) * 0.28)

        bodyMaterial.diffuse.contents = Self.woodImage
        bodyMaterial.multiply.contents = UIColor.white
        bodyMaterial.emission.contents = UIColor.black
        barrelMaterial.diffuse.contents = Self.crystalImage
        barrelMaterial.multiply.contents = crystal
        barrelMaterial.emission.contents = emit
        panelMaterial.diffuse.contents = crystal
        panelMaterial.multiply.contents = crystal
        panelMaterial.emission.contents = emit
        goldMaterial.diffuse.contents = bronzeTint
        goldMaterial.multiply.contents = bronzeTint
        goldMaterial.emission.contents = UIColor.black
        lockMaterial.diffuse.contents = bronzeDark
        lockMaterial.multiply.contents = bronzeDark
        lockMaterial.emission.contents = UIColor.black

        let diamond = Self.diamondImage(for: rarity)
        floorMaterial.diffuse.contents = Self.diamondTile(for: rarity)
        rarityGlowMaterial.diffuse.contents = Self.blobImage
        rarityGlowMaterial.multiply.contents = crystal
        interiorMaterial.diffuse.contents = Self.blobImage
        interiorMaterial.multiply.contents = crystal
        rarityGlowNode.opacity = glow
        glowMaterial.diffuse.contents = Self.shadowImage
        scnScene.fogColor = arena.withAlphaComponent(1)
        scnScene.background.contents = diamond
        fillLightNode.light?.color = crystal
        rimLightNode.light?.color = bronzeTint
        innerLightNode.light?.color = crystal
        innerLightNode.light?.intensity = innerGlowIntensity(for: rarity)

        atmosphere?.particleColor = spark.withAlphaComponent(0.36)
        sparkles?.particleColor = crystal.withAlphaComponent(0.8)
        restoreParticles()
    }

    private func innerGlowIntensity(for rarity: LuckyBoxRarity) -> CGFloat {
        40 + CGFloat(rarity.glowStrength) * 90
    }

    private func glowColor(_ color: UIColor, amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(
            red: min(1, r * amount),
            green: min(1, g * amount),
            blue: min(1, b * amount),
            alpha: 1
        )
    }

    private func boostParticles(_ upgraded: Bool) {
        atmosphere?.birthRate = upgraded ? 16 : 10
        sparkles?.birthRate = upgraded ? 12 : 7
    }

    private func restoreParticles() {
        atmosphere?.birthRate = 7
        sparkles?.birthRate = 0
    }

    private func spawnBurst(count: Int, speed: Float) {
        let burst = SCNParticleSystem()
        burst.particleImage = Self.blobImage
        burst.birthRate = CGFloat(count * 8)
        burst.emissionDuration = 0.1
        burst.loops = false
        burst.particleLifeSpan = 0.55
        burst.particleLifeSpanVariation = 0.15
        burst.particleSize = 0.05
        burst.particleSizeVariation = 0.02
        burst.particleColor = UIColor(currentRarity.enamel).withAlphaComponent(0.9)
        burst.spreadingAngle = 160
        burst.particleVelocity = CGFloat(speed)
        burst.particleVelocityVariation = CGFloat(speed) * 0.35
        burst.acceleration = SCNVector3(0, -0.5, 0)
        burst.blendMode = .additive
        burst.isLightingEnabled = false
        chestRoot.addParticleSystem(burst)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak chestRoot] in
            chestRoot?.removeParticleSystem(burst)
        }
    }

    // MARK: - Idle / pose

    func resumeIdleIfNeeded() {
        guard !isRevealed, !isUserRotating else { return }
        // Po pause SceneKit často nechá akce viset, ale neběží. Během hit/open je nenasazuj.
        let playingSequence = !chestRoot.actionKeys.isEmpty || lidPivot.hasActions
        if playingSequence && !idleRunning { return }
        stageRoot.removeAction(forKey: "idleBob")
        spinNode.removeAction(forKey: "idleTurn")
        idleRunning = false
        startIdleIfNeeded()
    }

    private func startIdleIfNeeded() {
        guard !isRevealed, !isUserRotating else { return }
        if stageRoot.action(forKey: "idleBob") == nil {
            let bob = SCNAction.sequence([
                SCNAction.moveBy(x: 0, y: 0.032, z: 0, duration: 1.7),
                SCNAction.moveBy(x: 0, y: -0.032, z: 0, duration: 1.7)
            ])
            bob.timingMode = .easeInEaseOut
            stageRoot.runAction(.repeatForever(bob), forKey: "idleBob")
        }
        if spinNode.action(forKey: "idleTurn") == nil {
            let turn = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 16)
            spinNode.runAction(.repeatForever(turn), forKey: "idleTurn")
        }
        idleRunning = true
    }

    private func stopIdle() {
        idleRunning = false
        stageRoot.removeAction(forKey: "idleBob")
        spinNode.removeAction(forKey: "idleTurn")
        stageRoot.position = SCNVector3(0, restY, 0)
    }

    private func resetPose(keepOrbit: Bool) {
        stageRoot.position = SCNVector3(0, restY, 0)
        spinNode.eulerAngles = SCNVector3Zero
        chestRoot.scale = SCNVector3(displayScale, displayScale, displayScale)
        chestRoot.eulerAngles = SCNVector3Zero
        chestRoot.opacity = 1
        if !keepOrbit {
            userYaw = 0.08
            userPitch = -0.16
        }
        applyOrbit()
    }

    private func applyOrbit() {
        orbitNode.eulerAngles = SCNVector3(userPitch, userYaw, 0)
    }

    // MARK: - Helpers

    private func box(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, chamfer: CGFloat, material: SCNMaterial) -> SCNNode {
        let geo = SCNBox(width: w, height: h, length: l, chamferRadius: chamfer)
        geo.chamferSegmentCount = 6
        geo.firstMaterial = material
        return SCNNode(geometry: geo)
    }

    private func woodMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = Self.woodImage
        m.multiply.contents = UIColor.white
        m.emission.contents = UIColor.black
        m.locksAmbientWithDiffuse = true
        m.writesToDepthBuffer = true
        return m
    }

    private func crystalMaterial(_ color: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .phong
        m.diffuse.contents = Self.crystalImage
        m.multiply.contents = color
        m.specular.contents = UIColor(white: 0.85, alpha: 1)
        m.shininess = 0.7
        m.emission.contents = glowColor(color, amount: 0.22)
        m.locksAmbientWithDiffuse = true
        m.writesToDepthBuffer = true
        return m
    }

    private func metalMaterial(_ color: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .phong
        m.diffuse.contents = color
        m.specular.contents = UIColor(red: 1, green: 0.84, blue: 0.48, alpha: 1)
        m.shininess = 1.15
        m.emission.contents = UIColor.black
        m.locksAmbientWithDiffuse = true
        m.blendMode = .alpha
        m.writesToDepthBuffer = true
        return m
    }

    private func unlitMaterial(_ color: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        m.emission.contents = UIColor.black
        return m
    }

    static let arenaImage: UIImage = diamondImage(for: .common)
    private static let woodImage: UIImage = makeWoodImage()
    private static let crystalImage: UIImage = makeCrystalImage()
    private static let shadowImage: UIImage = makeShadowImage()

    private static let diamondBackdrops: [LuckyBoxRarity: UIImage] = {
        var map: [LuckyBoxRarity: UIImage] = [:]
        for rarity in LuckyBoxRarity.allCases {
            map[rarity] = makeDiamondImage(
                base: UIColor(rarity.arenaTint),
                size: CGSize(width: 512, height: 912),
                half: 28
            )
        }
        return map
    }()

    private static let diamondTiles: [LuckyBoxRarity: UIImage] = {
        var map: [LuckyBoxRarity: UIImage] = [:]
        for rarity in LuckyBoxRarity.allCases {
            map[rarity] = makeDiamondImage(
                base: UIColor(rarity.arenaTint),
                size: CGSize(width: 256, height: 256),
                half: 16
            )
        }
        return map
    }()

    static func diamondImage(for rarity: LuckyBoxRarity) -> UIImage {
        diamondBackdrops[rarity] ?? diamondBackdrops[.common]!
    }

    static func diamondTile(for rarity: LuckyBoxRarity) -> UIImage {
        diamondTiles[rarity] ?? diamondTiles[.common]!
    }

    private static let blobImage: UIImage = {
        makeBlobImage()
    }()

    private static func makeDiamondImage(base: UIColor, size: CGSize, half: CGFloat) -> UIImage {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        base.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let light = UIColor(red: min(1, red * 1.22), green: min(1, green * 1.20), blue: min(1, blue * 1.16), alpha: 1)
        let dark = UIColor(red: red * 0.72, green: green * 0.74, blue: blue * 0.78, alpha: 1)
        let grout = UIColor(red: red * 0.46, green: green * 0.48, blue: blue * 0.54, alpha: 1)
        let highlight = UIColor(red: min(1, red * 1.55), green: min(1, green * 1.48), blue: min(1, blue * 1.38), alpha: 0.55)
        let shade = UIColor(red: red * 0.32, green: green * 0.34, blue: blue * 0.40, alpha: 0.75)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            grout.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let xStep = half * 2
            let yStep = half
            var row = -2
            while CGFloat(row) * yStep < size.height + half * 2 {
                var col = -2
                while CGFloat(col) * xStep < size.width + xStep {
                    let cx = CGFloat(col) * xStep + ((row & 1) == 0 ? 0 : half)
                    let cy = CGFloat(row) * yStep
                    let fill = ((row + col) & 1) == 0 ? light : dark
                    drawDiamond(
                        at: CGPoint(x: cx, y: cy),
                        half: half,
                        fill: fill,
                        highlight: highlight,
                        shade: shade
                    )
                    col += 1
                }
                row += 1
            }
        }
    }

    private static func drawDiamond(
        at center: CGPoint,
        half: CGFloat,
        fill: UIColor,
        highlight: UIColor,
        shade: UIColor
    ) {
        let top = CGPoint(x: center.x, y: center.y - half)
        let right = CGPoint(x: center.x + half, y: center.y)
        let bottom = CGPoint(x: center.x, y: center.y + half)
        let left = CGPoint(x: center.x - half, y: center.y)

        let path = UIBezierPath()
        path.move(to: top)
        path.addLine(to: right)
        path.addLine(to: bottom)
        path.addLine(to: left)
        path.close()
        fill.setFill()
        path.fill()

        let hi = UIBezierPath()
        hi.move(to: left)
        hi.addLine(to: top)
        hi.addLine(to: right)
        highlight.setStroke()
        hi.lineWidth = max(1.2, half * 0.08)
        hi.lineJoinStyle = .miter
        hi.stroke()

        let sh = UIBezierPath()
        sh.move(to: right)
        sh.addLine(to: bottom)
        sh.addLine(to: left)
        shade.setStroke()
        sh.lineWidth = max(1.2, half * 0.08)
        sh.lineJoinStyle = .miter
        sh.stroke()
    }

    private static func makeWoodImage() -> UIImage {
        let size = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let plankH: CGFloat = 42
            let tones: [(CGFloat, CGFloat, CGFloat)] = [
                (0.62, 0.38, 0.18),
                (0.55, 0.32, 0.14),
                (0.68, 0.42, 0.20),
                (0.50, 0.28, 0.12),
                (0.60, 0.36, 0.16),
                (0.58, 0.34, 0.15)
            ]
            for i in 0..<6 {
                let y = CGFloat(i) * plankH
                let t = tones[i % tones.count]
                UIColor(red: t.0, green: t.1, blue: t.2, alpha: 1).setFill()
                ctx.fill(CGRect(x: 0, y: y, width: size.width, height: plankH - 3))
                UIColor(red: 0.28, green: 0.14, blue: 0.06, alpha: 0.7).setFill()
                ctx.fill(CGRect(x: 0, y: y + plankH - 3, width: size.width, height: 3))
                cg.setStrokeColor(UIColor(red: t.0 * 0.7, green: t.1 * 0.65, blue: t.2 * 0.55, alpha: 0.45).cgColor)
                cg.setLineWidth(1)
                var x: CGFloat = CGFloat((i * 29) % 24)
                while x < size.width {
                    cg.move(to: CGPoint(x: x, y: y + 4))
                    cg.addQuadCurve(
                        to: CGPoint(x: x + 26, y: y + plankH - 6),
                        control: CGPoint(x: x + 10, y: y + plankH * 0.5)
                    )
                    cg.strokePath()
                    x += 28
                }
            }
        }
    }

    private static func makeCrystalImage() -> UIImage {
        let size = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            UIColor(white: 0.34, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            if let glow = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(white: 0.88, alpha: 1).cgColor,
                    UIColor(white: 0.28, alpha: 1).cgColor
                ] as CFArray,
                locations: [0, 1]
            ) {
                cg.drawRadialGradient(
                    glow,
                    startCenter: CGPoint(x: 108, y: 86),
                    startRadius: 6,
                    endCenter: CGPoint(x: 128, y: 128),
                    endRadius: 180,
                    options: []
                )
            }

            let shards: [(CGPoint, CGPoint, CGPoint, CGFloat)] = [
                (CGPoint(x: 18, y: 40), CGPoint(x: 90, y: 22), CGPoint(x: 70, y: 95), 0.22),
                (CGPoint(x: 110, y: 8), CGPoint(x: 190, y: 40), CGPoint(x: 140, y: 88), 0.18),
                (CGPoint(x: 160, y: 70), CGPoint(x: 250, y: 50), CGPoint(x: 230, y: 140), 0.16),
                (CGPoint(x: 20, y: 130), CGPoint(x: 80, y: 100), CGPoint(x: 95, y: 190), 0.14),
                (CGPoint(x: 120, y: 120), CGPoint(x: 200, y: 150), CGPoint(x: 150, y: 230), 0.17),
                (CGPoint(x: 8, y: 200), CGPoint(x: 70, y: 230), CGPoint(x: 30, y: 250), 0.12),
                (CGPoint(x: 180, y: 180), CGPoint(x: 250, y: 210), CGPoint(x: 210, y: 255), 0.13)
            ]
            for shard in shards {
                cg.setFillColor(UIColor(white: 0.72, alpha: shard.3).cgColor)
                cg.move(to: shard.0)
                cg.addLine(to: shard.1)
                cg.addLine(to: shard.2)
                cg.closePath()
                cg.fillPath()
            }

            cg.setStrokeColor(UIColor(white: 0.95, alpha: 0.78).cgColor)
            cg.setLineWidth(1.7)
            let cracks: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (20, 30, 90, 80, 140, 40),
                (40, 200, 110, 150, 200, 210),
                (8, 120, 80, 110, 170, 160),
                (180, 20, 200, 90, 240, 70),
                (60, 60, 130, 120, 90, 190),
                (150, 180, 190, 130, 250, 190),
                (30, 70, 70, 140, 40, 180),
                (210, 100, 180, 160, 240, 200)
            ]
            for crack in cracks {
                cg.move(to: CGPoint(x: crack.0, y: crack.1))
                cg.addLine(to: CGPoint(x: crack.2, y: crack.3))
                cg.addLine(to: CGPoint(x: crack.4, y: crack.5))
                cg.strokePath()
            }
            cg.setStrokeColor(UIColor(white: 0.12, alpha: 0.5).cgColor)
            cg.setLineWidth(2.4)
            for crack in cracks.prefix(4) {
                cg.move(to: CGPoint(x: crack.0 + 4, y: crack.1 + 3))
                cg.addLine(to: CGPoint(x: crack.2 + 3, y: crack.3 + 2))
                cg.strokePath()
            }
        }
    }

    private static func makeShadowImage() -> UIImage {
        let size = CGSize(width: 128, height: 128)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let colors = [
                UIColor.black.withAlphaComponent(0.7).cgColor,
                UIColor.black.withAlphaComponent(0).cgColor
            ] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return }
            ctx.cgContext.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: 64, y: 64),
                startRadius: 0,
                endCenter: CGPoint(x: 64, y: 64),
                endRadius: 62,
                options: []
            )
        }
    }

    private static func makeBlobImage() -> UIImage {
        let size = CGSize(width: 64, height: 64)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return }
            ctx.cgContext.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: 32, y: 32),
                startRadius: 0,
                endCenter: CGPoint(x: 32, y: 32),
                endRadius: 32,
                options: []
            )
        }
    }

    private func squash(mulX x: CGFloat, y: CGFloat, z: CGFloat, duration: TimeInterval) -> SCNAction {
        let start = chestRoot.scale
        let target = SCNVector3(
            displayScale * Float(x),
            displayScale * Float(y),
            displayScale * Float(z)
        )
        return SCNAction.customAction(duration: duration) { node, elapsed in
            let t = CGFloat(max(0, min(1, elapsed / CGFloat(duration))))
            let eased = t * t * (3 - 2 * t)
            node.scale = SCNVector3(
                start.x + (target.x - start.x) * Float(eased),
                start.y + (target.y - start.y) * Float(eased),
                start.z + (target.z - start.z) * Float(eased)
            )
        }
    }

    private func runAsync(_ action: SCNAction, on node: SCNNode) async {
        await withCheckedContinuation { continuation in
            node.runAction(action, completionHandler: {
                continuation.resume()
            })
        }
    }
}
