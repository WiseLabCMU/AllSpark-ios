# AllSpark-ios

AllSpark Edge mobile app for iOS — real-time video capture, recording, and upload with face detection and blurring.

> [!IMPORTANT]
> AllSpark Edge consists of this iOS client and the [AllSpark Edge Server](https://github.com/WiseLabCMU/AllSpark-edge-server). For compatibility reasons, please ensure that you run release versions of both repositories that share at least the same minor semantic version tag (e.g., `v0.3.x` of the iOS app with `v0.3.x` of the server).

For detailed architecture diagrams, feature requirements, and source file index, see **[REQUIREMENTS.md](REQUIREMENTS.md)**.

See also: **[CHANGELOG.md](CHANGELOG.md)** · **[RELEASE.md](RELEASE.md)**

## Features

- Camera capture (front/back) with continuous chunked recording
- Face detection & real-time blurring (Vision framework)
- Automatic storage management
- Bonjour/mDNS server auto-discovery & QR code pairing
- WebSocket connection with WSS/WS fallback and auto-reconnect
- Server-initiated time-range video upload
- Server-managed communications policy with app-level enforcement
- Configurable video format (MP4/MOV) synced from server

## Client Configuration

The iOS application receives a `clientConfig` JSON object from the Edge Server to remotely configure capture formats and sensor streams. The new architecture separates sensor streams to allow for multimodal VLM/LLM analysis on the edge server.

### Default Sensor Streams

Here are the default expectations and supported formats:

```json
"clientConfig": {
  "fps": 30,
  "videoChunkDurationMs": 10000,
  "videoBufferMaxMB": 16000,
  "videoFormat": "mp4",
  "audioFormat": "wav",
  "depthFormat": "png",
  "poseFormat": "json",
  "timestampFormat": "txt"
}
```

### Format Options
- **`videoFormat`** (rgb only, no audio): `"mp4"`, `"mov"`, `"none"`
- **`audioFormat`**: `"wav"`, `"m4a"`, `"none"`
- **`depthFormat`**: `"png"`, `"exr"`, `"none"`
- **`poseFormat`**: `"json"`, `"none"`
- **`timestampFormat`**: `"txt"`, `"none"`

> [!NOTE]
> Setting any format to `"none"` will remotely disable collection from that specific sensor. This allows operators to save bandwidth and compute resources when certain streams are not needed for their agentic pipelines.

### Output File Structure

For each recording chunk at epoch timestamp `{ts}`, the app produces separate companion files:

| Stream | Filename | Condition |
|--------|----------|-----------|
| Video (RGB only) | `chunk_{ts}.mp4` or `.mov` | `videoFormat ≠ "none"` |
| Audio | `audio_{ts}.wav` or `.m4a` | `audioFormat ≠ "none"` |
| Depth | `depth_{ts}/depth_{frame}_{ms}.png` | `depthFormat ≠ "none"`, LiDAR device required |
| Pose | `pose_{ts}.json` | `poseFormat ≠ "none"` |
| Timestamps | `timestamps_{ts}.txt` | `timestampFormat ≠ "none"` |

> [!IMPORTANT]
> **Depth capture** requires a LiDAR-equipped device (iPhone Pro/iPad Pro) with the **back camera** selected. Depth is captured via **ARKit** (`ARWorldTrackingConfiguration` with `.sceneDepth` frame semantics), not AVFoundation. On devices without LiDAR or when using the front camera, depth frames are silently skipped.
> **Pose data** uses ARKit 6DoF camera transforms (4×4 camera-to-world matrix + intrinsics) when the back camera with depth is active. On the front camera, it falls back to CoreMotion 3DoF (rotation matrix, gravity, user acceleration).

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
