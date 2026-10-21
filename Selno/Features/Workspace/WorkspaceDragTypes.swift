import Foundation
import UniformTypeIdentifiers

/// Dedicated drag payloads keep workspace module reordering separate from
/// calendar task drags, which use `public.utf8-plain-text`.
///
/// The app ships with a generated Info.plist, so a newly exported custom UTI
/// never reached the drop destination (the drag began but `onDrop` was never
/// called). `public.json` is a declared system type that plain text does not
/// conform to, and the payload also identifies its kind and source UUID, so a
/// stale drag state or an unrelated JSON file can never reorder modules.
nonisolated enum WorkspaceDragType {
    static let module = UTType.json
    /// Workspace rows use a different system type from module cards so a
    /// module dragged over the sidebar (or vice versa) cannot match.
    static let workspace = UTType.xml
    private static let moduleKind = "selno.workspace.module"
    private static let workspaceKind = "selno.workspace"

    static func provider(for id: UUID) -> NSItemProvider {
        let payload = #"{"kind":"\#(moduleKind)","id":"\#(id.uuidString)"}"#
        return provider(type: module, payload: payload)
    }

    static func workspaceProvider(for id: UUID) -> NSItemProvider {
        let payload = #"<selno-workspace kind="\#(workspaceKind)" id="\#(id.uuidString)"/>"#
        return provider(type: workspace, payload: payload)
    }

    private static func provider(type: UTType, payload: String) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: type.identifier,
            visibility: .all
        ) { completion in
            completion(Data(payload.utf8), nil)
            return nil
        }
        return provider
    }

    static func moduleID(from data: Data) -> UUID? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              dictionary["kind"] as? String == moduleKind,
              let raw = dictionary["id"] as? String else { return nil }
        return UUID(uuidString: raw)
    }

    /// Accepts the drop only when the payload is a module drag for
    /// `expected`, the UUID captured when the drag began.
    static func receive(_ providers: [NSItemProvider], expected: UUID,
                        perform: @escaping @MainActor (UUID) -> Void) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(module.identifier)
        }) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: module.identifier) { data, _ in
            guard let data, moduleID(from: data) == expected else { return }
            Task { @MainActor in perform(expected) }
        }
        return true
    }
}