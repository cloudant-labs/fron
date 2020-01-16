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
-module(fron_conn).
-behavior(gen_server).

-export([
    start_link/2,
    close/1,
    new_stream/1
]).

-export([
    init/1,
    terminate/2,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    code_change/3
]).


-define(RETURN(Arg), throw({?MODULE, return, Arg})).


start_link(ConnInfo, Options) ->
    proc_lib:start_link(?MODULE, init, [{ConnInfo, Options}]).


close(Conn) ->
    gen_server:cast(Conn, close).


new_stream(Conn) ->
    Ref = erlang:make_ref(),
    {ok, Socket, StreamId} = gen_server:call(Conn, {new_stream, self(), Ref}),
    {ok, {fron_stream, Socket, StreamId, Ref}}.


init({ConnInfo, Options}) ->
    case fron_socket:connect(ConnInfo, Options) of
        {ok, Socket} ->
            proc_lib:init_ack({ok, self()}),
            St = #{
                socket => Socket,
                curr_stream_id => 0,
                clients => #{},
                monitors => #{},
                messages => #{}
            },
            gen_server:enter_loop(?MODULE, [], St);
        Error ->
            proc_lib:init_ack(Error)
    end.


terminate(_Reason, St) ->
    #{
        socket := Socket
    } = St,
    fron_sock:close(Socket),
    ok.


handle_call({new_stream, Pid, Ref}, _From, St) ->
    #{
        socket := Socket,
        curr_stream_id := CurrStreamId,
        clients := Clients,
        monitors := Monitors
    } = St,
    MonRef = erlang:monitor(process, Pid),
    {reply, {ok, Socket, CurrStreamId}, St#{
        curr_stream_id := CurrStreamId + 1,
        clients := maps:put(CurrStreamId, {Pid, Ref}, Clients),
        monitors := maps:put(MonRef, CurrStreamId, Monitors)
    }};

handle_call(Msg, _From, St) ->
    {stop, {invalid_call, Msg}, {invalid_call, Msg}, St}.


handle_cast(stop, St) ->
    {stop, ok, St};

handle_cast(Msg, St) ->
    {stop, {invalid_cast, Msg}, St}.


handle_info({tcp, Port, Data}, #{socket := {gen_tcp, Port}} = St) ->
    handle_data(St, Data);

handle_info({tcp_closed, Port}, #{socket := {gen_tcp, Port}} = St) ->
    {stop, shutdown, St};

handle_info({tcp_error, Port, Reason}, #{socket := {gen_tcp, Port}} = St) ->
    {stop, {error, Reason}, St};

handle_info({ssl, Port, Data}, #{socket := {ssl, Port}} = St) ->
    handle_data(St, Data);

handle_info({ssl_closed, Port}, #{socket := {ssl, Port}} = St) ->
    {stop, shutdown, St};

handle_info({ssl_error, Port, Reason}, #{socket := {ssl, Port}} = St) ->
    {stop, {error, Reason}, St};

handle_info({'DOWN', MonRef, _, Pid, Reason}, St) ->
    #{
        clients := Clients,
        monitors := Monitors
    } = St,
    case maps:get(MonRef, Monitors, undefined) of
        StreamId when is_integer(StreamId) ->
            {noreply, St#{
                clients := maps:remove(StreamId, Clients),
                monitors := maps:remove(MonRef, Monitors)
            }};
        undefined ->
            {stop, {invalid_monitor, MonRef, Pid, Reason}, St}
    end;

handle_info(Msg, St) ->
    {stop, {invalid_info, Msg, maps:get(socket, St)}, St}.


code_change(_OldVsn, St, _Extra) ->
    {ok, St}.


handle_data(St, Frame) ->
    #{
        messages := Msgs0
    } = St,
    try
        {StreamId, Flags, Data} = parse_frame(St, Frame),
        IsStart = lists:member(message_start, Flags),
        IsEnd = lists:member(message_end, Flags),
        StreamExists = maps:is_key(StreamId, Msgs0),

        Msgs1 = case {IsStart, StreamExists} of
            {true, true} ->
                ?RETURN({stop, {invalid_message_start, StreamId}, St});
            {true, false} ->
                maps:put(StreamId, [Data], Msgs0);
            {false, true} ->
                maps:update_with(StreamId, fun(MsgAcc) ->
                    [Data | MsgAcc]
                end, Msgs0);
            {false, false} ->
                ?RETURN({stop, {invalid_message_continuation, StreamId}, St})
        end,

        Msgs2 = case IsEnd of
            true -> send_message(St, Msgs1, StreamId);
            false -> Msgs1
        end,

        {noreply, St#{messages := Msgs2}}

    catch throw:{?MODULE, return, Value} ->
        Value
    end.


parse_frame(St, Frame) ->
    case Frame of
        <<StreamId:32/integer-unsigned-big, Flags:8, Payload/binary>> ->
            {StreamId, parse_flags(Flags), Payload};
        _ ->
            ?RETURN({stop, {invalid_frame, Frame}, St})
    end.


parse_flags(Flags) ->
    case Flags band 1 == 1 of
        true -> [message_start];
        false -> []
    end
    ++
    case Flags band 2 == 2 of
        true -> [message_end];
        false -> []
    end.


send_message(#{clients := Clients}, Msgs0, StreamId) ->
    MsgAcc = maps:get(StreamId, Msgs0),
    case maps:get(StreamId, Clients, undefined) of
        {Pid, Ref} ->
            Pid ! {fron_msg, Ref, MsgAcc};
        undefined ->
            ok
    end,
    maps:remove(StreamId, Msgs0).
