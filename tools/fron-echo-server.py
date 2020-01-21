#!/usr/bin/env python

import socket
import struct


HOST = "127.0.0.1"
PORT = 8443

def send_msg(sock, stream_id, msg_bytes):
    frames = []
    for i in range(0, len(msg_bytes), 65530):
        frames.append([0, msg_bytes[i:i+65530]])
    # set bit 0 on first frame
    frames[0][0] += 1
    # set bit 1 on last frame
    frames[-1][0] += 2
    # create binary frame
    for (flags, data) in frames:
        # header format is: uint32_t, uint16_t, uint8_t (all big endian)
        header = struct.pack(">HIB", len(data) + 5, stream_id, flags)
        print "%r %r" % (header, data)
        sock.send(header)
        sock.send(data)


def recv_msgs(sock):
    streams = {}
    while True:
        frame_len = sock.recv(2)
        if not frame_len:
            return
        # Assume sync and no socket failures
        assert len(frame_len) == 2

        # Struct always returns a tuple which leads to the [0]
        frame_len = struct.unpack(">H", frame_len)[0]
        msg_bytes = sock.recv(frame_len)

        # Assume sync and no socket failures
        assert len(msg_bytes) == frame_len
        (stream_id, flags) = struct.unpack(">IB", msg_bytes[:5])
        msg_data = msg_bytes[5:]

        # We're starting a new message
        if flags & 1 == 1:
            assert stream_id not in streams
            streams[stream_id] = []

        streams[stream_id].append(msg_data)

        # Ending a message, this could be a single frame message here
        if flags & 2 == 2:
            assert stream_id in streams
            msg_data = streams.pop(stream_id)
            msg = "".join(msg_data)
            print "Received: %d : %s" % (stream_id, json.dumps(msg))
            send_msg(sock, stream_id, msg)


def main():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind((HOST, PORT))
    sock.listen(1)
    while True:
        conn, addr = sock.accept()
        recv_msgs(conn)


if __name__ == "__main__":
    main()
