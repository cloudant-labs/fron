% Licensed under the Apache License, Version 2.0 (the "License"); you may not
% use this file except in compliance with the License. You may obtain a copy of
% the License at
%
%   http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
% License for the specific language governing permissions and limitations under
% the License.
-module(fron).


-export([
    connect/1,
    connect/2,
    close/1,

    new_stream/1,

    send/2,
    recv/1,
    recv/2,
    recv/3
]).


-define(MAX_PKT_LEN, 65530).


connect(URI) ->
    connect(URI, []).


-spec connect(http_uri:uri(), fron_socket:conn_opts()) ->
    {ok, fron_conn:conn()} | {error, any()}.
connect(URI, Options) ->
    case http_uri:parse(URI) of
        {ok, {tcp, _, Host, Port, _, _}} ->
            fron_conn:start_link({gen_tcp, Host, Port}, Options);
        {ok, {ssl, _, Host, Port, _, _}} ->
            fron_conn:start_link({ssl, Host, Port}, Options);
        {ok, {Scheme, _, _, _, _, _}} ->
            {error, {invalid_scheme, Scheme}};
        {error, _} = Error ->
            Error
    end.


close(Connection) ->
    fron_conn:close(Connection).


new_stream(Connection) ->
    fron_conn:new_stream(Connection).


send({fron_stream, Socket, StreamId, _Ref}, Message) ->
    lists:foreach(fun({Flags, Data}) ->
        IoData = [<<StreamId:32/integer-unsigned-big, Flags:8>>, Data],
        fron_socket:send(Socket, IoData)
    end, prepare_packets(Message)).


recv(Stream) ->
    recv(Stream, 5000, []).


recv(Stream, Timeout) ->
    recv(Stream, Timeout, []).


recv({fron_stream, _Socket, _StreamId, Ref}, Timeout, Options) ->
    receive
        {fron_msg, Ref, MsgAcc} ->
            {ok, jiffy:decode(lists:reverse(MsgAcc), Options)}
    after Timeout ->
        {error, timeout}
    end.



prepare_packets(Message) ->
    Bin = iolist_to_binary(jiffy:encode(Message)),
    Packets1 = split(Bin),
    Packets2 = set_message_start(Packets1),
    set_message_end(Packets2).


set_message_start([{Flags, Data} | Rest]) ->
    [{Flags + 1, Data} | Rest].


set_message_end([{Flags, Data}]) ->
    [{Flags + 2, Data}];
set_message_end([Packet | RestPackets]) ->
    [Packet | set_message_end(RestPackets)].


split(Bin) when is_binary(Bin), size(Bin) =< ?MAX_PKT_LEN ->
    [{0, Bin}];
split(Bin) when is_binary(Bin) ->
    <<Prefix:?MAX_PKT_LEN/binary, Suffix/binary>> = Bin,
    [{0, Prefix} | split(Suffix)].
