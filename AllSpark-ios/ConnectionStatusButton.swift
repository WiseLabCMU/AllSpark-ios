import SwiftUI

struct ConnectionStatusButton: View {
    @ObservedObject private var connectionManager = ConnectionManager.shared

    var body: some View {
        Button(action: {
            if connectionManager.isConnected {
                connectionManager.disconnect()
            } else if !connectionManager.isAttemptingConnection {
                connectionManager.connect()
            }
        }) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: iconName)
                    .font(.system(size: AppConstants.UI.iconSizeSecure))
                    .foregroundColor(iconColor)
                
                if connectionManager.isConnected && connectionManager.isSecureProtocol {
                    Image(systemName: "lock.fill")
                        .font(.system(size: AppConstants.UI.iconSizeSecurePoint, weight: .bold))
                        .foregroundColor(AppConstants.Colors.statusConnected)
                        .offset(x: AppConstants.UI.offsetSecureBadge, y: AppConstants.UI.offsetSecureBadge)
                }
            }
            .frame(width: AppConstants.UI.buttonSizeMedium, height: AppConstants.UI.buttonSizeMedium)
            .background(Color(AppConstants.Colors.backgroundBaseUI).opacity(AppConstants.UI.buttonBackgroundAlpha))
            .clipShape(Circle())
        }
        .disabled(connectionManager.isAttemptingConnection)
    }

    private var iconName: String {
        if connectionManager.isConnected {
            return "wifi"
        } else if connectionManager.isAttemptingConnection {
            return "wifi"
        } else {
            return "wifi.slash"
        }
    }

    private var iconColor: Color {
        if connectionManager.isConnected {
             return AppConstants.Colors.statusConnected
        } else if connectionManager.isAttemptingConnection {
             return AppConstants.Colors.statusConnecting
        } else {
             return AppConstants.Colors.statusDisconnected
        }
    }
}
