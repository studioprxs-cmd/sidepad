#!/usr/bin/env python3
"""Probe a real AirPlay receiver over LAN or `adb forward tcp:17000 tcp:7000`."""
import argparse
import json
import plistlib
import socket


def probe(host, port):
    with socket.create_connection((host, port), timeout=3) as stream:
        stream.settimeout(3)
        stream.sendall(b'GET /info RTSP/1.0\r\nCSeq: 1\r\nUser-Agent: AirPlay/320.20\r\nContent-Length: 0\r\n\r\n')
        response = bytearray()
        while b'\r\n\r\n' not in response:
            chunk = stream.recv(4096)
            if not chunk:
                raise ValueError('EOF before RTSP headers')
            response.extend(chunk)
            if len(response) > 65536:
                raise ValueError('Oversized RTSP headers')
        header, body = bytes(response).split(b'\r\n\r\n', 1)
        lines = header.decode('ascii').split('\r\n')
        if lines[0] != 'RTSP/1.0 200 OK':
            raise ValueError('Unexpected AirPlay status: ' + lines[0])
        headers = dict(line.split(':', 1) for line in lines[1:])
        length = int(headers['Content-Length'])
        if not 0 < length <= 1024 * 1024:
            raise ValueError('Invalid AirPlay info length')
        while len(body) < length:
            chunk = stream.recv(min(8192, length - len(body)))
            if not chunk:
                raise ValueError('Truncated AirPlay info')
            body += chunk
        info = plistlib.loads(body[:length])
        if not info.get('name', '').startswith('SidePad'):
            raise ValueError('The receiver is not SidePad')
        if not info.get('deviceID') or not info.get('features'):
            raise ValueError('Missing AirPlay identity or capabilities')
        return {k: info[k] for k in ['name', 'deviceID', 'model', 'features', 'statusFlags'] if k in info}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=17000)
    args = parser.parse_args()
    print(json.dumps(probe(args.host, args.port), ensure_ascii=False, indent=2))
