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
-module(fron_socket).

-export([
    connect/2,
    close/1,
    send/2
]).


-type transport() :: gen_tcp | ssl.
-type socket() ::
    {gen_tcp, inet:socket()} |
    {ssl, ssl:sslsocket()}.

-type conn_opts() :: [].

-export_type([
    transport/0,
    socket/0,

    conn_opts/0
]).


-spec connect({transport(), http_uri:host(), http_uri:port()}, conn_opts()) ->
    {ok, socket()} | {error, any()}.
connect({gen_tcp, Host, Port}, Options) ->
    BaseOpts = [
        {mode, binary},
        {packet, 2},
        {active, true}
    ],
    case gen_tcp:connect(Host, Port, BaseOpts ++ Options) of
        {ok, Socket} ->
            {ok, {gen_tcp, Socket}};
        Else ->
            Else
    end;

connect({ssl, Host, Port}, Options) ->
    BaseOpts = [
        {mode, binary},
        {packet, 2},
        {active, true}
    ],
    case ssl:connect(Host, Port, BaseOpts ++ Options, infinity) of
        {ok, Socket} ->
            {ok, {ssl, Socket}};
        Else ->
            Else
    end;

connect({Transport, _, _}, _) ->
    {error, {invalid_transport, Transport}}.


close({Transport, Socket}) ->
    Transport:close(Socket).


-spec send(socket(), binary()) -> ok | {error, any()}.
send({gen_tcp, Socket}, Data) ->
    gen_tcp:send(Socket, Data);
send({ssl, Socket}, Data) ->
    ssl:send(Socket, Data);
send(Socket, _) ->
    erlang:error({bad_socket, Socket}).
