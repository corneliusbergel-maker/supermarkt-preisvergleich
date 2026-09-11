import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Nimmt ein Foto direkt in der App auf.
///
/// Für ein Preisschild ist das der natürliche Weg — der Umweg über die
/// Kamera-App und die Fotoauswahl kostet drei zusätzliche Schritte, während
/// man vor dem Regal steht.
///
/// Auf Geräten ohne Kamera (Mac, Simulator) meldet `isAvailable` das, und die
/// Oberfläche bietet die Aufnahme gar nicht erst an.
enum CameraCapture {

    @MainActor
    static var isAvailable: Bool {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        return UIImagePickerController.isSourceTypeAvailable(.camera)
        #else
        return false
        #endif
    }
}

#if canImport(UIKit) && !targetEnvironment(macCatalyst)

struct CameraPicker: UIViewControllerRepresentable {

    /// Wird mit dem aufgenommenen Bild aufgerufen.
    let onImage: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onFinish: { dismiss() })
    }

    final class Coordinator: NSObject,
                             UIImagePickerControllerDelegate,
                             UINavigationControllerDelegate {

        private let onImage: (UIImage) -> Void
        private let onFinish: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onFinish: @escaping () -> Void) {
            self.onImage = onImage
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            onFinish()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish()
        }
    }
}

#endif
