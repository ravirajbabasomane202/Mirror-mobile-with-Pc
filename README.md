# 🖥️ PC Mirror  

**PC Mirror** is a cross-platform application that enables **real-time screen mirroring** and **remote control of a PC** from a mobile device over Wi-Fi.  

It consists of:  
- 🐍 **Python server** (`pc_server.py`) running on the PC.  
- 📱 **Flutter client** (`main.dart`) for Android & iOS.  

Supports **multi-monitor setups**, **touch gestures (tap, double-tap, long-press)**, **keyboard input**, and **pinch-to-zoom** for enhanced control.  

---

## 📑 Table of Contents
- [✨ Features](#-features)  
- [🏗 Architecture](#-architecture)  
- [⚙️ Prerequisites](#%EF%B8%8F-prerequisites)  
- [📥 Installation](#-installation)  
  - [🔹 Server Setup (Python)](#-server-setup-python)  
  - [🔹 Client Setup (Flutter)](#-client-setup-flutter)  
- [🚀 Usage](#-usage)  
- [⚙️ Configuration](#%EF%B8%8F-configuration)  
- [🐞 Troubleshooting](#-troubleshooting)  
- [🤝 Contributing](#-contributing)  
- [📜 License](#-license)  

---

## ✨ Features  
✔ Real-Time Screen Mirroring with minimal latency  
✔ Multi-Monitor Support with seamless switching  
✔ Touch Interactions: tap (left-click), double-tap (double-click), long-press (right-click)  
✔ Keyboard Input from mobile device  
✔ Pinch-to-Zoom and Pan (0.5x–3x)  
✔ Automatic mDNS Discovery + Manual IP connection  
✔ Dark/Light Mode toggle  
✔ Connection Status indicators (Good/Poor/Connecting/Disconnected)  
✔ Error Handling with reconnection attempts  

---

## 🏗 Architecture  

### 🔹 Server (`pc_server.py`)  
- **Python-based** using:  
  - `mss` → screen capture  
  - `pyautogui` → mouse/keyboard control  
  - `zeroconf` → mDNS service discovery  
- Captures screen (10 FPS, JPEG 50% quality, 50% resolution)  
- Handles mouse, keyboard, and monitor control  
- Advertises service as `_pcserver._tcp.local`  

### 🔹 Client (`main.dart`)  
- **Flutter-based** for Android & iOS  
- Connects via **Wi-Fi** (mDNS discovery or manual IP)  
- Supports gestures: tap, double-tap, long-press, pinch-to-zoom, pan  
- Settings screen: monitor selection, manual IP, theme switch  

---

## ⚙️ Prerequisites  

### 🖥 Server (PC)  
- Python **3.8+**  
- OS: Windows, macOS, or Linux  
- Python packages:  
  ```bash
  pip install mss pyautogui Pillow zeroconf
