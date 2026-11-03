import AVFoundation
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WeatherKit

/// Everything the share card shows, captured when the share sheet opens.
struct ShareCardContent {
    struct Hour: Hashable {
        let time: String
        let emoji: String
        let temperature: String
    }

    let placeName: String
    let conditions: SceneConditions
    let dateLine: String
    let temperature: String
    let condition: String
    let high: String?
    let low: String?
    let tagline: String
    let hours: [Hour]
    /// The "Skymoji" mark at the bottom. Skymoji+ removes it.
    var showsWatermark: Bool

    init(placeName: String, timeZone: TimeZone, conditions: SceneConditions, forecast: ForecastContent, showsWatermark: Bool) {
        self.placeName = placeName
        self.conditions = conditions
        var now = Date.now
        #if DEBUG
        now = ScreenshotMode.fixedDate ?? now
        #endif
        let day = now.formatted(Date.FormatStyle(timeZone: timeZone).weekday(.abbreviated).month(.abbreviated).day().locale(DisplaySettings.locale))
        dateLine = "\(day) · \(now.formatted(DisplaySettings.timeStyle(timeZone)))"
        temperature = forecast.temperature
        condition = forecast.condition
        high = forecast.high
        low = forecast.low
        tagline = conditions.scene.tagline(in: conditions.sky)
        hours = forecast.hours.prefix(5).map { Hour(time: $0.time, emoji: $0.emoji, temperature: $0.temperature) }
        self.showsWatermark = showsWatermark
    }

    /// A safe file name like "Skymoji-Paris".
    var fileStem: String {
        let cleaned = placeName.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        return cleaned.isEmpty ? "Skymoji" : "Skymoji-\(cleaned)"
    }
}

/// The card's text: drawn over the live scene in the preview and over each rendered frame.
/// Laid out for a 360×640 point card (9:16), rendered at 3x for 1080×1920.
struct ShareCardOverlay: View {
    let content: ShareCardContent

    private var sky: SkyMode { content.conditions.sky }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 250)

            VStack(spacing: 2) {
                Text(verbatim: content.placeName)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(verbatim: content.dateLine)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .opacity(0.75)
                Text(verbatim: content.temperature)
                    .font(.system(size: 96, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.vertical, -8)
                Text(verbatim: content.condition)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                if let high = content.high, let low = content.low {
                    Text(verbatim: "↑\(high)  ↓\(low)")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                Text(verbatim: content.tagline)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .opacity(0.75)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            .shadow(color: sky.haloColor, radius: 8)
            .shadow(color: sky.haloColor, radius: 8)

            Spacer(minLength: 12)

            HStack(spacing: 0) {
                ForEach(content.hours, id: \.self) { hour in
                    VStack(spacing: 4) {
                        Text(verbatim: hour.time)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .opacity(0.8)
                        Text(verbatim: hour.emoji).font(.system(size: 22))
                        Text(verbatim: hour.temperature)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 12)
            .background(sky.isDark ? Color.black.opacity(0.3) : Color.white.opacity(0.75), in: .rect(cornerRadius: 22))
            .padding(.horizontal, 20)

            if content.showsWatermark {
                Text(verbatim: "☀️ Skymoji")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .opacity(0.7)
                    .padding(.top, 14)
            }
            Spacer().frame(height: content.showsWatermark ? 18 : 30)
        }
        .padding(.horizontal, 20)
        .foregroundStyle(sky.textColor)
        .frame(width: ShareExporter.cardSize.width, height: ShareExporter.cardSize.height)
    }
}

/// One frame for export: the particle system as it is now, with the card's text on top.
private struct ShareCardFrame: View {
    let content: ShareCardContent
    let system: EmojiParticleSystem

    var body: some View {
        ZStack {
            Canvas { context, size in
                system.draw(in: &context, size: size)
            }
            ShareCardOverlay(content: content)
        }
        .frame(width: ShareExporter.cardSize.width, height: ShareExporter.cardSize.height)
    }
}

/// Renders the card to a video, GIF or photo file in the temporary folder.
@MainActor
enum ShareExporter {
    enum Format: String, CaseIterable, Identifiable {
        case video, gif, photo
        var id: Self { self }

        var title: String {
            switch self {
            case .video: String(localized: "Video")
            case .gif: String(localized: "GIF")
            case .photo: String(localized: "Photo")
            }
        }

        var hint: String {
            switch self {
            case .video: String(localized: "Best for Stories, Reels and TikTok.")
            case .gif: String(localized: "Plays right in Messages and chats.")
            case .photo: String(localized: "A still image for anywhere.")
            }
        }
    }

    static let cardSize = CGSize(width: 360, height: 640)
    static let duration: Double = 5

    static func export(_ content: ShareCardContent, as format: Format, progress: @escaping (Double) -> Void) async throws -> URL {
        let system = EmojiParticleSystem(conditions: content.conditions)
        let start = Date.timeIntervalSinceReferenceDate
        // First update prewarms the scene so it starts full.
        system.update(now: start, size: cardSize, tilt: 0)

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Share", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        switch format {
        case .photo:
            // Let the scene run a moment so particles are spread out.
            advance(system, from: start, seconds: 1.5, fps: 20)
            guard let image = render(content, system, scale: 3) else { throw ExportError.renderFailed }
            let url = folder.appendingPathComponent("\(content.fileStem).png")
            guard let data = UIImage(cgImage: image).pngData() else { throw ExportError.renderFailed }
            try data.write(to: url)
            progress(1)
            return url

        case .gif:
            // Smaller and fewer frames: GIFs get big fast.
            let fps = 12.0
            let url = folder.appendingPathComponent("\(content.fileStem).gif")
            let frameCount = Int(duration * fps)
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
                throw ExportError.renderFailed
            }
            CGImageDestinationSetProperties(destination, [
                kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0],
            ] as CFDictionary)
            let frameProperties = [
                kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: 1 / fps],
            ] as CFDictionary
            for index in 0..<frameCount {
                system.update(now: start + Double(index + 1) / fps, size: cardSize, tilt: 0)
                guard let image = render(content, system, scale: 1.5) else { throw ExportError.renderFailed }
                CGImageDestinationAddImage(destination, image, frameProperties)
                progress(Double(index + 1) / Double(frameCount))
                await Task.yield()
            }
            guard CGImageDestinationFinalize(destination) else { throw ExportError.renderFailed }
            return url

        case .video:
            let fps: Int32 = 30
            let url = folder.appendingPathComponent("\(content.fileStem).mp4")
            let pixelSize = CGSize(width: cardSize.width * 3, height: cardSize.height * 3)
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: pixelSize.width,
                AVVideoHeightKey: pixelSize.height,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 3_500_000],
            ])
            input.expectsMediaDataInRealTime = false
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: pixelSize.width,
                kCVPixelBufferHeightKey as String: pixelSize.height,
            ])
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? ExportError.renderFailed }
            writer.startSession(atSourceTime: .zero)

            let frameCount = Int(duration * Double(fps))
            for index in 0..<frameCount {
                system.update(now: start + Double(index + 1) / Double(fps), size: cardSize, tilt: 0)
                guard let image = render(content, system, scale: 3),
                      let pool = adaptor.pixelBufferPool,
                      let buffer = pixelBuffer(from: image, pool: pool, size: pixelSize) else {
                    throw ExportError.renderFailed
                }
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(5))
                }
                adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: fps))
                progress(Double(index + 1) / Double(frameCount))
                await Task.yield()
            }
            input.markAsFinished()
            await writer.finishWriting()
            if writer.status != .completed { throw writer.error ?? ExportError.renderFailed }
            return url
        }
    }

    enum ExportError: LocalizedError {
        case renderFailed
        var errorDescription: String? { String(localized: "Couldn't make the share card. Try again.") }
    }

    private static func advance(_ system: EmojiParticleSystem, from start: TimeInterval, seconds: Double, fps: Double) {
        for index in 1...Int(seconds * fps) {
            system.update(now: start + Double(index) / fps, size: cardSize, tilt: 0)
        }
    }

    private static func render(_ content: ShareCardContent, _ system: EmojiParticleSystem, scale: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: ShareCardFrame(content: content, system: system))
        renderer.scale = scale
        renderer.isOpaque = true
        return renderer.cgImage
    }

    private static func pixelBuffer(from image: CGImage, pool: CVPixelBufferPool, size: CGSize) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return buffer
    }
}

/// The share sheet: a live preview of the card, a format picker and the Share button.
struct ShareCardSheet: View {
    let content: ShareCardContent

    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    @State private var format: ShareExporter.Format = .video
    @State private var progress: Double?
    @State private var exported: ExportedFile?
    @State private var errorMessage: String?
    @State private var showingPaywall = false

    struct ExportedFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                GeometryReader { proxy in
                    let scale = min(proxy.size.width / ShareExporter.cardSize.width, proxy.size.height / ShareExporter.cardSize.height)
                    ZStack {
                        EmojiSceneView(conditions: content.conditions)
                        ShareCardOverlay(content: content)
                    }
                    .frame(width: ShareExporter.cardSize.width, height: ShareExporter.cardSize.height)
                    .clipShape(.rect(cornerRadius: 24))
                    .scaleEffect(scale)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(content.placeName), \(content.temperature), \(content.condition)"))

                Picker("Format", selection: $format) {
                    ForEach(ShareExporter.Format.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                .pickerStyle(.segmented)

                Text(format.hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await share() }
                } label: {
                    Group {
                        if let progress {
                            ProgressView(value: progress).tint(.white)
                        } else {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(progress != nil)

                if content.showsWatermark {
                    Button("Remove the watermark with Skymoji+") { showingPaywall = true }
                        .font(.footnote)
                }
            }
            .padding()
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $exported) { file in
            ActivityView(items: [file.url])
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .alert("Couldn't share", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func share() async {
        progress = 0
        defer { progress = nil }
        var content = content
        content.showsWatermark = !purchases.hasPlus
        do {
            let url = try await ShareExporter.export(content, as: format) { value in
                progress = value
            }
            exported = ExportedFile(url: url)
            AppAnalytics.log(.shareExported, ["format": "\(format)"])
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The system share sheet.
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
