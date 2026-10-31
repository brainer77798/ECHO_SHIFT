"""
ECHO//SHIFT - Authoritative LAN Game Server Runner
"""

import sys
import os
import socket
import argparse
import time

sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

from game.server_world import GameServer
from settings import DEFAULT_PORT, VERSION


def get_local_ip_addresses():
    ips = []
    try:
        hostname = socket.gethostname()
        for ip in socket.gethostbyname_ex(hostname)[2]:
            if not ip.startswith("127."):
                ips.append(ip)
    except Exception:
        pass
    if not ips:
        ips.append("127.0.0.1")
    return ips


def main():
    parser = argparse.ArgumentParser(description="ECHO//SHIFT LAN Server")
    parser.add_argument("--host", default="0.0.0.0", help="Host address to bind (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT, help=f"Port (default: {DEFAULT_PORT})")
    parser.add_argument("--level", type=int, default=1, help="Starting level (1-3, default: 1)")
    args = parser.parse_args()

    print("==================================================")
    print(f"  ECHO//SHIFT v{VERSION} - DEDICATED LAN SERVER")
    print("==================================================")
    print(f"Starting simulation on port {args.port}...")
    local_ips = get_local_ip_addresses()
    print("Clients can connect using one of these LAN IP addresses:")
    for ip in local_ips:
        print(f"  -> {ip}:{args.port}")
    print("Press Ctrl+C to stop the server.")
    print("==================================================")

    server = GameServer(host=args.host, port=args.port, level=args.level)
    try:
        server.start(background=False)
    except KeyboardInterrupt:
        print("\nShutting down server cleanly...")
    finally:
        server.stop()
        print("Server stopped.")


if __name__ == "__main__":
    main()
