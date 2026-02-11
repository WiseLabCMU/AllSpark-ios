# AllSpark-ios

AllSpark system mobile app for iOS. This app provides real-time video capture, recording, and uploading capabilities with face detection and blurring features.

## Features

- **Camera Capture**: Real-time video capture from front or back camera
- **Face Detection & Blurring**: Automatic detection and pixelation of faces using Vision framework
- **Continuous Recording**: Automatically records video in chunks (default 30s) when camera view is active
- **Storage Management**: Automatically manages device storage by deleting oldest recordings when limit is reached
- **Auto-Discovery**: Automatically discovers available servers on the local network using Bonjour/mDNS
- **Time-Range Upload**: Server can request upload of video segments for specific time ranges
- **Video Format Selection**: Choose between MP4 (default) or MOV format for recordings
- **Network Configuration**: Configurable server host with support for discovered services

## Architecture

- **CameraViewController**: Handles camera capture, face detection, continuous video recording, and user interaction
- **ConnectionManager**: Singleton managing WebSocket connections, Bonjour service discovery, and video uploads
- **SettingsView**: Network configuration, server discovery list, and connection diagnostics
- **WebSocket Protocol**: Two-phase upload (metadata → binary data) & JSON command interface

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

#### Command Message - Request Upload Time Range

**Format:**
```json
{
  "command": "uploadTimeRange",
  "message": "Optional additional context",
  "startTime": 1700000000.0,
  "endTime": 1700000060.0
}
```

**Parameters:**
- `command` (required): `"uploadTimeRange"` - Server requests client to upload video covering a specific range
- `startTime` (required): Unix timestamp (seconds) for start of range
- `endTime` (required): Unix timestamp (seconds) for end of range

**App Behavior**:
- Scans local recordings for files overlapping with the requested time range
- Automatically uploads any matching files to the server
- Ignores files that do not overlap the range

---

#### Client Configuration Sync

**Received when**: Client connects to server or server config changes

**Format:**
```json
{
  "type": "clientConfig",
  "config": {
    "videoFormat": "mp4",
    "videoChunkDurationMs": 30000,
    "videoBufferMaxMB": 16000
  }
}
```

**Parameters:**
- `videoFormat`: Preferred video format (`"mp4"` or `"mov"`)
- `videoChunkDurationMs`: Duration of each recording chunk in milliseconds
- `videoBufferMaxMB`: Maximum storage space to use for video buffer (oldest files deleted when exceeded)

**App Behavior**:
- Updates local settings to match server configuration
- Adjusts recording chunk size and storage limits dynamically

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

2. **Configure Server Host**
   - **Auto-Discovery**: Automatically updates with server found on local network (Bonjour/mDNS)
   - **Manual Entry**: Allows manual IP/Hostname entry if server is not discovered, edits will automatically attempt to connect to WebSocket
   - Default: `localhost:8080`
   - Supports: IP addresses, hostnames, with or without protocol prefix

3. **Configure Server Discovery**
   - **Auto-Discovery**: Automatically lists servers using `_allspark._tcp` found on local network (Bonjour/mDNS)
   - **Manual Discovery**: Allows manual selection of discovered servers to connect to

4. **Set SSL Verfification**
   - Default: `true`
   - If testing self-signed certificates, set to `false`

5. **Control/Monitor WebSocket Connection**
    **Manual Connection**: When `Disconnected` allows WebSocket connection attempts
    **Manual Disconnection**: When `Connected` allows WebSocket disconnection
   - Displays connection status (success/failure)
   - Shows connection protocol (ws:// or wss://) being used
   - Useful for diagnosing network or certificate issues

6. **Edit Permissions**
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

## Continuous Recording Workflow

The app operates on a "always-recording" model when the Camera view is active:

1. **View Appears**: Camera initializes and recording starts immediately.
2. **Chunking**: Video is recorded in chunks (default 30 seconds) defined by `videoChunkDurationMs`.
3. **Storage**: Files are saved locally to the device.
4. **Cleanup**: Oldest files are automatically deleted when total storage exceeds `videoBufferMaxMB`.
5. **Upload**: Files are NOT uploaded automatically. They are only uploaded when:
    - User explicitly taps "Upload" button
    - Server sends an `uploadTimeRange` command matching the file's time range

This ensures a buffer of recent video is always available for on-demand retrieval without saturating network bandwidth.

## Icons

Icons used are sourced internally in iOS from SF Symbols Online from a repository like this one: https://github.com/andrewtavis/sf-symbols-online.

## Known Limitations

- Video recordings are stored in Documents directory
- Both MP4 and MOV formats require decoder support on the receiving server
- Face detection performance depends on device capabilities and lighting conditions
