#!/usr/bin/env escript
%%! -pa ebin/ deps/jiffy/ebin

main(_) ->
    {ok, Conn} = fron:connect("tcp://127.0.0.1:8443"),
    {ok, Stream} = fron:new_stream(Conn),
    fron:send(Stream, {[{foo, true}]}),
    {ok, Msg} = fron:recv(Stream),
    io:format("Received: ~p~n", [Msg]).
