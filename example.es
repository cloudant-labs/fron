#!/usr/bin/env escript

main(_) ->
    {ok, Conn} = fron:connect("tcp://127.0.0.1:8443"),
    {ok, Stream} = fron:new_stream(Conn),

    Msg1 = generate_protobuf_msg(),
    fron:send(Stream, Msg1),
    {ok, Msg1} = fron:recv(Stream).
