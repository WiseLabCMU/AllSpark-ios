import SwiftUI

struct CameraView: View {

    @Binding var cgImage: CGImage?

    var body: some View {
        GeometryReader { geometry in
            if let image = cgImage {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width,
                           height: geometry.size.height)
            } else {
                ContentUnavailableView("No camera feed", systemImage: "xmark.circle.fill")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray.opacity(0.2))
    }

}

#Preview {
    @Previewable @State var value = UIImage(named: "exampleImage")?.cgImage
    CameraView(cgImage: $value)
}
