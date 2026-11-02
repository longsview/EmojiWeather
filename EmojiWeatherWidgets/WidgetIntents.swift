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
        name = place.isCurrentLocation ? "Current Location" : place.name
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

/// The widget's arrow button: shows the next place.
struct NextPlaceIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Place"
    static var isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        SharedStore.cycleIndex += 1
        return .result()
    }
}
