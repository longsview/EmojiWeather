import CoreMotion
import SwiftUI
import UIKit

/// The full-screen animated emoji scene that sits behind the weather.
struct EmojiSceneView: View {
    var conditions: SceneConditions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var system: EmojiParticleSystem
    @State private var tilt = MotionTilt()

    init(conditions: SceneConditions) {
        self.conditions = conditions
        _system = State(initialValue: EmojiParticleSystem(conditions: conditions))
    }

    var body: some View {
        // 60 fps normally, 30 fps in Low Power Mode, paused in the background.
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        TimelineView(.animation(minimumInterval: lowPower ? 1.0 / 30 : nil, paused: scenePhase != .active)) { timeline in
            Canvas { context, size in
                system.update(
                    now: timeline.date.timeIntervalSinceReferenceDate,
                    size: size,
                    tilt: tilt.x
                )
                system.draw(in: &context, size: size)
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

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            // Smooth it so the scene leans gently instead of jittering.
            let target = max(-1, min(1, gravity.x))
            self.x = self.x * 0.85 + target * 0.15
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        x = 0
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
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                        .padding(.bottom, 60)
                }
        }
    }
    .tabViewStyle(.page)
    .ignoresSafeArea()
}
