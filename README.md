fron - Framed JSON over TLS/TCP
===

Fron is a simple protocol for multiplexing JSON messages over TCP.

Protocol Basics
---

Fron relies on having a basic stream oriented guaranteed connection (i.e.,
TCP semantics). A Fron connection is a 1:1 mapping to an underlying TCP/SSL
socket. SSL/TCP connection negotiation is left up to the implementation.
There are no ALPN requirements as part of Fron itself.

Fron sends JSON messages by splitting up JSON into discrete packets that
can then be multiplexed over a given connection. Fron only guarantees
that a JSON message will be deconstructed and reconstructed on the remote
end.

Sending Protocol
---

An implementation of a Fron sender does the following to send a JSON message:

1. Encode JSON as binary
2. Split the binary into 1 or more frames
3. Send each frame to the remote

A frame is defined as:

* 2 byte unsigned big-endian frame length
* 4 byte unsigned big-endian stream id
* 1 byte message flags
* Up to 64KiB - 5 bytes of binary data

There are two flags defined:

message_start - bit 0 is set to 1
message_end - bit 1 is set to 1

In pseudo code this might look like:

```python
def send_mesg(sock, stream_id, msg):
    msg_bytes = json.dumps(msg)
    frames = []
    for i in range(0, len(msg_bytes), 65535-7):
        frames.append([0, msg_bytes[i:i+65535-7]])
    # set bit 0 on first frame
    frames[0][0] += 1
    # set bit 1 on last frame
    frames[-1][0] += 2
    # create binary frame
    for (flags, data) in frames:
        # header format is: uint32_t, uint16_t, uint8_t (all big endian)
        header = struct.pack(">H>IB", len(data) + 7, stream_id, flags)
        sock.send(header + data)
```

Receive Protocol
---

A Fron receiver reads frames off the connection to reconstruct JSON
messages that can then be handled by the application. This basically means
that a Fron receiver will have some sort of associative container that
holds all partially received messages which can then are then combined
and returned as JSON messages.

In pseudo code that might look something like such:

```python
def recv_mesgs(sock):
    streams = {}
    while True:
        frame_len = sock.read(2)
        # Assume sync and no socket failures
        assert len(frame_len) == 2

        # Struct always returns a tuple which leads to the [0]
        frame_len = struct.unpack(">H", frame_len)[0]
        msg_bytes = sock.read(frame_len)

        # Assume sync and no socket failures
        assert len(msg_bytes) == frame_len
        (stream_id, flags) = struct.unpack(">IB", msg_bytes[:5])
        msg_data = msg_bytes[5:]

        # We're starting a new message
        if flags & 1 == 1:
            assert stream_id not in messages
            messages[stream_id] = []

        messages[stream_id].append(msg_data)

        # Ending a message, this could be a single frame message here
        if flags & 2 == 2:
            assert stream_id in messages
            msg_data = messages.pop(stream_id)
            msg = json.loads("".join(msg_data))
            do_something_with_message(msg)
```

Implementation Notes
---

The pseudocode above includes reading the two-byte length prefix off the
wire to show the entire protocol. Many languages and networking libraries
natively support length prefixed messages. As long as they follow the
network-oder-is-big-endian rule then that part of the protocol can be
elided from the Fron implementation.

On the sending side there's no fairness or concurrency included. In a real
Fron implementation there are lots of different approaches that could be
used. For instance, having a list of messages that are in flight so that
the implementation can send parts of each message. This prevents head-of-line
blocking when a client wants to mix sending messages of varying lengths.

Depending on application requirements, Fron senders may also want to
provide options for enabling and disabling Naggle's algorithm to improve
message packing between TCP level packets.



