"""A minimal authenticated HTTP CONNECT proxy, for proving the fetcher end to end.

Usage: python3 proxy.py PORT USER PASSWORD LOGFILE
Answers 407 with a Basic challenge until Proxy-Authorization matches, then tunnels.
"""
import base64
import socket
import sys
import threading

port, user, password, logfile = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
expected = "Basic " + base64.b64encode(f"{user}:{password}".encode()).decode()


def log(line):
    with open(logfile, "a") as f:
        f.write(line + "\n")


def pipe(src, dst):
    try:
        while True:
            data = src.recv(65536)
            if not data:
                break
            dst.sendall(data)
    except OSError:
        pass
    finally:
        for s in (src, dst):
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass


def handle(client):
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = client.recv(4096)
        if not chunk:
            client.close()
            return
        buf += chunk
    head = buf.split(b"\r\n\r\n", 1)[0].decode("latin-1").split("\r\n")
    method, target, _ = head[0].split(" ", 2)
    headers = {k.strip().lower(): v.strip() for k, v in (h.split(":", 1) for h in head[1:] if ":" in h)}
    authorized = headers.get("proxy-authorization") == expected
    log(f"{method} {target} authorized={authorized}")
    if method != "CONNECT":
        client.sendall(b"HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\n\r\n")
        client.close()
        return
    if not authorized:
        client.sendall(b'HTTP/1.1 407 Proxy Authentication Required\r\nProxy-Authenticate: Basic realm="test"\r\nContent-Length: 0\r\n\r\n')
        client.close()
        return
    host, p = target.rsplit(":", 1)
    upstream = socket.create_connection((host, int(p)))
    client.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
    threading.Thread(target=pipe, args=(client, upstream), daemon=True).start()
    pipe(upstream, client)


server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", port))
server.listen(16)
log(f"listening on {port}")
while True:
    conn, _ = server.accept()
    threading.Thread(target=handle, args=(conn,), daemon=True).start()
