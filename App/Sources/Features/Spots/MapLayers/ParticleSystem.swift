import SwiftUI

/// 風・流れ・波を流す粒子（F-43）。箱の正規化座標で動かし、描くときだけ画面の長方形に写す。
/// 各粒子は直近の位置を数点持ち、薄くなる線で尾を描く
final class ParticleSystem {
    struct Particle {
        var x: Double, y: Double
        var age: Int, life: Int
        var speed: Double
        var trail: [(Double, Double)]
    }

    private(set) var particles: [Particle] = []
    private var boxKey: GeoBox?
    private var lastTick: Date?
    let count: Int
    let trailLength = 7

    init(count: Int = 800) { self.count = count }

    private func reseed() {
        particles = (0..<count).map { _ in Self.spawn() }
    }

    private static func spawn() -> Particle {
        Particle(x: .random(in: 0...1), y: .random(in: 0...1), age: Int.random(in: 0..<60), life: Int.random(in: 70...160), speed: 0, trail: [])
    }

    /// 1 フレーム進める。箱が変わったら撒き直す
    func step(raster: FieldRaster, now: Date) {
        if boxKey != raster.box { boxKey = raster.box; reseed() }
        if particles.isEmpty { reseed() }
        let dt = min(0.05, lastTick.map { now.timeIntervalSince($0) } ?? (1.0 / 30))
        lastTick = now
        let scale = raster.layer.particleScale
        let w = max(1, raster.box.widthMeters), h = max(1, raster.box.heightMeters)
        for i in particles.indices {
            var p = particles[i]
            p.age += 1
            if p.age > p.life || p.x < 0 || p.x > 1 || p.y < 0 || p.y > 1 {
                particles[i] = Self.spawn(); particles[i].age = 0; continue
            }
            guard let vel = raster.velocity(x: p.x, y: p.y) else { particles[i] = Self.spawn(); continue }
            p.trail.append((p.x, p.y))
            if p.trail.count > trailLength { p.trail.removeFirst() }
            p.x += vel.u * scale * dt / w
            p.y += vel.v * scale * dt / h
            p.speed = (vel.u * vel.u + vel.v * vel.v).squareRoot()
            particles[i] = p
        }
    }

    /// 尾を描く。速いほど白く太く
    func draw(in ctx: inout GraphicsContext, rect: CGRect, layer: MapLayer) {
        let maxSpeed = layer.range.upperBound
        for p in particles where p.trail.count >= 2 {
            var path = Path()
            for (k, t) in p.trail.enumerated() {
                let pt = CGPoint(x: rect.minX + t.0 * rect.width, y: rect.maxY - t.1 * rect.height)
                if k == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            let last = CGPoint(x: rect.minX + p.x * rect.width, y: rect.maxY - p.y * rect.height)
            path.addLine(to: last)
            let s = min(1, p.speed / maxSpeed)
            let fade = p.age < 10 ? Double(p.age) / 10 : (p.age > p.life - 15 ? Double(p.life - p.age) / 15 : 1)
            ctx.stroke(path, with: .color(Color.white.opacity((0.25 + 0.5 * s) * fade)), style: StrokeStyle(lineWidth: 0.8 + 1.0 * s, lineCap: .round, lineJoin: .round))
        }
    }
}
