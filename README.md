# AllSpark-ios

AllSpark system mobile app for iOS. This app provides real-time video capture, recording, and uploading capabilities with face detection and blurring features.

## Features

- **Camera Capture**: Real-time video capture from front or back camera
- **Face Detection & Blurring**: Automatic detection and pixelation of faces using Vision framework
- **Video Recording**: Record video to device with timestamp naming (supports MP4 and MOV formats)
- **Video Format Selection**: Choose between MP4 (default) or MOV format for recordings
- **Video Upload**: Upload recorded or selected videos to a remote server via WebSocket
- **Network Configuration**: Configurable server host for flexible deployment
- **Connection Testing**: Built-in ping and HTTP health check utilities

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

#### Command Message - Server Instructions

**Format:**
```json
{
  "command": "record",
  "message": "Optional additional context or instructions"
}
```

**Supported Commands:**
- `"record"` - Server requests the client to start/stop recording
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

1. **Configure Server Host**
   - Default: `localhost:8080`
   - Supports: IP addresses, hostnames, with or without protocol prefix
   - Automatically converts HTTP/HTTPS to WS/WSS

2. **Select Video Format**
   - Default: `MP4`
   - Options: `MP4` or `MOV`
   - Selection applies to all future recordings
   - Upload metadata includes correct MIME type based on format

3. **Ping Server**
   - Single ICMP ping to test network connectivity
   - Displays round-trip time in milliseconds
   - Shows response byte count

4. **Test HTTP Connection**
   - Calls `/api/health` endpoint
   - Verifies server status and uptime
   - Displays health check response

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
   |-- Send Metadata (JSON) ------> |
   |                                |
   |-- Send Video Data (Binary) --> |
   |                                |
   |<- Status: success/error ------- |
   |                                |
   |<-- Command (if issued) ------- |
   |                                |
   |-- Acknowledge & Display ----> |
```

## Icons

Icons used are sourced internally in iOS from SF Symbols Online from a repository like this one: https://github.com/andrewtavis/sf-symbols-online.

## Known Limitations

- WebSocket connection state is confirmed after 0.5 second delay (not real-time)
- Face detection runs on main frame processing queue
- Video recordings are stored in Documents directory
- Both MP4 and MOV formats require decoder support on the receiving server
