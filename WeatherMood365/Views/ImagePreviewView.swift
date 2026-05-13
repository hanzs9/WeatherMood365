import SwiftUI

struct ImagePreviewView: View {
    @Environment(\.dismiss) private var dismiss

    let image: UIImage

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
}
