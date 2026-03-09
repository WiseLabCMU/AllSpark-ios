# AllSpark-ios

AllSpark Edge mobile app for iOS — real-time video capture, recording, and upload with face detection and blurring.

> [!IMPORTANT]
> AllSpark Edge consists of this iOS client and the [AllSpark Edge Server](https://github.com/WiseLabCMU/AllSpark-edge-server). For compatibility reasons, please ensure that you run release versions of both repositories that share at least the same minor semantic version tag (e.g., `v0.3.x` of the iOS app with `v0.3.x` of the server).

For detailed architecture diagrams, feature requirements, and source file index, see **[REQUIREMENTS.md](REQUIREMENTS.md)**.

## Features

- Camera capture (front/back) with continuous chunked recording
- Face detection & real-time blurring (Vision framework)
- Automatic storage management
- Bonjour/mDNS server auto-discovery & QR code pairing
- WebSocket connection with WSS/WS fallback and auto-reconnect
- Server-initiated time-range video upload
- Server-managed communications policy with app-level enforcement
- Configurable video format (MP4/MOV) synced from server

## API & WebSocket Communication

See the **[Endpoints Documentation](https://github.com/WiseLabCMU/AllSpark-edge-server/blob/master/docs/endpoints.md)** in the AllSpark Edge Server repository.

## Icons

Icons are sourced from SF Symbols: https://github.com/andrewtavis/sf-symbols-online

## Known Limitations

- Video recordings are stored in the app sandbox Documents directory (not accessible to other apps or Files.app)
- Both MP4 and MOV formats require decoder support on the receiving server
- Face detection performance depends on device capabilities and lighting conditions
- iOS does not expose APIs to programmatically disable Bluetooth, AirDrop, or other radios — the app detects state and guides the user to Settings
- UWB, NFC, and Satellite policy enforcement is deferred (no public iOS API for runtime state detection)
- Communications policy enforcement is app-level only; device-wide radio lockdown requires MDM
