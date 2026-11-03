import CoreLocation
import SwiftUI

/// The Skymoji Daily sheet: five questions, then the score, streak, sharing and
/// "guess tomorrow's high".
struct QuizView: View {
    @Environment(QuizStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(CityStore.self) private var cityStore
    @Environment(WeatherProvider.self) private var weather
    @Environment(\.dismiss) private var dismiss

    /// The question on screen. Answering shows the explanation; Next moves on.
    @State private var currentIndex = 0
    @State private var rightAnswers = 0
    @State private var wrongAnswers = 0

    /// Where "you" are: the current location, or the first saved city without one.
    private var origin: (location: CLLocation, name: String)? {
        if let here = location.location {
            return (here, location.placeName ?? String(localized: "My Location"))
        }
        if let city = cityStore.cities.first { return (city.location, city.name) }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let result = store.guessResult {
                        GuessResultCard(result: result) { store.dismissGuessResult() }
                    }
                    if let quiz = store.quiz {
                        header(quiz)
                        if currentIndex < quiz.questions.count {
                            QuestionCard(question: quiz.questions[currentIndex]) { option in
                                let question = quiz.questions[currentIndex]
                                store.answer(question.id, with: option)
                                if option == question.correctIndex { rightAnswers += 1 } else { wrongAnswers += 1 }
                            } onNext: {
                                withAnimation(.snappy) { currentIndex += 1 }
                            }
                            .id(currentIndex)
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                        } else {
                            QuizSummary(quiz: quiz, origin: origin)
                        }
                    } else {
                        VStack(spacing: 12) {
                            Text(verbatim: "🧩").font(.system(size: 64))
                            ProgressView("Building today's quiz…")
                        }
                        .padding(.top, 80)
                    }
                }
                .padding()
            }
            .navigationTitle(store.quiz.map { "Skymoji Daily #\($0.number)" } ?? String(localized: "Skymoji Daily"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sensoryFeedback(.success, trigger: rightAnswers)
        .sensoryFeedback(.error, trigger: wrongAnswers)
        .preferredColorScheme(SystemAppearance.shared.colorScheme)
        .task {
            await store.prepare(origin: origin?.location, weather: weather)
            if let quiz = store.quiz {
                currentIndex = quiz.questions.firstIndex { !$0.isAnswered } ?? quiz.questions.count
            }
        }
    }

    private func header(_ quiz: DailyQuiz) -> some View {
        HStack {
            Text(verbatim: quiz.grid)
                .font(.title3)
                .accessibilityLabel(Text("Score \(quiz.score) of \(quiz.questions.count)"))
            Spacer()
            if store.currentStreak > 0 {
                Text(verbatim: "🔥 \(store.currentStreak)")
                    .font(.system(.headline, design: .rounded, weight: .heavy))
                    .accessibilityLabel(Text("\(store.currentStreak)-day streak"))
            }
        }
    }
}

// MARK: - Question

private struct QuestionCard: View {
    let question: QuizQuestion
    let onAnswer: (Int) -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text(verbatim: question.emoji)
                .font(.system(size: 72))
                .accessibilityHidden(true)
            Text(question.prompt)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 10) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    OptionButton(option: option, state: state(for: index)) {
                        onAnswer(index)
                    }
                    .disabled(question.isAnswered)
                }
            }

            if question.isAnswered {
                VStack(spacing: 14) {
                    Text(verbatim: question.isCorrect ? "☀️ " + String(localized: "Nice!") : "🌧️ " + String(localized: "Not quite."))
                        .font(.system(.headline, design: .rounded, weight: .heavy))
                    Text(question.explanation)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button(action: onNext) {
                        Text("Next")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                }
                .transition(.opacity)
            }
        }
        .animation(.snappy, value: question.isAnswered)
    }

    private func state(for index: Int) -> OptionButton.AnswerState {
        guard question.isAnswered else { return .open }
        if index == question.correctIndex { return .right }
        if index == question.chosenIndex { return .wrong }
        return .dimmed
    }
}

private struct OptionButton: View {
    enum AnswerState { case open, right, wrong, dimmed }

    let option: QuizQuestion.Option
    let state: AnswerState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if !option.emoji.isEmpty {
                    Text(verbatim: option.emoji).font(.title2).accessibilityHidden(true)
                }
                Text(verbatim: option.text)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                switch state {
                case .right: Text(verbatim: "✅")
                case .wrong: Text(verbatim: "❌")
                default: EmptyView()
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            .background(background, in: .rect(cornerRadius: 18))
            .opacity(state == .dimmed ? 0.5 : 1)
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityValue(accessibilityValue)
    }

    private var background: Color {
        switch state {
        case .right: Color.green.opacity(0.22)
        case .wrong: Color.red.opacity(0.18)
        default: Color.primary.opacity(0.06)
        }
    }

    private var accessibilityValue: Text {
        switch state {
        case .right: Text("Correct answer")
        case .wrong: Text("Your answer, wrong")
        default: Text(verbatim: "")
        }
    }
}

// MARK: - Results

private struct QuizSummary: View {
    let quiz: DailyQuiz
    let origin: (location: CLLocation, name: String)?

    @Environment(QuizStore.self) private var store

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 6) {
                Text(verbatim: quiz.score == quiz.questions.count ? "🌈" : (quiz.score >= 3 ? "☀️" : "⛅️"))
                    .font(.system(size: 64))
                    .accessibilityHidden(true)
                Text(verbatim: "\(quiz.score)/\(quiz.questions.count)")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                Text(verbatim: quiz.grid).font(.title2)
                    .accessibilityHidden(true)
                if store.currentStreak > 0 {
                    Text("🔥 \(store.currentStreak)-day streak")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                }
                Text("Come back tomorrow for a new quiz.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ShareLink(item: store.shareText) {
                Label("Share results", systemImage: "square.and.arrow.up")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)

            if let origin {
                TomorrowGuessCard(origin: origin)
            }
            StatsCard(stats: store.stats)
            ReminderCard()
        }
    }
}

/// "Guess tomorrow's high": the answer arrives tomorrow, a reason to come back.
private struct TomorrowGuessCard: View {
    let origin: (location: CLLocation, name: String)

    @Environment(QuizStore.self) private var store
    @Environment(WeatherProvider.self) private var weather
    @State private var value: Int?

    private var unit: UnitTemperature { DisplaySettings.temperatureUnit }

    var body: some View {
        QuizCard {
            if store.hasGuessForTomorrow, let guess = store.pendingGuess {
                let shown = Measurement(value: guess.celsius, unit: UnitTemperature.celsius).shortTemperature
                Text(verbatim: "🔮").font(.largeTitle).accessibilityHidden(true)
                Text("You guessed \(shown) for tomorrow's high in \(guess.placeName).")
                    .font(.system(.headline, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("Come back tomorrow to see how close you were.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(verbatim: "🔮").font(.largeTitle).accessibilityHidden(true)
                Text("Guess tomorrow's high in \(origin.name)")
                    .font(.system(.headline, design: .rounded))
                    .multilineTextAlignment(.center)
                HStack(spacing: 24) {
                    stepButton("minus") { value = (value ?? 0) - 1 }
                        .accessibilityLabel("Lower")
                    Text(verbatim: "\(value ?? 0)°")
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .frame(minWidth: 100)
                    stepButton("plus") { value = (value ?? 0) + 1 }
                        .accessibilityLabel("Higher")
                }
                .accessibilityElement(children: .combine)
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: value = (value ?? 0) + 1
                    case .decrement: value = (value ?? 0) - 1
                    @unknown default: break
                    }
                }
                Button("Lock it in") {
                    let guess = Measurement(value: Double(value ?? 0), unit: unit)
                    store.lockInGuess(guess, placeName: origin.name, location: origin.location)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        }
        .task {
            // Start from today's high, so the guess is about the change, not the climate.
            guard value == nil else { return }
            let today = weather.cachedWeather(for: origin.location)?.daily.first?.highTemperature
            value = Int((today?.converted(to: unit).value ?? (unit == .fahrenheit ? 70 : 21)).rounded())
        }
    }

    private func stepButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.snappy) { action() } }) {
            Image(systemName: systemName)
                .font(.title3.weight(.bold))
                .frame(width: 48, height: 48)
                .background(Color.primary.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct GuessResultCard: View {
    let result: GuessResult
    let onDismiss: () -> Void

    var body: some View {
        let guess = Measurement(value: result.guess.celsius, unit: UnitTemperature.celsius).shortTemperature
        let actual = Measurement(value: result.actualCelsius, unit: UnitTemperature.celsius).shortTemperature
        QuizCard {
            Text(verbatim: result.emoji).font(.system(size: 48)).accessibilityHidden(true)
            Text("You guessed \(guess) for today's high in \(result.guess.placeName). It's \(actual).")
                .font(.system(.headline, design: .rounded))
                .multilineTextAlignment(.center)
            Button("Got it", action: onDismiss)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
    }
}

private struct StatsCard: View {
    let stats: QuizStats

    var body: some View {
        QuizCard {
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    stat("📅", "\(stats.played)", String(localized: "Played"))
                    stat("🔥", "\(stats.bestStreak)", String(localized: "Best streak"))
                }
                GridRow {
                    stat("🌈", "\(stats.perfectDays)", String(localized: "Perfect days"))
                    stat("🎯", "\(stats.bullseyes)", String(localized: "Bullseye guesses"))
                }
            }
        }
    }

    private func stat(_ emoji: String, _ value: String, _ title: String) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: "\(emoji) \(value)")
                .font(.system(.title3, design: .rounded, weight: .heavy))
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct ReminderCard: View {
    @Environment(QuizStore.self) private var store
    @AppStorage("quiz.reminder") private var isOn = false

    var body: some View {
        QuizCard {
            Toggle(isOn: Binding(
                get: { isOn },
                set: { newValue in
                    isOn = newValue
                    Task { isOn = await store.setReminder(newValue) }
                }
            )) {
                Label("Remind me each morning", systemImage: "bell")
                    .font(.system(.body, design: .rounded, weight: .semibold))
            }
        }
    }
}

private struct QuizCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 12) { content }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 24))
    }
}
