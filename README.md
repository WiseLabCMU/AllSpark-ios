# AllSpark-ios

AllSpark system mobile app for iOS. This app provides real-time video capture, recording, and uploading capabilities with face detection and blurring features.

## Features

- **Camera Capture**: Real-time video capture from front or back camera
- **Face Detection & Blurring**: Automatic detection and pixelation of faces using Vision framework
- **Video Recording**: Record video to device with timestamp naming (supports MP4 and MOV formats)
- **Video Format Selection**: Choose between MP4 (default) or MOV format for recordings
- **Video Upload**: Upload recorded or selected videos to a remote server via WebSocket
- **Network Configuration**: Configurable server host for flexible deployment
- **Connection Testing**: Built-in WebSocket and HTTP health check utilities

## Architecture

- **CameraViewController**: Handles camera capture, face detection, video recording, and WebSocket communication
- **SettingsView**: Network configuration and connection diagnostics
- **WebSocket Protocol**: Two-phase upload (metadata → binary data)

## WebSocket Communication

The iOS app establishes a WebSocket connection to a configured server for real-time video upload and command reception.

### Connection Setup

```swift
var serverHost = UserDefaults.standard.string(forKey: "serverHost") ?? "localhost:8080"
// URL is automatically converted to ws:// or wss:// protocol
```

### Sending Messages to Server

#### 1. Video Upload - Metadata Message (String/JSON)

**Sent when**: User selects a video file to upload

**Format (MP4):**
```json
{
  "filename": "video.mp4",
  "filesize": 1048576,
  "mimetype": "video/mp4"
}
```

**Format (MOV):**
```json
{
  "filename": "video.mov",
  "filesize": 1048576,
  "mimetype": "video/quicktime"
}
```

**Purpose**: Informs the server about the incoming video file before transmission

**MIME Types**:
- `"video/mp4"` - For MP4 format files
- `"video/quicktime"` - For MOV format files

---

#### 2. Video Upload - Binary Data Message

**Sent immediately after**: Metadata message

**Format**: Raw binary video file data (MP4 or MOV encoded video stream)

**Purpose**: Transmits the actual video file content to the server

---

### Receiving Messages from Server

#### Status Message - Upload Confirmation

**Received after**: Binary video data is successfully written to server

**Format:**
```json
{
  "status": "success",
  "message": "Video uploaded successfully"
}
```

**App Behavior**: Displays success alert to user

---

#### Status Message - Upload Error

**Received when**: Server encounters an error processing the upload

**Format:**
```json
{
  "status": "error",
  "message": "Failed to write file"
}
```

**App Behavior**: Displays error alert to user with error details

---

#### Command Message - Record with Duration and Auto-Upload

**Format:**
```json
{
  "command": "record",
  "message": "Optional additional context or instructions",
  "duration": 5000,
  "autoUpload": true,
  "camera": "front"
}
```

**Parameters:**
- `command` (required): `"record"` - Server requests client to record
- `message` (optional): Additional context to display to user
- `duration` (optional): Recording duration in milliseconds (default: 30000 = 30 seconds)
- `autoUpload` (optional): Whether to automatically upload after recording stops (default: false)
- `camera` (optional): Camera to use (`"front"` or `"back"`). If omitted, active camera is used.

**App Behavior**:
- Automatically starts video recording
- Records for the specified duration
- Displays alert with duration and auto-upload status
- When duration expires, stops recording
- If `autoUpload` is true, automatically uploads the recorded file to server
- If `autoUpload` is false, saves the file locally without uploading

---

#### Command Message - Server Instructions (Generic)

**Format:**
```json
{
  "command": "record",
  "message": "Optional additional context or instructions"
}
```

**Supported Commands:**
- `"record"` - Server requests the client to start recording with optional duration and auto-upload
  - Additional message context can be included
  - App displays command notification to user

**App Behavior**:
- Parses the command type
- Displays alert with command name and message
- Unknown commands are logged but not actioned

---

## Network Configuration

### Settings View

Located in **SettingsView.swift**, allows users to:

1. **Configure Device Name** (optional)
   - Custom name shown on server's web interface
   - Useful for identifying specific devices in the test host
   - Defaults to the iOS device name (e.g., "iPhone")

1. **Select Video Format**
   - Default: `MP4`
   - Options: `MP4` or `MOV`
   - Selection applies to all future recordings
   - Upload metadata includes correct MIME type based on format

1. **Configure Server Host**
   - Default: `localhost:8080`
   - Supports: IP addresses, hostnames, with or without protocol prefix

1. **Set SSL Verfification**
   - Default: `true`
   - If testing self-signed certificates, set to `false`

1. **Test WebSocket Connection**
   - Initiates a test WebSocket connection to verify server reachability
   - Displays connection status (success/failure)
   - Shows connection protocol (ws:// or wss://) being used
   - Useful for diagnosing network or certificate issues

1. **Test HTTP Connection**
   - Calls `/api/health` endpoint
   - Verifies server status and uptime
   - Displays health check response
   - Shows connection protocol (http:// or https://) being used

1. **Edit Permissions**
    - Opens Allspark's iOS app permissions settings
    - *Local Network*: May be required for WebSocket/HTTP connections depending on server configuration
    - *Microphone*: Required for audio recording
    - *Camera*: Required for video recording

## Connection Status Indicator

The **Camera** tab displays a WiFi icon in the top-right corner that indicates connection status:

- **Red WiFi with slash** - Disconnected from server
- **Orange WiFi** - Attempting to connect
- **Green WiFi** - Connected to server
- **Green WiFi + Green Lock** - Connected via secure WSS protocol

The lock icon overlay appears automatically when using a secure WebSocket (WSS) connection, indicating encrypted communication with the server.

### Server Disconnection Detection

When a previously established server connection becomes unavailable:

1. **Automatic Detection**: The app detects connection loss when WebSocket receive errors occur after successful connection
2. **UI Update**: The connection icon immediately changes from green to red
3. **User Alert**: A modal alert notifies the user that the server was lost with two options:
   - **Reconnect**: Manually initiate reconnection attempt
   - **Dismiss**: Close the alert
4. **Automatic Recovery**: The app automatically attempts to reconnect after 5 seconds, allowing the connection to be restored if the server comes back online
5. **Continuous Attempts**: Automatic reconnection attempts continue until the connection is restored or the user navigates away from the camera view

## HTTP Endpoints Used

The app makes HTTP requests to the following endpoints:

- **GET `/api/health`** - Health check during connection test
  - Returns: `{ "status": "ok", "timestamp": "...", "uptime": ... }`

## WebSocket Flow Diagram

```
iOS App                           Server
   |                                |
   |-- Connect WebSocket ---------> |
   |                                |
   |<-- Send Metadata (JSON) ------ | (if uploading)
   |                                |
   |<-- Send Video Data (Binary) -- | (if uploading)
   |                                |
   |<-- Status: success/error ----- |
   |                                |
   |<-- Command: record ----------- |
   |   (with duration & autoUpload) |
   |                                |
   |-- Start Recording ----------> |
   |                                |
   |-- Record for duration -------> |
   |                                |
   |-- Auto-stop & Upload --------> | (if autoUpload=true)
   |   (metadata & binary)          |
   |                                |
   |<-- Status: success/error ----- |
```

## Auto-Recording Workflow

When the server sends a `record` command with `duration` and `autoUpload` parameters:

1. **Client receives command** with duration (e.g., 5000ms) and autoUpload flag
2. **Recording starts immediately** without user interaction
3. **Alert displayed** showing duration and auto-upload status
4. **Recording continues** for the specified duration
5. **Auto-stop triggered** when timer expires
6. **File saved** to device
7. **Auto-upload triggered** (if `autoUpload` is true):
   - Metadata sent to server
   - Video file streamed to server
   - Server acknowledges receipt
8. **Process complete** - Ready for next command

## Icons

Icons used are sourced internally in iOS from SF Symbols Online from a repository like this one: https://github.com/andrewtavis/sf-symbols-online.

## Known Limitations

- Video recordings are stored in Documents directory
- Both MP4 and MOV formats require decoder support on the receiving server
- Face detection performance depends on device capabilities and lighting conditions
