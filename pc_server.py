import socket
import threading
import pyautogui
import mss
import struct
import json
import time
from PIL import Image
import io
from zeroconf import ServiceInfo, Zeroconf
import queue
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

HOST = "0.0.0.0"
PORT = 9999

class PCServer:
    def __init__(self):
        self.zeroconf = Zeroconf()
        self.clients = []
        self.client_lock = threading.Lock()
        self.command_queue = queue.Queue()
        self.running = True

    def get_screen_info(self):
        try:
            with mss.mss() as sct:
                monitors = sct.monitors
                if not monitors:
                    logging.error("Could not find any monitors.")
                    return None
                
                # The first monitor in mss is the "all-in-one" virtual monitor.
                # The rest are individual monitors.
                all_individual_monitors = monitors[1:]

                # If no individual monitors are found, use the all-in-one monitor.
                if not all_individual_monitors:
                    logging.warning("Only a single 'all-in-one' monitor description found. Using it as the only monitor.")
                    all_individual_monitors = [monitors[0]]

                primary_monitor = all_individual_monitors[0]

                return {
                    'primary': primary_monitor,
                    'all': all_individual_monitors,
                    'total_width': monitors[0]['width'],
                    'total_height': monitors[0]['height']
                }
        except Exception as e:
            logging.error(f"Error getting screen info: {e}", exc_info=True)
            return None

    def handle_client(self, conn, addr):
        logging.info(f"New client connected: {addr}")
        with self.client_lock:
            self.clients.append(conn)

        screen_info = self.get_screen_info()
        if screen_info is None:
            logging.error(f"Failed to get screen info for {addr}. Closing connection.")
            with self.client_lock:
                if conn in self.clients:
                    self.clients.remove(conn)
            conn.close()
            return

        selected_monitor_index = 0
        
        try:
            info_data = json.dumps(screen_info).encode()
            conn.sendall(struct.pack('>I', len(info_data)) + info_data)
            
            with mss.mss() as sct:
                while self.running:
                    start_time = time.time()
                    try:
                        # Validate monitor index to prevent crash from malicious/buggy client
                        if not (0 <= selected_monitor_index < len(screen_info['all'])):
                            logging.warning(f"Invalid monitor index {selected_monitor_index} received. Defaulting to 0.")
                            selected_monitor_index = 0
                        
                        monitor = screen_info['all'][selected_monitor_index]
                        screenshot = sct.grab(monitor)
                        
                        img = Image.frombytes("RGB", screenshot.size, screenshot.bgra, "raw", "BGRX")
                        new_size = (int(screenshot.width * 0.5), int(screenshot.height * 0.5))
                        img = img.resize(new_size, Image.Resampling.LANCZOS)
                        
                        img_byte_arr = io.BytesIO()
                        img.save(img_byte_arr, format='JPEG', quality=50)
                        img_bytes = img_byte_arr.getvalue()
                        
                        with self.client_lock:
                            if conn in self.clients:
                                try:
                                    conn.sendall(struct.pack('>I', len(img_bytes)) + img_bytes)
                                except (BrokenPipeError, ConnectionResetError):
                                    logging.warning(f"Client {addr} disconnected while sending image.")
                                    break
                        
                        conn.settimeout(1.0)
                        try:
                            length_data = conn.recv(4)
                            if length_data and len(length_data) == 4:
                                cmd_length = struct.unpack('>I', length_data)[0]

                                # Add a sanity check for command length to prevent OOM from malicious client
                                if cmd_length > 1024 * 1024: # 1MB limit for commands
                                    logging.warning(f"Command from {addr} too large: {cmd_length} bytes. Disconnecting.")
                                    break

                                cmd_data = b''
                                while len(cmd_data) < cmd_length:
                                    chunk = conn.recv(min(4096, cmd_length - len(cmd_data)))
                                    if not chunk:
                                        logging.warning(f"Client {addr} disconnected while sending command data.")
                                        raise ConnectionAbortedError("Client disconnected")
                                    cmd_data += chunk
                                
                                if cmd_data:
                                    cmd = json.loads(cmd_data.decode())
                                    logging.info(f"Received command from {addr}: {cmd}")
                                    
                                    action = cmd.get('action') # Use .get for safety
                                    if action == 'select_monitor':
                                        new_index = cmd.get('monitor_index')
                                        if isinstance(new_index, int):
                                            selected_monitor_index = new_index
                                            logging.info(f"Switched to monitor {selected_monitor_index}")
                                        else:
                                            logging.warning(f"Invalid monitor_index received: {new_index}")
                                        continue
                                    elif action == 'ping':
                                        continue
                                    elif action == 'keyboard':
                                        text_to_write = cmd.get('text', '')
                                        if text_to_write:
                                            pyautogui.write(text_to_write)
                                            logging.info(f"Typed: {text_to_write}")
                                        continue
                                    
                                    x = cmd.get('x')
                                    y = cmd.get('y')

                                    if x is None or y is None:
                                        logging.warning(f"Command '{action}' received without coordinates from {addr}.")
                                        continue

                                    monitor = screen_info['all'][selected_monitor_index]
                                    # The client sends coordinates based on a 0.5 scaled image. We scale it back up (x2).
                                    scale_x = 2.0
                                    scale_y = 2.0
                                    actual_x = max(0, min(int(x * scale_x) + monitor['left'], monitor['left'] + monitor['width'] - 1))
                                    actual_y = max(0, min(int(y * scale_y) + monitor['top'], monitor['top'] + monitor['height'] - 1))
                                    
                                    logging.info(f"Mapping: ({x}, {y}) -> ({actual_x}, {actual_y})")
                                    if action == 'click':
                                        pyautogui.click(actual_x, actual_y)
                                        logging.info(f"Clicked at: {actual_x}, {actual_y}")
                                    elif action == 'double_click':
                                        pyautogui.doubleClick(actual_x, actual_y)
                                        logging.info(f"Double clicked at: {actual_x}, {actual_y}")
                                    elif action == 'right_click':
                                        pyautogui.rightClick(actual_x, actual_y)
                                        logging.info(f"Right clicked at: {actual_x}, {actual_y}")
                        except socket.timeout:
                            pass
                        except (json.JSONDecodeError, KeyError, TypeError) as e:
                            logging.error(f"Error processing command from {addr}: {e}")
                        except (ConnectionAbortedError, ConnectionResetError, BrokenPipeError) as e:
                            logging.warning(f"Client {addr} connection error: {e}")
                            break # Exit while loop
                        except Exception as e:
                            logging.error(f"Unexpected command error from {addr}: {e}", exc_info=True)
                            break
                        
                        elapsed = time.time() - start_time
                        time.sleep(max(0, 0.1 - elapsed))
                        
                    except Exception as e:
                        logging.error(f"Error in client handler for {addr}: {e}", exc_info=True)
                        break
        finally:
            with self.client_lock:
                if conn in self.clients:
                    self.clients.remove(conn)
            conn.close()
            logging.info(f"Client disconnected: {addr}")

    def start_tcp_server(self):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind((HOST, PORT))
            s.listen()
            logging.info(f"TCP server listening on {HOST}:{PORT}...")
            while self.running:
                try:
                    conn, addr = s.accept()
                    threading.Thread(target=self.handle_client, args=(conn, addr), daemon=True).start()
                except Exception as e:
                    logging.error(f"Server error: {e}")
                    break

    def start(self):
        info = ServiceInfo(
            "_pcserver._tcp.local.",
            "PCServer._pcserver._tcp.local.",
            addresses=[socket.inet_aton(socket.gethostbyname(socket.gethostname()))],
            port=PORT,
            properties={},
            server="pcserver.local.",
        )
        self.zeroconf.register_service(info)
        
        try:
            self.start_tcp_server()
        finally:
            self.zeroconf.unregister_service(info)
            self.zeroconf.close()

    def stop(self):
        self.running = False
        with self.client_lock:
            for conn in self.clients:
                conn.close()
            self.clients.clear()

def main():
    server = PCServer()
    try:
        server.start()
    except KeyboardInterrupt:
        server.stop()
        logging.info("Server stopped")

if __name__ == "__main__":
    main()