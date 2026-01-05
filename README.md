# USB-NCM Tester for iOS

An iOS diagnostic app for testing USB-NCM (Network Control Model) connectivity, specifically designed to debug ESP32-S3 USB networking issues with iOS devices.

## Background

### The Problem

When implementing USB-NCM on ESP32-S3 using TinyUSB's NCM device class, iOS connectivity presents unique challenges:

1. **iOS is picky about USB-NCM implementations** — Unlike macOS or Linux, iOS has stricter requirements for USB-NCM device enumeration and network interface setup. Minor deviations from the spec can cause iOS to reject the device entirely or fail to assign an IP address.

2. **TinyUSB's NCM implementation quirks** — The TinyUSB NCM device class works well with desktop operating systems but may require adjustments for iOS compatibility. Issues include:
   - Descriptor ordering and formatting
   - MAC address handling
   - NTB (NCM Transfer Block) parameter negotiation
   - Timing-sensitive enumeration sequences

3. **Debugging is difficult** — When USB-NCM fails on iOS, there's little visibility into what's happening. The network interface may appear briefly and disappear, or never appear at all. Traditional debugging tools don't help when the connection is unstable.

4. **Background connectivity** — iOS aggressively suspends apps and network connections. Testing whether a USB-NCM connection survives app backgrounding requires special handling.

## What This App Does

This app provides real-time visibility into USB-NCM connectivity on iOS:

### Network Interface Scanning
- Continuously scans all network interfaces every 2 seconds
- Identifies interface types (Wi-Fi, Cellular, Ethernet/USB, IPsec, Loopback)
- Highlights USB/Ethernet interfaces with visual indicators
- Shows IP addresses and interface status (up/down)

### Connection Testing
- Establishes TCP connections over the detected Ethernet interface
- Sends periodic HTTP keep-alive requests to verify connectivity
- Monitors connection path, viability, and interface changes
- Logs all connection events with timestamps

### Background Operation
- Uses location services to remain active in background
- Continues scanning and connection monitoring when backgrounded
- Debug output visible in Xcode console for background diagnostics

### Debug Output
All significant events are logged with `DEBUG:` prefix for easy filtering:
- Interface appearances/disappearances
- Connection state changes
- Path updates (interface, type, expensive/constrained status)
- Viability changes
- Request/response timing

## Usage

1. Build and run on an iOS device (not simulator)
2. Grant location permission (required for background operation)
3. Connect your ESP32-S3 USB-NCM device
4. Watch for the Ethernet interface to appear (marked with green "USB" badge)
5. The app will auto-connect and begin keep-alive requests
6. Monitor the connection log for issues
7. Background the app to test connection persistence

## Requirements

- iOS 17.0+
- Physical iOS device (USB-NCM won't work in simulator)
- ESP32-S3 or other USB-NCM device

## Project Structure

```
USBNCMTester/
├── USBNCMTesterApp.swift        # App entry point
├── ContentView.swift             # Main UI with settings sheet
├── Models/
│   └── NetworkInterface.swift    # Interface model and type detection
├── Views/
│   ├── InterfaceListView.swift   # Interface list display
│   └── ConnectionStatusView.swift # Connection status and logs
└── Services/
    ├── NetworkInterfaceScanner.swift # getifaddrs-based scanning
    ├── ConnectionManager.swift       # NWConnection-based TCP testing
    └── LocationManager.swift         # Background execution support
```

## Debugging Tips

1. **Filter console output**: Use `DEBUG:` to filter relevant logs in Xcode
2. **Check interface names**: USB-NCM typically appears as `en1`, `en2`, etc.
3. **Watch for viability**: "Connection viability: not viable" indicates path issues
4. **Monitor path updates**: Interface type should show as `wiredEthernet`
5. **Background testing**: Keep Xcode attached to see logs while app is backgrounded
