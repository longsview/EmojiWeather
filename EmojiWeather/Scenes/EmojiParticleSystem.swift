import SwiftUI
import UIKit

/// Simulates and draws an emoji scene. Owned by `EmojiSceneView` and driven by its `TimelineView`,
/// so it's a plain class: changing particles must not trigger SwiftUI view updates.
final class EmojiParticleSystem {
    private struct Particle {
        var emitter: Int
        var emoji: String
        var position: CGPoint
        var velocity: CGVector
        var size: Double
        var lifetime: Double
        var age: Double = 0
        var rotation: Double = 0
        var spin: Double = 0
        var wobble: Double = 0
        var wobblePhase: Double = 0
        var opacity: Double = 1
        var fades = false
        var gravity: Double = 0
        var landedAge: Double?
        var isSplash = false
    }

    private struct Bolt {
        var points: [CGPoint]
        var age: Double = 0
    }

    /// Emoji are rendered to images once at this size and scaled when drawn.
    private static var baseSize: Double { EmojiImageCache.pointSize }
    private static let boltDuration: Double = 0.45

    private(set) var spec: SceneSpec
    private var intensity: Double
    private var sky: SkyMode
    var reduceMotion = false
    /// Called on each lightning strike, for a haptic.
    var onStrike: (() -> Void)?

    private var particles: [Particle] = []
    private var emitCredit: [Double] = []
    private var lastTime: TimeInterval?
    private var elapsed: Double = 0
    private var nextStrike: Double = 0
    private var flash: Double = 0
    private var bolt: Bolt?

    init(conditions: SceneConditions) {
        spec = SceneSpec.make(for: conditions)
        intensity = conditions.intensity
        sky = conditions.sky
        reset()
    }

    func configure(_ conditions: SceneConditions) {
        spec = SceneSpec.make(for: conditions)
        intensity = conditions.intensity
        sky = conditions.sky
        reset()
    }

    private func reset() {
        particles.removeAll(keepingCapacity: true)
        emitCredit = Array(repeating: 0, count: spec.emitters.count)
        lastTime = nil
        elapsed = 0
        flash = 0
        bolt = nil
        nextStrike = spec.lightningInterval.map { Double.random(in: 1.5...$0.lowerBound) } ?? .infinity
    }

    // MARK: - Simulation

    /// Advances the scene to `now`. `tilt` is -1...1 from the phone's tilt.
    func update(now: TimeInterval, size: CGSize, tilt: Double) {
        guard size.width > 0, size.height > 0 else { return }
        guard let lastTime else {
            // First frame: simulate ahead so slow scenes don't start empty.
            let step = 1.0 / 20
            var simulated = 0.0
            while simulated < spec.prewarm {
                self.step(dt: step, size: size, tilt: tilt, allowLightning: false)
                simulated += step
            }
            self.lastTime = now
            return
        }
        // Clamp so a long pause (app in the background) doesn't fast-forward.
        let dt = min(max(now - lastTime, 0), 1.0 / 15)
        self.lastTime = now
        step(dt: dt, size: size, tilt: tilt, allowLightning: true)
    }

    private func step(dt: Double, size: CGSize, tilt: Double, allowLightning: Bool) {
        elapsed += dt
        // Wide landscape canvases (iPhone Duo open, iPad sideways) cover far more sky than a
        // portrait phone, so they get proportionally more rain, snow and wind, up to double.
        let widthScale = size.width > size.height * 1.2 ? min(2, max(1, size.width / 500)) : 1
        let rateScale = (reduceMotion ? 0.25 : 1) * widthScale
        let speedScale = reduceMotion ? 0.35 : 1
        let maxParticles = Int(Double(spec.maxParticles) * widthScale)

        // Emit new particles.
        for (index, emitter) in spec.emitters.enumerated() {
            let intensityScale = emitter.followsIntensity ? intensity : 1
            emitCredit[index] += emitter.rate * intensityScale * rateScale * dt
            while emitCredit[index] >= 1 {
                emitCredit[index] -= 1
                if particles.count < maxParticles {
                    particles.append(spawn(emitter, index: index, size: size, tilt: tilt, speedScale: speedScale))
                }
            }
        }

        // Move particles and handle landings.
        var splashes: [Particle] = []
        let floor = size.height
        for index in particles.indices {
            particles[index].age += dt
            if particles[index].landedAge != nil { continue }

            particles[index].velocity.dy += particles[index].gravity * dt
            particles[index].position.x += particles[index].velocity.dx * dt
            particles[index].position.y += particles[index].velocity.dy * dt
            particles[index].rotation += particles[index].spin * dt

            let particle = particles[index]
            guard !particle.isSplash, particle.velocity.dy > 0,
                  particle.position.y >= floor - particle.size * 0.3 else { continue }

            switch spec.emitters[particle.emitter].landing {
            case .none:
                break
            case .splash:
                splashes.append(contentsOf: makeSplash(from: particle, floor: floor))
                particles[index].age = particle.lifetime
            case .settle:
                particles[index].landedAge = particle.age
                particles[index].position.y = floor - particle.size * 0.35
                particles[index].velocity = .zero
                particles[index].spin = 0
            }
        }

        let width = size.width
        particles.removeAll { particle in
            if particle.age >= particle.lifetime { return true }
            if let landed = particle.landedAge, particle.age - landed > 4 { return true }
            let margin = particle.size * 2 + 40
            return particle.position.x < -margin - 200
                || particle.position.x > width + margin + 200
                || particle.position.y > floor + margin
                || particle.position.y < -margin - 300
        }
        if particles.count + splashes.count <= spec.maxParticles + 60 {
            particles.append(contentsOf: splashes)
        }

        updateLightning(dt: dt, size: size, allowLightning: allowLightning)
    }

    private func spawn(_ emitter: EmitterSpec, index: Int, size: CGSize, tilt: Double, speedScale: Double) -> Particle {
        let fontSize = Double.random(in: emitter.size)
        let jitter = emitter.angleJitter > 0 ? Double.random(in: -emitter.angleJitter...emitter.angleJitter) : 0
        // Tilting the phone right pulls the stream toward the right (a smaller angle).
        let baseAngle: Double
        if let rays = emitter.rays, let ray = rays.randomElement() {
            baseAngle = ray + elapsed * emitter.rayRotation
        } else {
            baseAngle = emitter.angle
        }
        let degrees = baseAngle + jitter - tilt * emitter.tiltResponse
        let radians = degrees * .pi / 180
        let speed = Double.random(in: emitter.speed) * speedScale

        let width = size.width
        let height = size.height
        let bandY = Double.random(in: emitter.band) * height
        let position: CGPoint
        switch emitter.origin {
        case .top:
            let startY = emitter.band.lowerBound * height
            position = CGPoint(x: Double.random(in: emitter.xRange) * width, y: startY - fontSize)
        case .point(let point):
            position = CGPoint(
                x: point.x * width + cos(radians) * emitter.spawnRadius,
                y: point.y * height + sin(radians) * emitter.spawnRadius
            )
        case .left:
            position = CGPoint(x: -fontSize * 1.5, y: bandY)
        case .scattered:
            position = CGPoint(x: Double.random(in: 0.03...0.97) * width, y: bandY)
        case .bottom:
            position = CGPoint(x: Double.random(in: 0...1) * width, y: height + fontSize)
        }

        return Particle(
            emitter: index,
            emoji: emitter.emoji.randomElement() ?? "❓",
            position: position,
            velocity: CGVector(dx: cos(radians) * speed, dy: sin(radians) * speed),
            size: fontSize,
            lifetime: Double.random(in: emitter.lifetime),
            rotation: emitter.spin == 0...0 ? 0 : Double.random(in: -30...30),
            spin: Double.random(in: emitter.spin),
            wobble: emitter.wobble,
            wobblePhase: Double.random(in: 0...(2 * .pi)),
            opacity: Double.random(in: emitter.opacity),
            fades: emitter.fades,
            gravity: emitter.gravity
        )
    }

    private func makeSplash(from particle: Particle, floor: Double) -> [Particle] {
        guard !reduceMotion else { return [] }
        return (0..<Int.random(in: 2...3)).map { _ in
            let angle = Double.random(in: -150 ... -30) * .pi / 180
            let speed = Double.random(in: 60...140)
            return Particle(
                emitter: particle.emitter,
                emoji: particle.emoji,
                position: CGPoint(x: particle.position.x, y: floor - 4),
                velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                size: particle.size * 0.4,
                lifetime: 0.45,
                opacity: particle.opacity,
                fades: true,
                gravity: 700,
                isSplash: true
            )
        }
    }

    private func updateLightning(dt: Double, size: CGSize, allowLightning: Bool) {
        flash = max(0, flash - dt * 4)
        if var current = bolt {
            current.age += dt
            bolt = current.age < Self.boltDuration ? current : nil
        }

        guard allowLightning, let interval = spec.lightningInterval, elapsed >= nextStrike else { return }
        nextStrike = elapsed + Double.random(in: interval)

        // A zig-zag chain of ⚡️ from under the storm clouds down toward the middle of the screen.
        var x = Double.random(in: 0.25...0.75) * size.width
        var y = size.height * spec.lightningStart
        var points = [CGPoint(x: x, y: y)]
        let segments = Int.random(in: 7...10)
        for _ in 0..<segments {
            y += size.height * 0.04
            x += Double.random(in: -30...30)
            points.append(CGPoint(x: x, y: y))
        }
        bolt = Bolt(points: points)
        if !reduceMotion {
            flash = 1
        }
        onStrike?()
    }

    // MARK: - Drawing

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size)
        context.fill(
            Path(bounds),
            with: .linearGradient(
                Gradient(colors: spec.background),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )

        // A quick shake while the lightning flash is bright.
        var shaken = context
        if flash > 0.3 {
            shaken.translateBy(x: Double.random(in: -5...5) * flash, y: Double.random(in: -5...5) * flash)
        }
        let base = shaken
        // Each emoji is a cached bitmap; drawing an image is far cheaper than laying out text
        // for every particle on every frame.
        var resolved: [String: GraphicsContext.ResolvedImage] = [:]
        func text(_ emoji: String) -> GraphicsContext.ResolvedImage {
            if let cached = resolved[emoji] { return cached }
            let new = base.resolve(Image(uiImage: EmojiImageCache.image(for: emoji)))
            resolved[emoji] = new
            return new
        }

        for particle in particles {
            var opacity = particle.opacity
            if particle.fades {
                opacity *= min(1, particle.age / 0.4) * min(1, (particle.lifetime - particle.age) / 0.6)
            }
            if let landed = particle.landedAge {
                opacity *= max(0, 1 - (particle.age - landed) / 4)
            }
            guard opacity > 0.01 else { continue }

            var x = particle.position.x
            if particle.wobble > 0 {
                x += sin(particle.age * 1.6 + particle.wobblePhase) * particle.wobble
            }
            draw(text(particle.emoji), in: base, at: CGPoint(x: x, y: particle.position.y),
                 size: particle.size, rotation: particle.rotation, opacity: opacity)
        }

        for hero in spec.heroes {
            let phase = hero.phase * .pi / 180
            let orbitAngle = (hero.phase + hero.orbitSpeed * elapsed) * .pi / 180
            let scale = 1 + sin(elapsed * 1.8 + phase) * hero.pulse
            let point = CGPoint(
                x: hero.position.x * size.width + hero.offset.width + cos(orbitAngle) * hero.orbitRadius,
                y: hero.position.y * size.height + hero.offset.height + sin(orbitAngle) * hero.orbitRadius
                    + sin(elapsed * 1.3 + phase) * hero.bob
            )
            draw(text(hero.emoji), in: base, at: point,
                 size: hero.size * scale, rotation: elapsed * hero.spin, opacity: hero.opacity)
        }

        if let bolt {
            let opacity = 1 - bolt.age / Self.boltDuration
            for point in bolt.points {
                draw(text("⚡️"), in: base, at: point, size: 40, rotation: 0, opacity: opacity)
            }
        }

        if flash > 0 {
            // On a white day sky a white flash is invisible, so flash a pale lightning yellow there.
            // On the dark night sky yellow turns muddy olive, so flash a cool pale blue-white instead.
            let color = sky == .night ? Color(hex: 0xDCE8FF) : Color(hex: 0xFFE45C)
            context.fill(Path(bounds), with: .color(color.opacity(flash * (sky == .night ? 0.35 : 0.45))))
        }
    }

    private func draw(_ text: GraphicsContext.ResolvedImage, in context: GraphicsContext,
                      at point: CGPoint, size: Double, rotation: Double, opacity: Double) {
        var layer = context
        layer.opacity = opacity
        layer.translateBy(x: point.x, y: point.y)
        if rotation != 0 {
            layer.rotate(by: .degrees(rotation))
        }
        let scale = size / Self.baseSize
        layer.scaleBy(x: scale, y: scale)
        layer.draw(text, at: .zero, anchor: .center)
    }
}

/// Renders each emoji to a bitmap once and keeps it for the life of the app.
enum EmojiImageCache {
    static let pointSize: Double = 96
    private static var images: [String: UIImage] = [:]

    static func image(for emoji: String) -> UIImage {
        if let cached = images[emoji] { return cached }
        let image: UIImage
        if case .genmoji(let id) = SceneEmoji(emoji) {
            // A Genmoji saved as a picture. Until the file is there (the watch may still be
            // receiving it from the phone), draw a sparkle and try again next time.
            guard let picture = GenmojiStore.image(for: id) else { return Self.image(for: "✨") }
            image = fitted(picture)
        } else {
            image = render(emoji)
        }
        images[emoji] = image
        return image
    }

    /// The canvas an emoji glyph renders into, so pictures line up with emoji of the same size.
    private static var glyphSize: CGSize {
        if let size = cachedGlyphSize { return size }
        let image = render("☀️")
        let size = image.size == .zero ? CGSize(width: pointSize, height: pointSize * 1.2) : image.size
        cachedGlyphSize = size
        return size
    }
    private static var cachedGlyphSize: CGSize?

    /// Scales a Genmoji picture to fill the same box an emoji would, keeping its shape.
    private static func fitted(_ picture: UIImage) -> UIImage {
        let canvas = glyphSize
        #if os(watchOS)
        let side = min(canvas.width, canvas.height) * 0.98
        return MainActor.assumeIsolated {
            let renderer = ImageRenderer(content:
                Image(uiImage: picture)
                    .resizable()
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .frame(width: canvas.width, height: canvas.height)
            )
            renderer.scale = 2
            guard let cgImage = renderer.cgImage else { return picture }
            return UIImage(cgImage: cgImage, scale: 2, orientation: .up)
        }
        #else
        let side = min(canvas.width, canvas.height) * 0.98
        let scale = min(side / max(picture.size.width, 1), side / max(picture.size.height, 1))
        let size = CGSize(width: picture.size.width * scale, height: picture.size.height * scale)
        let origin = CGPoint(x: (canvas.width - size.width) / 2, y: (canvas.height - size.height) / 2)
        return UIGraphicsImageRenderer(size: canvas).image { _ in
            picture.draw(in: CGRect(origin: origin, size: size))
        }
        #endif
    }

    #if os(watchOS)
    // watchOS has no UIGraphicsImageRenderer, so let SwiftUI draw the emoji instead.
    private static func render(_ emoji: String) -> UIImage {
        MainActor.assumeIsolated {
            let renderer = ImageRenderer(content: Text(verbatim: emoji).font(.system(size: pointSize)))
            renderer.scale = 2
            guard let cgImage = renderer.cgImage else { return UIImage() }
            return UIImage(cgImage: cgImage, scale: 2, orientation: .up)
        }
    }
    #else
    private static func render(_ emoji: String) -> UIImage {
        let text = NSAttributedString(
            string: emoji,
            attributes: [.font: UIFont.systemFont(ofSize: pointSize)]
        )
        return UIGraphicsImageRenderer(size: text.size()).image { _ in
            text.draw(at: .zero)
        }
    }
    #endif
}
