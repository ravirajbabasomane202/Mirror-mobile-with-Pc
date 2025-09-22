import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

void main() => runApp(MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    });
  }

  Future<void> _saveThemePreference(bool isDarkMode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', isDarkMode);
    setState(() {
      _isDarkMode = isDarkMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: PCMirror(onThemeChanged: _saveThemePreference),
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light().copyWith(
        primaryColor: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: AppBarTheme(
          elevation: 0,
          backgroundColor: Colors.blue,
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 20),
        ),
        textTheme: TextTheme(
          bodyMedium: TextStyle(color: Colors.black87),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.grey[200],
          hintStyle: TextStyle(color: Colors.grey[600]),
          labelStyle: TextStyle(color: Colors.black87),
          errorStyle: TextStyle(color: Colors.red),
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        primaryColor: Colors.blue,
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: AppBarTheme(
          elevation: 0,
          backgroundColor: Colors.blue,
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 20),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.grey[800],
          hintStyle: TextStyle(color: Colors.grey[400]),
          labelStyle: TextStyle(color: Colors.white70),
          errorStyle: TextStyle(color: Colors.redAccent),
        ),
      ),
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
    );
  }
}

class PCMirror extends StatefulWidget {
  final Function(bool) onThemeChanged;

  PCMirror({required this.onThemeChanged});

  @override
  State<PCMirror> createState() => _PCMirrorState();
}

class _PCMirrorState extends State<PCMirror> with TickerProviderStateMixin {
  Socket? socket;
  Uint8List? imageBytes;
  bool isConnected = false;
  double? serverScreenWidth;
  double? serverScreenHeight;
  double? monitorLeft;
  double? monitorTop;
  Timer? _keepAliveTimer;
  Timer? _reconnectTimer;
  List<int> _buffer = [];
  int? _expectedLength;
  bool _receivedScreenInfo = false;
  List<Map<String, dynamic>> monitors = [];
  int? selectedMonitorIndex;
  String? _manualIpAddress;
  String? _errorMessage;
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  String _connectionQuality = 'Unknown';
  final TextEditingController _keyboardController = TextEditingController();
  final TextEditingController _ipController = TextEditingController();
  AnimationController? _errorAnimationController;
  Animation<double>? _errorAnimation;
  bool _isAppBarVisible = true;
  double _baseScale = 1.0; // Added for zoom
  Offset _baseOffset = Offset.zero; // Added for zoom
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _errorAnimationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500),
    );
    _errorAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _errorAnimationController!, curve: Curves.easeInOut),
    );
    connectToServer();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _manualIpAddress = prefs.getString('manualIpAddress');
      _ipController.text = _manualIpAddress ?? '';
    });
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('manualIpAddress', _manualIpAddress ?? '');
  }

  bool _isValidIpAddress(String ip) {
    final RegExp ipRegex = RegExp(
        r'^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$');
    return ipRegex.hasMatch(ip);
  }

  Future<bool> _requestPermissions() async {
    if (!Platform.isAndroid) {
      return true;
    }

    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.nearbyWifiDevices,
    ].request();

    bool allGranted = statuses.values.every((status) => status.isGranted);

    if (!allGranted) {
      bool permanentlyDenied = statuses.values.any((status) => status.isPermanentlyDenied);
      if (permanentlyDenied) {
        _showError('Permissions are permanently denied. Please enable them in app settings to use discovery features.');
        openAppSettings();
      } else {
        _showError('Permissions are required for automatic discovery.');
      }
      return false;
    }
    return true;
  }

  Future<void> connectToServer({bool forceReconnect = false}) async {
    if (forceReconnect) {
      await _cleanupConnection();
    }

    setState(() {
      _errorMessage = null;
      _connectionQuality = 'Connecting';
    });

    if (_manualIpAddress != null && _manualIpAddress!.isNotEmpty) {
      if (_isValidIpAddress(_manualIpAddress!)) {
        await tryManualIpConnection();
        if (isConnected) return;
      } else {
        _showError('Invalid IP address format');
        return;
      }
    }

    bool permissionsGranted = await _requestPermissions();
    if (!permissionsGranted) {
      return;
    }

    await tryWiFiConnection();

    if (!isConnected) {
      _startReconnectTimer();
    }
  }

  Future<void> _cleanupConnection() async {
    _keepAliveTimer?.cancel();
    _reconnectTimer?.cancel();
    socket?.close();
    setState(() {
      isConnected = false;
      imageBytes = null;
      _buffer.clear();
      _receivedScreenInfo = false;
      _connectionQuality = 'Disconnected';
    });
  }

  Future<void> tryManualIpConnection() async {
    try {
      socket = await Socket.connect(_manualIpAddress!, 9999, timeout: Duration(seconds: 10));
      setState(() {
        isConnected = true;
        _connectionQuality = 'Good';
      });
      listenToSocket();
      startKeepAlive();
    } catch (e) {
      _showError('Failed to connect to IP: $e');
    }
  }

  Future<void> tryWiFiConnection() async {
    try {
      final client = MDnsClient();
      await client.start();
      await for (PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
          ResourceRecordQuery.service('_pcserver._tcp.local'))) {
        await for (SrvResourceRecord srv in client.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName))) {
          await for (IPAddressResourceRecord ip in client.lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target))) {
            socket = await Socket.connect(ip.address.host, 9999, timeout: Duration(seconds: 10));
            setState(() {
              isConnected = true;
              _connectionQuality = 'Good';
            });
            listenToSocket();
            startKeepAlive();
            client.stop();
            return;
          }
        }
      }
      client.stop();
      _showError('No Wi-Fi PC server found');
    } catch (e) {
      _showError('Wi-Fi connection failed: $e');
    }
  }

  void startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(Duration(seconds: 5), (timer) {
      if (isConnected && socket != null) {
        var keepAlive = utf8.encode('{"action":"ping"}');
        var lengthBytes = Uint8List(4)
          ..buffer.asByteData().setInt32(0, keepAlive.length, Endian.big);
        socket!.add([...lengthBytes, ...keepAlive]);
      }
    });
  }

  void _startReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      if (!isConnected) {
        connectToServer();
      } else {
        timer.cancel();
      }
    });
  }

  void listenToSocket() {
    socket!.listen(
      (data) => _handleIncomingData(data),
      onError: (error) {
        _showError('Socket error: $error');
        connectToServer(forceReconnect: true);
      },
      onDone: () {
        _showError('Connection closed by server');
        connectToServer(forceReconnect: true);
      },
    );
  }

  void _showError(String message) {
    setState(() {
      isConnected = false;
      _errorMessage = message;
      _connectionQuality = 'Poor';
      _errorAnimationController?.forward(from: 0.0);
    });
  }

  void _handleIncomingData(List<int> data) async {
    if (!isConnected) return;

    _buffer.addAll(data);

    while (_buffer.length >= 4) {
      if (_expectedLength == null) {
        _expectedLength = (_buffer[0] << 24) |
            (_buffer[1] << 16) |
            (_buffer[2] << 8) |
            _buffer[3];
        _buffer.removeRange(0, 4);
      }

      if (_buffer.length >= _expectedLength!) {
        var messageData = _buffer.sublist(0, _expectedLength!);
        _buffer.removeRange(0, _expectedLength!);

        if (!_receivedScreenInfo) {
          try {
            var infoJson = utf8.decode(messageData);
            var screenInfo = jsonDecode(infoJson);
            monitors = List<Map<String, dynamic>>.from(screenInfo['all'] ?? []);
            if (monitors.isEmpty) {
              _showError('No monitors found in screen info from server.');
              connectToServer(forceReconnect: true);
              return;
            }
            // Use the primary monitor's dimensions initially.
            serverScreenWidth = monitors[0]['width'].toDouble() * 0.5;
            serverScreenHeight = monitors[0]['height'].toDouble() * 0.5;
            monitorLeft = 0;
            monitorTop = 0;
            _receivedScreenInfo = true;
            setState(() {
              selectedMonitorIndex = 0;
              // The updateMonitorSelection call was redundant here as we've already set the correct values
              // for the first monitor. It will be called when the user changes selection.
            });
          } catch (e) {
            _showError('Failed to parse screen info: $e');
            connectToServer(forceReconnect: true);
          }
        } else {
          try {
            setState(() {
              imageBytes = Uint8List.fromList(messageData);
              _connectionQuality = 'Good';
            });
          } catch (e) {
            _showError('Invalid image data received: $e');
          }
        }

        _expectedLength = null;
      } else {
        break;
      }
    }
  }

  void updateMonitorSelection(int index) {
    if (index < 0 || index >= monitors.length) return;
    setState(() {
      selectedMonitorIndex = index;
      serverScreenWidth = monitors[index]['width'].toDouble() * 0.5;
      serverScreenHeight = monitors[index]['height'].toDouble() * 0.5;
      monitorLeft = monitors[index]['left'].toDouble() * 0.5;
      monitorTop = monitors[index]['top'].toDouble() * 0.5;
      _scale = 1.0;
      _offset = Offset.zero;
    });
    sendCommand('select_monitor', Offset.zero, Size.zero, monitorIndex: index);
  }

  void sendCommand(String action, Offset localPosition, Size containerSize, {int? monitorIndex, String? text}) {
    if (!isConnected ||
        socket == null ||
        serverScreenWidth == null ||
        serverScreenHeight == null ||
        serverScreenHeight == 0.0) {
      return;
    }

    try {
      double containerWidth = containerSize.width;
      double containerHeight = containerSize.height;

      double x = 0, y = 0;
      if (action != 'select_monitor' && action != 'keyboard') {
        double imageRatio = serverScreenWidth! / serverScreenHeight!;
        double containerRatio = containerWidth / containerHeight;

        double displayedWidth, displayedHeight;
        if (containerRatio > imageRatio) {
          displayedHeight = containerHeight;
          displayedWidth = containerHeight * imageRatio;
        } else {
          displayedWidth = containerWidth;
          displayedHeight = containerWidth / imageRatio;
        }

        double offsetX = (containerWidth - displayedWidth) / 2;
        double offsetY = (containerHeight - displayedHeight) / 2;

        // Adjust for zoom and pan
        double scaledWidth = displayedWidth * _scale;
        double scaledHeight = displayedHeight * _scale;
        double adjustedOffsetX = offsetX + _offset.dx * _scale;
        double adjustedOffsetY = offsetY + _offset.dy * _scale;

        // Check if the tap is within the image bounds
        if (localPosition.dx < adjustedOffsetX ||
            localPosition.dx > adjustedOffsetX + scaledWidth ||
            localPosition.dy < adjustedOffsetY ||
            localPosition.dy > adjustedOffsetY + scaledHeight) {
          return;
        }

        // Map the tap position to server coordinates
        x = ((localPosition.dx - adjustedOffsetX) / scaledWidth) * serverScreenWidth!;
        y = ((localPosition.dy - adjustedOffsetY) / scaledHeight) * serverScreenHeight!;
      }

      var cmd = {
        'action': action,
        'x': x,
        'y': y,
        'client_width': containerWidth,
        'client_height': containerHeight,
        'monitor_index': monitorIndex ?? selectedMonitorIndex,
        'text': text,
        'timestamp': DateTime.now().millisecondsSinceEpoch
      };

      var cmdData = utf8.encode(jsonEncode(cmd));
      var lengthBytes = Uint8List(4)
        ..buffer.asByteData().setInt32(0, cmdData.length, Endian.big);
      socket!.add([...lengthBytes, ...cmdData]);
    } catch (e) {
      _showError('Error sending command: $e');
    }
  }

  void _onNavBarTap(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _currentIndex == 0 ? _buildMainScreen() : _buildSettingsScreen(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onNavBarTap,
        backgroundColor: Theme.of(context).primaryColor,
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white70,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.computer),
            label: 'PC',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildMainScreen() {
    return Column(
      children: [
        if (_isAppBarVisible)
          AppBar(
            title: Text('PC Mirror'),
            backgroundColor: isConnected ? Colors.green : Colors.red,
            actions: [
              if (_receivedScreenInfo && monitors.length > 1)
                DropdownButton<int>(
                  value: selectedMonitorIndex,
                  items: monitors.asMap().entries.map((entry) {
                    int idx = entry.key;
                    return DropdownMenuItem<int>(
                      value: idx,
                      child: Text('Monitor ${idx + 1}', style: TextStyle(color: Colors.white)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      updateMonitorSelection(value);
                    }
                  },
                ),
              IconButton(
                icon: Icon(Theme.of(context).brightness == Brightness.dark ? Icons.light_mode : Icons.dark_mode),
                onPressed: () {
                  final isCurrentlyDark = Theme.of(context).brightness == Brightness.dark;
                  widget.onThemeChanged(!isCurrentlyDark);
                },
              ),
            ],
          ),
        if (_isAppBarVisible)
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              'Connection: $_connectionQuality',
              style: TextStyle(
                color: _connectionQuality == 'Good' ? Colors.green : Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _isAppBarVisible = !_isAppBarVisible;
                  });
                },
                onTapDown: (details) {
                  if (imageBytes != null && serverScreenWidth != null && serverScreenHeight != null) {
                    sendCommand('click', details.localPosition, constraints.biggest);
                  }
                },
                onDoubleTapDown: (details) {
                  if (imageBytes != null && serverScreenWidth != null && serverScreenHeight != null) {
                    sendCommand('double_click', details.localPosition, constraints.biggest);
                  }
                },
                onSecondaryTapUp: (details) {
                  if (imageBytes != null && serverScreenWidth != null && serverScreenHeight != null) {
                    sendCommand('right_click', details.localPosition, constraints.biggest);
                  }
                },
                onScaleStart: (details) {
                  _baseScale = _scale;
                  _baseOffset = _offset;
                },
                onScaleUpdate: (details) {
                  setState(() {
                    _scale = (_baseScale * details.scale).clamp(0.5, 3.0);

                    // Calculate the focal point in image coordinates
                    double containerWidth = constraints.biggest.width;
                    double containerHeight = constraints.biggest.height;
                    double imageRatio = serverScreenWidth! / serverScreenHeight!;
                    double containerRatio = containerWidth / containerHeight;

                    double displayedWidth, displayedHeight;
                    if (containerRatio > imageRatio) {
                      displayedHeight = containerHeight;
                      displayedWidth = containerHeight * imageRatio;
                    } else {
                      displayedWidth = containerWidth;
                      displayedHeight = containerWidth / imageRatio;
                    }

                    double offsetX = (containerWidth - displayedWidth) / 2;
                    double offsetY = (containerHeight - displayedHeight) / 2;

                    // Focal point in image coordinates
                    double focalX = (details.focalPoint.dx - offsetX - _baseOffset.dx * _baseScale) / _baseScale;
                    double focalY = (details.focalPoint.dy - offsetY - _baseOffset.dy * _baseScale) / _baseScale;

                    // Update offset to keep the focal point stable
                    _offset = Offset(
                      focalX - (focalX * details.scale) + (details.focalPoint.dx - offsetX) / _scale,
                      focalY - (focalY * details.scale) + (details.focalPoint.dy - offsetY) / _scale,
                    );

                    // Apply boundary checks
                    double maxOffsetX = (displayedWidth * (_scale - 1)) / (2 * _scale);
                    double maxOffsetY = (displayedHeight * (_scale - 1)) / (2 * _scale);
                    _offset = Offset(
                      _offset.dx.clamp(-maxOffsetX, maxOffsetX),
                      _offset.dy.clamp(-maxOffsetY, maxOffsetY),
                    );
                  });
                },
                onScaleEnd: (details) {
                  // Optional: Add snapping or inertia if desired
                },
                child: Stack(
                  children: [
                    imageBytes != null
                        ? Container(
                            width: double.infinity,
                            height: double.infinity,
                            color: Colors.black,
                            child: Transform(
                              transform: Matrix4.identity()
                                ..scale(_scale)
                                ..translate(_offset.dx, _offset.dy),
                              child: RepaintBoundary(
                                child: FittedBox(
                                  fit: BoxFit.contain,
                                  child: Image.memory(
                                    Uint8List.fromList(imageBytes!),
                                    gaplessPlayback: true,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Center(
                                        child: Text(
                                          'Error loading image',
                                          style: TextStyle(color: Colors.red, fontSize: 16),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SpinKitFadingCircle(
                                  color: Theme.of(context).primaryColor,
                                  size: 50.0,
                                ),
                                SizedBox(height: 20),
                                Text(
                                  isConnected ? 'Receiving screen...' : 'Connecting...',
                                  style: TextStyle(fontSize: 16, color: Theme.of(context).textTheme.bodyMedium!.color),
                                ),
                                if (!isConnected) ...[
                                  SizedBox(height: 20),
                                  ElevatedButton(
                                    onPressed: () => connectToServer(forceReconnect: true),
                                    child: Text('Reconnect'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                    if (_errorMessage != null)
                      Positioned(
                        bottom: 20,
                        left: 20,
                        right: 20,
                        child: FadeTransition(
                          opacity: _errorAnimation!,
                          child: Container(
                            padding: EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: Colors.white, fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 20,
                      right: 20,
                      child: FloatingActionButton(
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            builder: (context) => Container(
                              padding: EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(
                                    controller: _keyboardController,
                                    decoration: InputDecoration(
                                      labelText: 'Type on PC',
                                      border: OutlineInputBorder(),
                                    ),
                                    onSubmitted: (value) {
                                      if (value.isNotEmpty) {
                                        sendCommand('keyboard', Offset.zero, Size.zero, text: value);
                                        _keyboardController.clear();
                                      }
                                      Navigator.pop(context);
                                    },
                                  ),
                                  SizedBox(height: 10),
                                  ElevatedButton(
                                    onPressed: () {
                                      if (_keyboardController.text.isNotEmpty) {
                                        sendCommand('keyboard', Offset.zero, Size.zero, text: _keyboardController.text);
                                        _keyboardController.clear();
                                      }
                                      Navigator.pop(context);
                                    },
                                    child: Text('Send'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        child: Icon(Icons.keyboard),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsScreen() {
    return Padding(
      padding: EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Settings',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 20),
          Text(
            'Monitor Selection',
            style: TextStyle(fontSize: 18),
          ),
          if (_receivedScreenInfo)
            if (monitors.length > 1)
              DropdownButton<int>(
                value: selectedMonitorIndex,
                isExpanded: true,
                items: monitors.asMap().entries.map((entry) {
                  int idx = entry.key;
                  return DropdownMenuItem<int>(
                    value: idx,
                    child: Text('Monitor ${idx + 1}'),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    updateMonitorSelection(value);
                  }
                },
              )
            else if (monitors.isNotEmpty)
              Text(
                'Only one monitor detected.',
                style: TextStyle(color: Theme.of(context).textTheme.bodyMedium!.color!.withOpacity(0.6)),
              )
            else // monitors.isEmpty
              Text(
                'No monitors available.',
                style: TextStyle(color: Theme.of(context).textTheme.bodyMedium!.color!.withOpacity(0.6)),
              )
          else
            Text(
              'Connect to a PC to see monitor options.',
              style: TextStyle(color: Theme.of(context).textTheme.bodyMedium!.color!.withOpacity(0.6)),
            ),
          SizedBox(height: 20),
          Text(
            'Manual IP Address',
            style: TextStyle(fontSize: 18),
          ),
          TextField(
            controller: _ipController,
            decoration: InputDecoration(
              labelText: 'Enter IP address (e.g., 192.168.0.176)',
              border: OutlineInputBorder(),
              errorText: _errorMessage != null && _errorMessage!.contains('Invalid IP') ? _errorMessage : null,
            ),
            style: TextStyle(color: Theme.of(context).textTheme.bodyMedium!.color),
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            onChanged: (value) {
              _manualIpAddress = value.trim();
              _savePreferences();
              setState(() {
                _errorMessage = null;
              });
            },
          ),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              if (_manualIpAddress != null && _manualIpAddress!.isNotEmpty) {
                if (_isValidIpAddress(_manualIpAddress!)) {
                  connectToServer(forceReconnect: true);
                } else {
                  _showError('Invalid IP address format');
                }
              }
            },
            child: Text('Connect with Manual IP'),
          ),
          SizedBox(height: 20),
          SwitchListTile(
            title: Text('Dark Mode'),
            value: Theme.of(context).brightness == Brightness.dark,
            onChanged: (value) {
              widget.onThemeChanged(value);
            },
          ),
          if (_errorMessage != null && !_errorMessage!.contains('Invalid IP'))
            Padding(
              padding: EdgeInsets.only(top: 20),
              child: Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red, fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _keepAliveTimer?.cancel();
    _reconnectTimer?.cancel();
    socket?.close();
    _errorAnimationController?.dispose();
    _keyboardController.dispose();
    _ipController.dispose();
    super.dispose();
  }
}