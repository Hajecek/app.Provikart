//
//  AikaOrbView.swift
//  Provikart
//
//  Koule AIKA – stejný shader, barvy a přechody stavů jako na webu (assets/aika/orb.js).
//

import SwiftUI
import MetalKit

enum AikaOrbState: String {
    case idle, connecting, listening, thinking, speaking
}

/// Paleta stavu – hodnoty 1:1 z webového `PALETTES`.
struct AikaOrbPalette {
    var a: SIMD3<Float>
    var b: SIMD3<Float>
    var c: SIMD3<Float>
    var swirl: Float
    var breath: Float

    static func of(_ state: AikaOrbState) -> AikaOrbPalette {
        switch state {
        case .idle:       .init(a: [0.20, 0.32, 0.95], b: [0.55, 0.30, 0.98], c: [0.35, 0.85, 1.00], swirl: 0.6, breath: 1.0)
        case .connecting: .init(a: [0.25, 0.30, 0.80], b: [0.45, 0.45, 0.95], c: [0.80, 0.85, 1.00], swirl: 1.6, breath: 0.6)
        case .listening:  .init(a: [0.05, 0.55, 0.90], b: [0.10, 0.85, 0.85], c: [0.65, 1.00, 0.95], swirl: 0.9, breath: 0.8)
        case .thinking:   .init(a: [0.40, 0.18, 0.90], b: [0.75, 0.30, 0.95], c: [0.95, 0.70, 1.00], swirl: 2.4, breath: 0.4)
        case .speaking:   .init(a: [0.95, 0.30, 0.55], b: [0.98, 0.55, 0.30], c: [1.00, 0.88, 0.60], swirl: 1.2, breath: 0.5)
        }
    }
}

/// Plynulé přechody barev, hlasitosti a „hodin“ shaderu – stejné konstanty jako web.
final class AikaOrbAnimator {
    private(set) var cur = AikaOrbPalette.of(.idle)
    private(set) var level: Float = 0
    private(set) var clock: Double = 0
    private var last: Date?

    func step(now: Date, state: AikaOrbState, target: Double, reduced: Bool) {
        let dt = min(0.05, last.map { now.timeIntervalSince($0) } ?? 0)
        last = now
        let pal = AikaOrbPalette.of(state)
        let k = Float(1 - exp(-dt * 3.5))
        cur.a += (pal.a - cur.a) * k
        cur.b += (pal.b - cur.b) * k
        cur.c += (pal.c - cur.c) * k
        cur.swirl += (pal.swirl - cur.swirl) * k
        cur.breath += (pal.breath - cur.breath) * k
        let t = Float(max(0, min(1, target)))
        level += (t - level) * (t > level ? 0.35 : 0.08)
        let speed = reduced ? 0.3 : (0.8 + Double(cur.swirl) * 0.35 + Double(level) * 0.8)
        clock += dt * speed
    }
}

struct AikaOrbView: View {
    var state: AikaOrbState = .idle
    /// Hlasitost 0…1 (mikrofon při poslechu, Aika při mluvení).
    var level: Double = 0
    /// Vnější záře (na světlém pozadí, např. v liště, vypnout).
    var glow: Bool = true
    /// Přiblížení: 1 = jako web (koule ~56 % plochy), menší číslo = větší koule.
    var zoom: Float = 1
    /// Rychlost otáčení vzoru (rad/s „hodin“ shaderu), 0 = bez otáčení.
    var spin: Float = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        AikaOrbMetalView(state: state, level: level, reduced: reduceMotion, extra: SIMD4(glow ? 1 : 0, zoom, reduceMotion ? 0 : spin, 0))
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

/// MTKView s koulí – shader se zkompiluje jednou za běh aplikace a sdílí se.
private struct AikaOrbMetalView: UIViewRepresentable {
    let state: AikaOrbState
    let level: Double
    let reduced: Bool
    let extra: SIMD4<Float>

    func makeCoordinator() -> AikaOrbRenderer { AikaOrbRenderer() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: AikaOrbRenderer.shared?.device)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.layer.isOpaque = false
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.isUserInteractionEnabled = false
        // Žádný Metal HUD (počítadlo FPS) nad koulí.
        (view.layer as? CAMetalLayer)?.developerHUDProperties = ["mode": "disabled"]
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.state = state
        context.coordinator.target = level
        context.coordinator.reduced = reduced
        context.coordinator.extra = extra
    }
}

final class AikaOrbRenderer: NSObject, MTKViewDelegate {
    struct Shared {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let pipeline: MTLRenderPipelineState
    }

    static let shared: Shared? = {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        do {
            let library = try device.makeLibrary(source: AikaOrbShader.source, options: nil)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "aika_vertex")
            desc.fragmentFunction = library.makeFunction(name: "aika_fragment")
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            let pipeline = try device.makeRenderPipelineState(descriptor: desc)
            return Shared(device: device, queue: queue, pipeline: pipeline)
        } catch {
            print("[AIKA] Shader koule se nepodařilo zkompilovat: \(error)")
            return nil
        }
    }()

    private struct Uniforms {
        var a: SIMD4<Float>
        var b: SIMD4<Float>
        var c: SIMD4<Float>
        var params: SIMD4<Float>
        var size: SIMD4<Float>
        var extra: SIMD4<Float>
    }

    var state: AikaOrbState = .idle
    var target: Double = 0
    var reduced = false
    var extra = SIMD4<Float>(1, 1, 0, 0)
    private let animator = AikaOrbAnimator()

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let shared = Self.shared,
              let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let buffer = shared.queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        animator.step(now: Date(), state: state, target: target, reduced: reduced)
        let cur = animator.cur
        let size = view.drawableSize
        var u = Uniforms(
            a: SIMD4(cur.a, 0),
            b: SIMD4(cur.b, 0),
            c: SIMD4(cur.c, 0),
            params: SIMD4(Float(animator.clock), reduced ? animator.level * 0.4 : animator.level, cur.swirl, cur.breath),
            size: SIMD4(Float(size.width), Float(size.height), 0, 0),
            extra: extra
        )
        encoder.setRenderPipelineState(shared.pipeline)
        encoder.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

/// Koule AIKA do toolbaru vedle loga – otevře hlasovou asistentku.
struct AikaToolbarButton: View {
    @EnvironmentObject private var authState: AuthState

    var body: some View {
        if authState.currentRole == .manager {
            link
        }
    }

    private var link: some View {
        NavigationLink {
            AikaView()
                .environmentObject(authState)
        } label: {
            // Bez záře (v liště by dělala tmavý čtverec), koule přes celý rámeček, velká jako logo (34 b).
            // Stálá „hlasitost“ 0.35 rozvlní okraj a zrychlí vzor, spin ji viditelně otáčí.
            AikaOrbView(level: 0.35, glow: false, zoom: 0.66, spin: 1.8)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Aika – hlasová asistentka")
    }
}

#Preview {
    VStack(spacing: 40) {
        AikaOrbView().frame(width: 52)
        AikaOrbView(state: .speaking, level: 0.5).frame(width: 300)
    }
    .padding()
    .background(Color.black)
}
