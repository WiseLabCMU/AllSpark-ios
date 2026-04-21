import Foundation
import CoreGraphics
import UIKit
import SwiftUI

/// Centralized repository for all magic numbers and generic constants across the app.
enum AppConstants {
    enum UI {
        // Opacity
        static let overlayOpacityDark: CGFloat = 0.85
        static let overlayOpacityMedium: CGFloat = 0.7
        static let overlayOpacityLight: CGFloat = 0.6
        static let overlayOpacityFaint: CGFloat = 0.1
        static let buttonBackgroundAlpha: CGFloat = 0.5

        // Sizing
        static let buttonSizeLarge: CGFloat = 50.0
        static let buttonSizeMedium: CGFloat = 40.0
        static let iconSizeSmall: CGFloat = 12.0
        static let iconSizeSecure: CGFloat = 20.0
        static let iconSizeSecurePoint: CGFloat = 10.0

        static let viewMaxHeightMedium: CGFloat = 200.0
        static let indicatorMinHeight: CGFloat = 36.0

        // Font Sizing
        static let fontSizeGateIcon: CGFloat = 56.0
        static let fontSizeTimer: CGFloat = 20.0
        static let fontSizeModes: CGFloat = 11.0

        // Spacing & Padding
        static let spacingLarge: CGFloat = 24.0
        static let spacingStandard: CGFloat = 20.0
        static let spacingMedium: CGFloat = 12.0
        static let spacingSmall: CGFloat = 8.0
        static let spacingTiny: CGFloat = 2.0

        static let paddingLarge: CGFloat = 50.0
        static let paddingHeader: CGFloat = 32.0
        static let paddingStandard: CGFloat = 20.0
        static let paddingSmall: CGFloat = 10.0
        static let paddingTiny: CGFloat = 6.0
        static let paddingMicro: CGFloat = 2.0

        static let offsetTrailingStatus: CGFloat = -80.0

        // Corner Radii
        static let cornerRadiusSwitch: CGFloat = 25.0
        static let cornerRadiusLarge: CGFloat = 20.0
        static let cornerRadiusMedium: CGFloat = 12.0
        static let cornerRadiusStandard: CGFloat = 10.0
        static let cornerRadiusSmall: CGFloat = 8.0
    }

    enum Colors {
        // Status & Connection Colors
        static let statusConnectedUI = UIColor.systemGreen
        static let statusConnectingUI = UIColor.systemOrange
        static let statusDisconnectedUI = UIColor.systemRed

        static let statusConnected = Color.green
        static let statusConnecting = Color.orange
        static let statusDisconnected = Color.red
        static let statusWarning = Color.yellow
        static let statusError = Color.red

        // Text Colors
        static let textPrimary = Color.white
        static let textSecondary = Color.gray

        // Backgrounds & Overlays
        static let backgroundBase = Color.black
        static let backgroundBaseUI = UIColor.black
        static let overlayBase = Color.black
        static let overlayBaseLight = Color.white
        static let backgroundSecondary = Color(UIColor.secondarySystemBackground)
        static let backgroundGrouped = Color(UIColor.systemGroupedBackground)

        // Actions
        static let buttonPrimary = Color.blue
        static let buttonDestructive = Color.red
        static let actionToggleOn = Color.blue
        static let actionToggleOff = Color.red
    }

    enum Privacy {
        // High scale for strong privacy masking (pixelation)
        static let pixelationScale: CGFloat = 50.0
    }

    enum Video {
        static let defaultChunkDurationMs: Int = 10000
        static let dimensionHigh: Int = 1920
        static let dimensionLow: Int = 1080
        static let defaultFPS: Double = 30.0
    }

    enum Audio {
        static let sampleRate: Double = 44100.0
        static let bitRate: Int = 128000
        static let channels: Int = 1
    }

    enum Network {
        static let autoReconnectDelaySeconds: TimeInterval = 5.0
    }

    enum Storage {
        static let defaultVideoBufferMaxMB: Int = 16000
        static let bytesPerMB: Int64 = 1024 * 1024
    }
}
