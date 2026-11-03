import CoreMotion
import SwiftUI
import UIKit

/// The full-screen animated emoji scene that sits behind the weather.
struct EmojiSceneView: View {
    var conditions: SceneConditions
    /// Pauses the animation, e.g. for city pages that are off screen.
    var paused = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// Settings > Animated scenes. Off shows a still picture of the scene.
    @AppStorage(DisplaySettings.animateScenesKey, store: SharedStore.defaults) private var animateScenes = true
    @State private var system: EmojiParticleSystem
    @State private var tilt = MotionTilt()

    init(conditions: SceneConditions, paused: Bool = false) {
        self.conditions = conditions
        self.paused = paused
        _system = State(initialValue: EmojiParticleSystem(conditions: conditions))
    }

    var body: some View {
        // 60 fps normally, 30 fps in Low Power Mode, paused in the background.
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        TimelineView(.animation(minimumInterval: lowPower ? 1.0 / 30 : nil, paused: paused || !animateScenes || scenePhase != .active)) { timeline in
            Canvas { context, size in
                system.update(
                    now: timeline.date.timeIntervalSinceReferenceDate,
                    size: size,
                    tilt: tilt.x
                )
                // No parallax with Reduce Motion.
                let parallax = reduceMotion ? .zero : CGVector(dx: tilt.parallaxX, dy: tilt.y)
                system.draw(in: &context, size: size, parallax: parallax)
            }
        }
        .accessibilityHidden(true)
        .onAppear {
            system.reduceMotion = reduceMotion
            system.onStrike = {
                Task { @MainActor in
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 0.8)
                }
            }
            if !reduceMotion { tilt.start() }
        }
        .onDisappear { tilt.stop() }
        .onChange(of: conditions) { _, newValue in
            system.configure(newValue)
        }
        .onChange(of: reduceMotion) { _, newValue in
            system.reduceMotion = newValue
            if newValue { tilt.stop() } else { tilt.start() }
        }
    }
}

/// Reads the phone's sideways tilt (-1...1) so rain, snow and clouds lean as you tip the phone.
final class MotionTilt {
    private let manager = CMMotionManager()
    private(set) var x: Double = 0
    /// Sideways tilt for parallax: more sensitive than `x`, so a small tilt is visible.
    var parallaxX: Double { max(-1, min(1, x * 2.5)) }
    /// Forward/back tilt relative to how the phone is usually held, -1...1.
    private(set) var y: Double = 0
    /// The usual holding angle, which slowly follows the hand so only changes register.
    private var restingY: Double?

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            // Smooth it so the scene leans gently instead of jittering.
            let target = max(-1, min(1, gravity.x))
            self.x = self.x * 0.85 + target * 0.15

            let resting = (self.restingY ?? gravity.y) * 0.995 + gravity.y * 0.005
            self.restingY = resting
            let targetY = max(-1, min(1, (gravity.y - resting) * 4))
            self.y = self.y * 0.85 + targetY * 0.15
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        x = 0
        y = 0
        restingY = nil
    }
}

#Preview("All scenes") {
    TabView {
        ForEach(WeatherScene.allCases) { scene in
            EmojiSceneView(conditions: SceneConditions(scene: scene, intensity: 0.8, windDrift: 0.3))
                .ignoresSafeArea()
                .overlay(alignment: .bottom) {
                    Text(scene.title)
                        .font(.title2.bold())
                        .foregroundStyle(.black)
                        .padding(.bottom, 60)
                }
        }
    }
    .tabViewStyle(.page)
    .ignoresSafeArea()
}
