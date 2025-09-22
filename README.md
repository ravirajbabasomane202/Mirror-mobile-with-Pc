PC Mirror
 
PC Mirror is a cross-platform application that enables real-time screen mirroring and remote control of a PC from a mobile device over a Wi-Fi network. The project consists of a Python-based server (pc_server.py) running on the PC and a Flutter-based mobile client (main.dart) for Android and iOS devices. It supports multi-monitor setups, touch-based interactions (click, double-click, right-click), keyboard input, and pinch-to-zoom functionality for an enhanced user experience.
Table of Contents

Features
Architecture
Prerequisites
Installation
Server Setup (Python)
Client Setup (Flutter)


Usage
Configuration
Troubleshooting
Contributing
License

Features

Real-Time Screen Mirroring: Stream your PC's screen to your mobile device with minimal latency.
Multi-Monitor Support: Switch between multiple monitors seamlessly via a dropdown menu.
Touch Interactions: Perform left-click, double-click, and right-click actions using tap, double-tap, and long-press gestures.
Keyboard Input: Send text input to the PC from the mobile device's virtual keyboard.
Pinch-to-Zoom and Pan: Zoom in/out and pan the mirrored screen for precise control.
Automatic Discovery: Uses mDNS (multicast DNS) to automatically discover the server on the local network.
Manual IP Connection: Connect to the server using a manually specified IP address.
Dark/Light Mode: Toggle between dark and light themes for better visibility.
Connection Status: Visual indicators for connection quality (Good/Poor/Connecting/Disconnected).
Error Handling: Robust error messages and automatic reconnection attempts.

Architecture
The project is divided into two main components:

Server (pc_server.py):

Written in Python using libraries like mss for screen capture, pyautogui for mouse/keyboard control, and zeroconf for mDNS service discovery.
Runs on the PC, captures the screen at 10 FPS, compresses it as JPEG (50% quality, 50% resolution), and sends it to connected clients.
Handles client commands for mouse clicks, keyboard input, and monitor selection.
Advertises itself on the network using mDNS under the service type _pcserver._tcp.local.


Client (main.dart):

Built with Flutter for cross-platform compatibility (Android and iOS).
Connects to the server via Wi-Fi using mDNS discovery or manual IP input.
Displays the streamed screen, supports touch gestures (tap, double-tap, long-press, pinch-to-zoom, pan), and sends commands to the server.
Features a settings screen for monitor selection, manual IP configuration, and theme switching.



Prerequisites
Server (PC)

Python 3.8 or higher
Operating System: Windows, macOS, or Linux
Required Python packages:
mss
pyautogui
Pillow
zeroconf



Client (Mobile)

Flutter 3.0 or higher
Dart SDK
Android Studio or Xcode for mobile development
Mobile device running Android 5.0+ or iOS 12.0+
Required Flutter packages:
multicast_dns: ^0.3.2+7
shared_preferences: ^2.2.2
permission_handler: ^11.0.0
flutter_spinkit: ^5.2.0



Installation
Server Setup (Python)

Clone the Repository:
git clone https://github.com/your-username/pc-mirror.git
cd pc-mirror


Install Python Dependencies:Create a virtual environment (optional but recommended) and install the required packages:
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install mss pyautogui Pillow zeroconf


Run the Server:Start the server by running the pc_server.py script:
python pc_server.py

The server will listen on port 9999 and advertise itself via mDNS as _pcserver._tcp.local.


Client Setup (Flutter)

Clone the Repository (if not already done):
git clone https://github.com/your-username/pc-mirror.git
cd pc-mirror/client


Install Flutter Dependencies:Ensure you have Flutter installed, then install the required packages:
flutter pub get


Update pubspec.yaml:Ensure the following dependencies are included in pubspec.yaml:
dependencies:
  flutter:
    sdk: flutter
  multicast_dns: ^0.3.2+7
  shared_preferences: ^2.2.2
  permission_handler: ^11.0.0
  flutter_spinkit: ^5.2.0


Run the App:Connect a mobile device or emulator, then run the Flutter app:
flutter run



Usage

Start the Server:

Run pc_server.py on your PC. Ensure the PC is on the same Wi-Fi network as the mobile device.
The server will log its status and client connections.


Launch the Client:

Open the PC Mirror app on your mobile device.
The app will attempt to discover the server via mDNS. If successful, it will connect automatically.
Alternatively, go to the Settings tab, enter the PC's IP address (e.g., 192.168.0.176), and tap Connect with Manual IP.


Interact with the PC:

View Screen: The PC's screen will be mirrored on your mobile device.
Mouse Control:
Tap: Left-click.
Double-tap: Double-click.
Long-press: Right-click.


Zoom and Pan: Use pinch gestures to zoom in/out (0.5x to 3x) and drag to pan the screen.
Keyboard Input: Tap the keyboard icon (bottom-right) to open a text input field and send text to the PC.
Monitor Selection: If multiple monitors are detected, use the dropdown in the app bar or settings to switch monitors.


Toggle Theme:

In the app bar or settings, toggle between light and dark modes.


Monitor Connection:

The app displays the connection status (Good, Poor, Connecting, Disconnected) at the top.
If disconnected, tap Reconnect or check the manual IP settings.



Configuration

Server:

Port: The server listens on port 9999 by default. Modify the PORT constant in pc_server.py if needed.
Frame Rate: The server captures frames at ~10 FPS. Adjust the time.sleep(max(0, 0.1 - elapsed)) line in pc_server.py for a different frame rate.
Image Quality: The server compresses images to 50% resolution and 50% JPEG quality. Modify the img.save(img_byte_arr, format='JPEG', quality=50) line in pc_server.py to adjust quality.


Client:

Manual IP: Set a manual IP address in the Settings tab to bypass mDNS discovery.
Permissions: On Android, grant Location and Nearby Wi-Fi Devices permissions for mDNS discovery.
Zoom Limits: The zoom scale is clamped between 0.5x and 3x. Adjust the .clamp(0.5, 3.0) in main.dart (onScaleUpdate) to change the range.



Troubleshooting

Connection Issues:

Ensure the PC and mobile device are on the same Wi-Fi network.
Check if the server is running and listening on port 9999 (netstat -an | grep 9999).
If mDNS discovery fails, use the manual IP option with the PC's IP address (find it using ipconfig on Windows or ifconfig/ip addr on Linux/macOS).
Verify that firewall settings allow incoming connections on port 9999.


Zoom/Pan Not Working:

Ensure you are using a pinch gesture with two fingers for zooming.
Check that the screen is fully loaded (imageBytes is not null).
If coordinates seem off, verify the server and client are using the same scaling factor (0.5x for screen dimensions).


Image Not Displaying:

Check server logs for errors in screen capture (mss) or image encoding.
Ensure the client has sufficient memory to handle the image stream.
Try increasing the JPEG quality in pc_server.py if the image is corrupted.


Permissions Denied:

On Android, go to app settings and enable Location and Nearby Wi-Fi Devices permissions.
If permissions are permanently denied, the app will prompt to open app settings.


Logs:

Server logs are output to the console with timestamps and levels (INFO, ERROR).
Client errors are displayed as pop-up messages at the bottom of the screen.



Contributing
Contributions are welcome! To contribute:

Fork the repository.
Create a feature branch (git checkout -b feature/your-feature).
Commit your changes (git commit -m 'Add your feature').
Push to the branch (git push origin feature/your-feature).
Open a pull request with a detailed description of your changes.

Please ensure your code follows the existing style and includes tests where applicable.
License
This project is licensed under the MIT License. See the LICENSE file for details.

Built with ❤️ by [Your Name/Team Name]
