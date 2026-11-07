import SwiftUI
import UIKit

// MARK: - Live preview

/// A small live scene at the top of the pack and emoji screens, so changes show right away.
struct SceneStylePreview: View {
    enum Sample: String, CaseIterable, Identifiable {
        case day, night, rain, snow
        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .day: "Day"
            case .night: "Night"
            case .rain: "Rain"
            case .snow: "Snow"
            }
        }

        var conditions: SceneConditions {
            switch self {
            case .day: SceneConditions(scene: .partlyCloudy, sky: .day, sunProgress: 0.3)
            case .night: SceneConditions(scene: .partlyCloudy, sky: .night)
            case .rain: SceneConditions(scene: .rain, intensity: 0.6, windDrift: 0.2, sky: .day)
            case .snow: SceneConditions(scene: .snow, intensity: 0.6, sky: .day)
            }
        }
    }

    @AppStorage(SceneStyle.packKey, store: SharedStore.defaults) private var pack: ScenePack = .classic
    @AppStorage(SceneStyle.customEmojiKey, store: SharedStore.defaults) private var customEmoji = ""
    @State private var sample: Sample = .day

    var body: some View {
        VStack(spacing: 12) {
            EmojiSceneView(conditions: sample.conditions, canvasScale: 0.62)
                .id("\(sample.rawValue)|\(pack.rawValue)|\(customEmoji)")
                .frame(height: 260)
                .clipShape(.rect(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.quaternary))
                .accessibilityHidden(true)
            Picker("Preview", selection: $sample) {
                ForEach(Sample.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }
}

// MARK: - Scene packs

struct ScenePackView: View {
    @AppStorage(SceneStyle.packKey, store: SharedStore.defaults) private var pack: ScenePack = .classic

    var body: some View {
        List {
            Section {
                SceneStylePreview()
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            }
            Section {
                row(.classic, subtitle: Text("Just the weather."))
                let seasonNow = ScenePack.seasonal.resolved().title
                row(.seasonal, subtitle: Text("Right now: \(seasonNow)"))
            }
            Section {
                ForEach(ScenePack.themed) { row($0, subtitle: nil) }
            } footer: {
                Text("Packs add a few seasonal emoji to every scene. The weather itself stays real.")
            }
        }
        .navigationTitle("Scene pack")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ option: ScenePack, subtitle: Text?) -> some View {
        Button {
            pack = option
            AppAnalytics.log(.scenePackChosen, ["pack": option.rawValue])
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title).foregroundStyle(.primary)
                    if let subtitle {
                        subtitle.font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(verbatim: option.preview)
                    .font(.title3)
                    .accessibilityHidden(true)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .opacity(pack == option ? 1 : 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(pack == option ? .isSelected : [])
    }
}

// MARK: - Your own emoji

struct CustomEmojiView: View {
    @AppStorage(SceneStyle.customEmojiKey, store: SharedStore.defaults) private var customJSON = ""
    @State private var editing: EmojiSlot?

    private var custom: [EmojiSlot: SceneEmoji] { SceneStyle.decodeCustom(customJSON) }

    var body: some View {
        List {
            Section {
                SceneStylePreview()
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            }
            Section {
                ForEach(EmojiSlot.allCases) { slot in
                    Button {
                        editing = slot
                    } label: {
                        HStack(spacing: 14) {
                            SceneEmojiImage(value: custom[slot] ?? .emoji(slot.original))
                                .frame(width: 36, height: 36)
                            Text(slot.title).foregroundStyle(.primary)
                            Spacer()
                            if custom[slot] != nil {
                                Text("Custom").font(.footnote).foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        if custom[slot] != nil {
                            Button("Reset", role: .destructive) { set(slot, to: nil) }
                        }
                    }
                }
            } footer: {
                Text("Tap one to swap it for any emoji. With Apple Intelligence, you can make a Genmoji in the emoji keyboard and use that too.")
            }
            if !custom.isEmpty {
                Section {
                    Button("Reset All", role: .destructive) {
                        SceneStyle.customEmoji = [:]
                        customJSON = SharedStore.defaults.string(forKey: SceneStyle.customEmojiKey) ?? ""
                    }
                }
            }
        }
        .navigationTitle("Your own emoji")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { slot in
            EmojiPickerSheet(slot: slot, current: custom[slot]) { picked in
                set(slot, to: picked)
            }
        }
    }

    private func set(_ slot: EmojiSlot, to value: SceneEmoji?) {
        var updated = custom
        // Picking the original emoji is the same as resetting.
        if let value, value != .emoji(slot.original) {
            updated[slot] = value
        } else {
            updated[slot] = nil
        }
        SceneStyle.customEmoji = updated
        if let value {
            let kind = if case .genmoji = value { "genmoji" } else { "emoji" }
            AppAnalytics.log(.customEmojiSet, ["slot": slot.rawValue, "kind": kind])
        }
        // Re-read so every view watching the setting updates.
        customJSON = SharedStore.defaults.string(forKey: SceneStyle.customEmojiKey) ?? ""
    }
}

/// Draws a scene emoji: plain text for an emoji, the saved picture for a Genmoji.
struct SceneEmojiImage: View {
    var value: SceneEmoji

    var body: some View {
        switch value {
        case .emoji(let emoji):
            Text(verbatim: emoji)
                .font(.system(size: 100))
                .minimumScaleFactor(0.1)
                .lineLimit(1)
        case .genmoji(let id):
            if let image = GenmojiStore.image(for: id) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(Text("Genmoji"))
            } else {
                Text(verbatim: "✨").font(.system(size: 100)).minimumScaleFactor(0.1)
            }
        }
    }
}

// MARK: - Picking an emoji or Genmoji

/// What came out of the keyboard: an emoji, or a Genmoji's image data.
enum PickedEmoji: Equatable {
    case emoji(String)
    case genmoji(Data)
}

struct EmojiPickerSheet: View {
    let slot: EmojiSlot
    let current: SceneEmoji?
    var onSave: (SceneEmoji?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked: PickedEmoji?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Type or pick any emoji.")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                ZStack {
                    if picked == nil {
                        SceneEmojiImage(value: current ?? .emoji(slot.original))
                            .frame(width: 96, height: 96)
                            .opacity(0.35)
                            .allowsHitTesting(false)
                    }
                    EmojiInputField { picked = $0 }
                        .frame(height: 110)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 24))

                Label {
                    Text("Want something new? Search in the emoji keyboard and tap Create New Emoji to make a Genmoji with Apple Intelligence.")
                } icon: {
                    Text(verbatim: "🪄")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(20)
            .navigationTitle(slot.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(picked == nil)
                }
                ToolbarItem(placement: .bottomBar) {
                    if current != nil {
                        Button("Use \(slot.original)") {
                            onSave(nil)
                            dismiss()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        switch picked {
        case .emoji(let emoji):
            onSave(.emoji(emoji))
        case .genmoji(let data):
            if let id = GenmojiStore.save(data) { onSave(.genmoji(id: id)) }
        case nil:
            break
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

/// A one-emoji text field that opens straight to the emoji keyboard and accepts Genmoji
/// (adaptive image glyphs). Whatever was typed last is the pick.
struct EmojiInputField: UIViewRepresentable {
    var onPick: (PickedEmoji) -> Void

    func makeUIView(context: Context) -> EmojiTextView {
        let view = EmojiTextView()
        view.supportsAdaptiveImageGlyph = true
        view.font = .systemFont(ofSize: 80)
        view.textAlignment = .center
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.tintColor = .clear
        view.autocorrectionType = .no
        view.spellCheckingType = .no
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 0, right: 0)
        view.delegate = context.coordinator
        view.accessibilityLabel = String(localized: "Emoji")
        DispatchQueue.main.async { view.becomeFirstResponder() }
        return view
    }

    func updateUIView(_ uiView: EmojiTextView, context: Context) {
        context.coordinator.onPick = onPick
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onPick: (PickedEmoji) -> Void

        init(onPick: @escaping (PickedEmoji) -> Void) {
            self.onPick = onPick
        }

        func textViewDidChange(_ textView: UITextView) {
            let text = textView.attributedText ?? NSAttributedString()
            guard text.length > 0 else { return }
            // Keep only the last thing typed.
            let lastRange = (text.string as NSString).rangeOfComposedCharacterSequence(at: text.length - 1)
            let last = text.attributedSubstring(from: lastRange)

            if let glyph = last.attribute(.adaptiveImageGlyph, at: 0, effectiveRange: nil) as? NSAdaptiveImageGlyph {
                textView.attributedText = last
                onPick(.genmoji(glyph.imageContent))
                return
            }
            guard let character = last.string.last, character.isEmoji else {
                // Letters and numbers don't make good weather. Put back what was there.
                textView.attributedText = text.attributedSubstring(from: NSRange(location: 0, length: lastRange.location))
                    .lastComposedCharacter
                return
            }
            textView.attributedText = last
            textView.textAlignment = .center
            onPick(.emoji(String(character)))
        }
    }
}

/// A text view that asks for the emoji keyboard.
final class EmojiTextView: UITextView {
    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
    }
}

private extension NSAttributedString {
    var lastComposedCharacter: NSAttributedString {
        guard length > 0 else { return self }
        return attributedSubstring(from: (string as NSString).rangeOfComposedCharacterSequence(at: length - 1))
    }
}

private extension Character {
    /// True for characters that show as emoji (not plain digits or symbols like #).
    var isEmoji: Bool {
        guard let first = unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation || (first.properties.isEmoji && unicodeScalars.count > 1)
    }
}
