# PingMonitor

A professional macOS menu bar application for real-time network monitoring with beautiful graphs and detailed ping history.

![PingMonitor Screenshot](screenshot.png)

## Features

### 🎯 Core Functionality
- **Real-time ping monitoring** of multiple hosts simultaneously
- **Beautiful menu bar status** with colored dot and ping time
- **Professional dropdown interface** with tabs, graphs, and history
- **Smart default gateway detection** - automatically finds your router IP

### 📊 Visual Monitoring
- **Interactive host tabs** - Google DNS, Cloudflare, and your Default Gateway
- **Real-time line graphs** with smooth animations and data points
- **Detailed history table** with time, host, ping times, and status
- **Color-coded status indicators** (Green/Yellow/Red/Gray)

### ⚙️ User Interface
- **Left-click**: Opens full monitoring interface
- **Right-click**: Quick context menu with host selection and settings
- **Settings gear**: Access to configuration and export options
- **Clean, native macOS design** following Apple's design guidelines

### 🌐 Monitored Hosts
- **Google DNS** (8.8.8.8) - Internet connectivity
- **Cloudflare** (1.1.1.1) - Alternative DNS monitoring
- **Default Gateway** (auto-detected) - Local network connectivity

## Installation

1. Download the latest release
2. Move PingMonitor.app to your Applications folder
3. Launch the app - it will appear in your menu bar
4. Grant network permissions when prompted

## Usage

### Basic Monitoring
- The menu bar shows a colored status dot and current ping time
- **Green**: Good connection (<50ms)
- **Yellow**: Slow connection (50-150ms)
- **Red**: Poor connection (>150ms)
- **Gray**: Connection timeout/error

### Interface Navigation
- **Left-click** the menu bar icon to open the full interface
- **Right-click** for quick host switching and settings
- **Click host tabs** to switch between monitored servers
- **Use the gear menu** for settings and export options

### Host Selection
Switch between monitoring different hosts:
- **Google**: General internet connectivity
- **Cloudflare**: Alternative DNS performance
- **Default Gateway**: Local network health

## Technical Details

### Requirements
- macOS 13.0 or later
- Network permissions for ping operations

### Architecture
- **SwiftUI** for modern, native interface
- **Real-time ping monitoring** using system ping command
- **Multi-host concurrent monitoring** with separate timers
- **Data persistence** with automatic history management
- **Native menu bar integration** with proper click handling

### Performance
- **Lightweight**: Minimal CPU and memory usage
- **Efficient**: Smart ping scheduling and data management
- **Responsive**: Non-blocking UI with background ping operations

## Development

### Building from Source
```bash
git clone https://github.com/yourusername/pingmonitor.git
cd pingmonitor
swiftc PingMonitor.swift -o PingMonitor
./PingMonitor
```

### Project Structure
```
PingMonitor/
├── PingMonitor.swift      # Main application code
├── README.md             # This file
├── LICENSE              # MIT License
└── screenshot.png       # App screenshot
```

## Roadmap

### Planned Features
- [ ] Host management (add/edit/remove custom hosts)
- [ ] Configurable ping intervals and thresholds
- [ ] Data export (CSV/JSON formats)
- [ ] Notification system for connection issues
- [ ] Historical data persistence
- [ ] Network performance statistics

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with SwiftUI and AppKit
- Inspired by professional network monitoring tools
- Designed for macOS menu bar integration

---

**PingMonitor** - Professional network monitoring for macOS