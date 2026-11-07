import AppIntents
import WidgetKit

/// A place the widget can show, for the "Edit Widget" picker.
struct PlaceEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Place"
    static var defaultQuery = PlaceQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(place: WidgetPlace) {
        id = place.id
        name = place.isCurrentLocation ? String(localized: "Current Location") : place.name
    }
}

struct PlaceQuery: EntityQuery {
    func entities(for identifiers: [PlaceEntity.ID]) async throws -> [PlaceEntity] {
        SharedStore.places.filter { identifiers.contains($0.id) }.map(PlaceEntity.init(place:))
    }

    func suggestedEntities() async throws -> [PlaceEntity] {
        SharedStore.places.map(PlaceEntity.init(place:))
    }
}

/// Long-press > Edit Widget: pin one place, or leave it empty to step through all of them.
struct SelectPlaceIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Choose Place"
    static var description = IntentDescription("Show one place, or leave empty to step through all your places.")

    @Parameter(title: "Place")
    var place: PlaceEntity?

    init() {}
}

/// The widget's back and next buttons.
struct StepPlaceIntent: AppIntent {
    static var title: LocalizedStringResource = "Change Place"
    static var isDiscoverable = false

    @Parameter(title: "Forward")
    var forward: Bool

    init() {}

    init(forward: Bool) {
        self.forward = forward
    }

    func perform() async throws -> some IntentResult {
        SharedStore.cycleIndex += forward ? 1 : -1
        return .result()
    }
}
