import AppKit
import SwiftUI

/// The application logo from the asset catalog (`AppLogo.imageset`), with the
/// brand mark as a fallback if the asset is unavailable.
///
/// A dedicated image set is used because `AppIcon.appiconset` is a special
/// catalog type that Xcode does not expose as a named image.
struct AppLogoView: View {
    var size: CGFloat = 38

    var body: some View {
        if let logo = NSImage(named: "AppLogo") {
            Image(nsImage: logo)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(KBTheme.brandGradient)
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        }
    }
}
