import socket, sys, time
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("0.0.0.0", 18194))
while True:
    data, addr = s.recvfrom(2048)
    line = data.decode("utf8", "replace").rstrip("\n")
    print(f"{addr[0]} | {line}", flush=True)
