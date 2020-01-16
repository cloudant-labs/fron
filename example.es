#!/usr/bin/env escript
%%! -pa ebin/ deps/jiffy/ebin

main(_) ->
    {ok, Conn} = fron:connect("tcp://127.0.0.1:8443"),
    {ok, Stream} = fron:new_stream(Conn),

    Msg1 = {[{<<"foo">>, true}]},
    fron:send(Stream, Msg1),
    {ok, Msg1} = fron:recv(Stream),

    Msg2 = {[{<<"baz">>, bigstring(70000)}]},
    fron:send(Stream, Msg2),
    {ok, Msg2} = fron:recv(Stream).


bigstring(Size) when is_integer(Size), Size > 0 ->
    bigstring(Size, []).

bigstring(0, Acc) ->
    list_to_binary(Acc);
bigstring(Size, Acc) ->
    bigstring(Size - 1, [$a + (Size rem 26) | Acc]).
