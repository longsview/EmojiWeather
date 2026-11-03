import CoreMotion
import SwiftUI
#if os(watchOS)
import WatchKit
#else
import UIKit
#endif

/// The full-screen animated emoji scene that sits behind the weather.
struct EmojiSceneView: View {
    var conditions: SceneConditions
    /// Pauses the animation, e.g. for city pages that are off screen.
    var paused = false
    /// Scenes are tuned for a phone-sized screen. On a smaller screen (the watch), the scene is
    /// simulated at phone size and drawn shrunk by this factor so it looks the same, just smaller.
    var canvasScale: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    /// Settings > Animated scenes. Off shows a still picture of the scene.
    @AppStorage(DisplaySettings.animateScenesKey, store: SharedStore.defaults) private var animateScenes = true
    @State private var system: EmojiParticleSystem
    @State private var tilt = MotionTilt()

    init(conditions: SceneConditions, paused: Bool = false, canvasScale: Double = 1) {
        self.conditions = conditions
        self.paused = paused
        self.canvasScale = canvasScale
        _system = State(initialValue: EmojiParticleSystem(conditions: conditions))
    }

    var body: some View {
        // 60 fps normally, 30 fps in Low Power Mode and on the watch, paused in the background.
        #if os(watchOS)
        let interval: Double? = 1.0 / 30
        #else
        let interval: Double? = ProcessInfo.processInfo.isLowPowerModeEnabled ? 1.0 / 30 : nil
        #endif
        TimelineView(.animation(minimumInterval: interval, paused: paused || !animateScenes || scenePhase != .active)) { timeline in
            Canvas { context, size in
                let scale = max(canvasScale, 0.1)
                let virtualSize = CGSize(width: size.width / scale, height: size.height / scale)
                context.scaleBy(x: scale, y: scale)
                system.update(
                    now: timeline.date.timeIntervalSinceReferenceDate,
                    size: virtualSize,
                    tilt: tilt.x
                )
                system.draw(in: &context, size: virtualSize)
            }
        }
        .accessibilityHidden(true)
        .onAppear {
            system.reduceMotion = reduceMotion
            system.onStrike = {
                Task { @MainActor in
                    #if os(watchOS)
                    WKInterfaceDevice.current().play(.directionDown)
                    #else
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 0.8)
                    #endif
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
                        .foregroundStyle(.black)
                        .padding(.bottom, 60)
                }
        }
    }
    .tabViewStyle(.page)
    .ignoresSafeArea()
}
