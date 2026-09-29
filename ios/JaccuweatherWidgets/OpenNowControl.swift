import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct OpenNowValueProvider: ControlValueProvider {
    var previewValue: OpenNowControlCopy.Face {
        currentFace()
    }

    func currentValue() async throws -> OpenNowControlCopy.Face {
        currentFace()
    }

    /// Reads the existing widget snapshot. A Personal Team with no App Group
    /// container gets the plain Open label and still launches the app.
    private func currentFace() -> OpenNowControlCopy.Face {
        let snapshot = WidgetSnapshotStore.load()
        return OpenNowControlCopy.face(
            temperatureF: snapshot?.temperatureF,
            symbolName: snapshot?.symbolName,
            placeName: snapshot?.locationName
        )
    }
}

@available(iOS 18.0, *)
private struct OpenNowControlLabel: View {
    var face: OpenNowControlCopy.Face

    var body: some View {
        let label = Label(face.title, systemImage: face.symbolName)
        if let status = face.status {
            label.controlWidgetStatus(status)
        } else {
            label
        }
    }
}

@available(iOS 18.0, *)
struct OpenNowControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetSnapshotStore.openControlKind, provider: OpenNowValueProvider()) { face in
            ControlWidgetButton(action: OpenURLIntent(NowLink.url)) {
                OpenNowControlLabel(face: face)
            }
        }
        .displayName("Open Jaccuweather")
        .description("Opens the Now tab for the current place. Shows the temperature when a shared reading is available.")
    }
}
