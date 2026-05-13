import ImageIO
import Photos
import SwiftUI
import UIKit

struct PickedPhoto {
    enum Source {
        case camera
        case photoLibrary
    }

    var data: Data
    var date: Date?
    var location: PhotoLocation?
    var source: Source
}

struct CameraPickerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onPhotoPicked: (PickedPhoto) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPickerView

        init(parent: CameraPickerView) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.86) {
                parent.onPhotoPicked(PickedPhoto(data: data, date: Date(), location: nil, source: .camera))
            }

            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct PhotoLibraryPickerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    let onPhotoPicked: (PickedPhoto) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: PhotoLibraryPickerView

        init(parent: PhotoLibraryPickerView) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.86) else {
                parent.dismiss()
                return
            }

            let asset = info[.phAsset] as? PHAsset
            var location = asset?.location.map {
                PhotoLocation(
                    latitude: $0.coordinate.latitude,
                    longitude: $0.coordinate.longitude,
                    name: nil
                )
            }
            if location == nil {
                location = Self.photoLocation(from: data)
            }

            parent.onPhotoPicked(PickedPhoto(
                data: data,
                date: asset?.creationDate,
                location: location,
                source: .photoLibrary
            ))
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        private static func photoLocation(from data: Data) -> PhotoLocation? {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
                  let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
                  let longitude = gps[kCGImagePropertyGPSLongitude] as? Double else {
                return nil
            }

            let latitudeRef = (gps[kCGImagePropertyGPSLatitudeRef] as? String) ?? "N"
            let longitudeRef = (gps[kCGImagePropertyGPSLongitudeRef] as? String) ?? "E"
            return PhotoLocation(
                latitude: latitudeRef == "S" ? -latitude : latitude,
                longitude: longitudeRef == "W" ? -longitude : longitude,
                name: nil
            )
        }
    }
}
