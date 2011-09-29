%%%----------------------------------------------------------------------
%%% File    : unixdom_drv.erl
%%% Summary : EDTK implementation of UNIX domain socket driver (incomplete!)
%%%
%%%
%%% NOTICE: This file was generated by the tools of the Erlang Driver
%%%         toolkit.  Do not edit this file by hand unless you know
%%%         what you're doing!
%%%
%%% Copyright (c) 2004, Scott Lystig Fritchie.  All rights reserved.
%%% See the file "LICENSE" at the top of the source distribution for
%%% full license terms.
%%%
%%%----------------------------------------------------------------------

-module(unixdom_drv).
-include("unixdom_drv.hrl").

%% Xref with erl_driver_tk.h's PIPE_DRIVER_TERM_* values
-define(T_NIL, 0).
-define(T_ATOM, 1).
-define(T_PORT, 2).
-define(T_INT, 3).
-define(T_TUPLE, 4).
-define(T_BINARY, 5).
-define(T_STRING, 6).
-define(T_LIST, 7).

%% External exports
-export([start/0, start_pipe/0]).
-export([shutdown/1]).
-export([debug/2]).
-export([null/1, open/3, getfd/2, sendfd/3,
         receivefd/2, close/2]).

start() ->
    {ok, Path} = load_path(?DRV_NAME ++ ".so"),
    erl_ddll:start(),
    ok = erl_ddll:load_driver(Path, ?DRV_NAME),
    case open_port({spawn, ?DRV_NAME}, []) of
        P when is_port(P) ->
            {ok, P};
        Err ->
            Err
    end.

start_pipe() ->
    {ok, PipeMain} = load_path("pipe-main"),
    {ok, ShLib} = load_path("./unixdom_drv.so"),
    Cmd = PipeMain ++ "/pipe-main " ++ ShLib ++ "/unixdom_drv.so",
    case open_port({spawn, Cmd}, [exit_status, binary, use_stdio, {packet, 4}]) of
        P when is_port(P) ->
            {ok, P};
        Err ->
            Err
    end.

shutdown(Port) when is_port(Port) ->
    catch erlang:port_close(Port),
    %% I was under the impression you'd always get a message sent to
    %% you in this case, so this receive is to keep your mailbox from
    %% getting cluttered.  Hrm, well, sometimes the message does
    %% not arrive at all!
    receive
        {'EXIT', Port, normal} -> {ok, normal};
        {'EXIT', Port, Err}    -> {error, Err}
    after 0                    -> {ok, normal} % XXX is 0 too small?
    end.

debug(Port, Flags) when is_port(Port), is_integer(Flags) ->
    case catch erlang:port_command(Port, <<?S1_DEBUG, Flags:32>>) of
        true -> get_port_reply(Port);
        Err  -> throw(Err)              % XXX too drastic?
    end.

null(Port) when is_port(Port) -> % TODO: Add additional constraints here
    IOList_____ = <<?S1_NULL>>,
    case catch erlang:port_command(Port, IOList_____) of
        true -> get_port_reply(Port);
        Err  -> throw(Err)              % XXX Is this too drastic?
    end.

open(Port, Filename, Flags) when is_port(Port) -> % TODO: Add additional constraints here
    {FilenameBinOrList, FilenameLen} = serialize_contiguously(Filename, 1),
    IOList_____ = [<<?S1_OPEN,
                     FilenameLen:32/integer>>,     %% I/O list length
                   FilenameBinOrList,
                   <<Flags:32/integer>>],
    case catch erlang:port_command(Port, IOList_____) of
        true -> get_port_reply(Port);
        Err  -> throw(Err)              % XXX Is this too drastic?
    end.

getfd(Port, Fd) when is_port(Port) -> % TODO: Add additional constraints here
    {valmap_fd, FdIndex} = Fd,
    IOList_____ = <<?S1_GETFD,
                    FdIndex:32/integer>>,
    case catch erlang:port_command(Port, IOList_____) of
        true -> get_port_reply(Port);
        Err  -> throw(Err)              % XXX Is this too drastic?
    end.

sendfd(Port, Unixdom_Fd, Fd_To_Be_Sent) when is_port(Port) -> % TODO: Add additional constraints here
    IOList_____ = <<?S1_SENDFD,
                    Unixdom_Fd:32/integer,
                    Fd_To_Be_Sent:32/integer
                  >>,
    case catch erlang:port_command(Port, IOList_____) of
        true -> get_port_reply(Port);
        Err  -> throw(Err)              % XXX Is this too drastic?
    end.

receivefd(Port, Unixdom_Fd) when is_port(Port) -> % TODO: Add additional constraints here
    IOList_____ = <<?S1_RECEIVEFD,
                    Unixdom_Fd:32/integer
                  >>,
    case catch erlang:port_command(Port, IOList_____) of
        true -> get_port_reply(Port);
        Err  -> throw(Err)              % XXX Is this too drastic?
    end.

close(Port, Fd) when is_port(Port) -> % TODO: Add additional constraints here
    {valmap_fd, FdIndex} = Fd,
    IOList_____ = <<?S1_CLOSE,
                    FdIndex:32/integer
                  >>,
    case catch erlang:port_command(Port, IOList_____) of
        true -> get_port_reply(Port);
        Err  -> throw(Err)              % XXX Is this too drastic?
    end.

%%%
%%% Internal functions.
%%%
load_path(File) ->
    case lists:filter(fun(D) ->
                              case file:read_file_info(D ++ "/" ++ File) of
                                  {ok, _} -> true;
                                  _ -> false
                              end
                      end, code:get_path()) of
        [Dir|_] ->
            {ok, Dir};
        [] ->
            io:format("Error: ~s not found in code path\n", [File]),
            {error, enoent}
    end.

%%%
%%% Note that an 'xtra_return' that only returns one item in its
%%% tuple will return {Port, ok, {Thingie}}, so we'll return
%%% {ok, {Thingie}}, which is *sooooooo* maddening because I keep
%%% forgetting the extra tuple wrapper.  So, if there's only one
%%% thingie in the return tuple, strip it off: {ok, Thingie}
%%%
get_port_reply(Port) when is_port(Port) ->
    receive
        {Port, ok} = T -> proc_reply(T);
        {Port, ok, {_M}} = T -> proc_reply(T);
        {Port, ok, _M} = T -> proc_reply(T);
        {Port, error, {_Reason}} = T -> proc_reply(T);
        {Port, error, _Reason} = T -> proc_reply(T);
        %% Pipe driver messages
        {Port, {data, Bytes}} -> proc_reply(pipedrv_deser(Port, Bytes));
        {'EXIT', Port, Reason} -> throw({port_error, Reason});  % XXX too drastic?
        {Port, Reason} -> throw({port_error, Reason})   % XXX too drastic?
    end.

%% This function exists to provide consistency of replies
%% given by linked-in and pipe drivers.  The "receive" statement
%% in get_port_reply/1 is specific because we want it to be
%% very selective about what it will grab out of the mailbox.
proc_reply({Port, ok}) when is_port(Port) ->
    ok;
proc_reply({Port, ok, {M}}) when is_port(Port) ->
    {ok, M};
proc_reply({Port, ok, M}) when is_port(Port) ->
    {ok, M};
proc_reply({Port, error, {Reason}}) when is_port(Port) ->
    {error, Reason};
proc_reply({Port, error, Reason}) when is_port(Port) ->
    {error, Reason}.

%%% We need to make the binary thing we're passing in contiguous
%%% because the C function we're calling is expecting a single
%%% contiguous buffer.  If IOList is ["Hello, ", <<"World">>, "!"],
%%% that binary in the middle element will end up with the argument
%%% spanning three parts of an ErlIOVec.  If that happens, then we'd
%%% have to have the driver do the dirty work of putting the argument
%%% into a single contiguous buffer.
%%%
%%% Frankly, we're lazy, and this code is short and won't be much
%%% slower than doing it in C.

%%% 2nd arg: if 1, NUL-terminate the IOList
serialize_contiguously(B, 0) when is_binary(B) ->
    {B, size(B)};
serialize_contiguously([B], 0) when is_binary(B) ->
    {B, size(B)};
serialize_contiguously(IOList, 1) ->
    serialize_contiguously([IOList, 0], 0);
serialize_contiguously(IOList, 0) ->
    B = list_to_binary(IOList),
    {B, size(B)}.

%% pipedrv_deser/2 -- Deserialize the term that the pipe driver is
%% is returning to Erlang.  The pipe driver doesn't know it's a pipe
%% driver, it thinks it's a linked-in driver, so it tries to return
%% an arbitrary Erlang term to us.  The pipe-main program is sneaky:
%% it has a driver_output_term() function that serializes the term
%% that the driver built.  With the help of a list-as-stack, we
%% deserialize that term.
pipedrv_deser(Port, B) ->
    pipedrv_deser(Port, B, []).

pipedrv_deser(_Port, <<>>, []) ->
    throw(icky_i_think);
pipedrv_deser(_Port, <<>>, [T]) ->
    T;
pipedrv_deser(Port, <<?T_NIL:8, Rest/binary>>, Stack) ->
    pipedrv_deser(Port, Rest, [foo___foo_nil___|Stack]);
pipedrv_deser(Port, <<?T_ATOM:8, Len:8, Rest/binary>>, Stack) ->
    <<A:Len/binary, Rest2/binary>> = Rest,
    pipedrv_deser(Port, Rest2, [list_to_atom(binary_to_list(A))|Stack]);
pipedrv_deser(Port, <<?T_PORT:8, _P:32/unsigned, Rest/binary>>, Stack) ->
    %% The pipe driver tried sending us a port, but it cannot know what
    %% port ID was assigned to this port, so we'll assume it is Port.
    pipedrv_deser(Port, Rest, [Port|Stack]);
pipedrv_deser(Port, <<?T_INT:8, I:32/signed, Rest/binary>>, Stack) ->
    pipedrv_deser(Port, Rest, [I|Stack]);
pipedrv_deser(Port, <<?T_TUPLE:8, N:8, Rest/binary>>, Stack) ->
    {L, NewStack} = popN(N, Stack),
    pipedrv_deser(Port, Rest, [list_to_tuple(L)|NewStack]);
pipedrv_deser(Port, <<?T_LIST:8, N:32, Rest/binary>>, Stack) ->
    {L, NewStack} = popN(N, Stack),
    pipedrv_deser(Port, Rest, [L|NewStack]);
pipedrv_deser(Port, <<?T_BINARY:8, Len:32/signed, Rest/binary>>, Stack) ->
    <<Bin:Len/binary, Rest2/binary>> = Rest,
    pipedrv_deser(Port, Rest2, [Bin|Stack]);
pipedrv_deser(Port, <<?T_STRING:8, Len:32/signed, Rest/binary>>, Stack) ->
    <<Bin:Len/binary, Rest2/binary>> = Rest,
    pipedrv_deser(Port, Rest2, [binary_to_list(Bin)|Stack]);
pipedrv_deser(_Port, X, Y) ->
    throw({bah, X, Y}).

popN(N, Stack) ->
    popN(N, Stack, []).
popN(0, Stack, Acc) ->
    {Acc, Stack};
popN(N, [foo___foo_nil___|T], Acc) ->
    %% This is the nonsense we put on the stack to represent NIL.  Ignore it.
    popN(N - 1, T, Acc);
popN(N, [H|T], Acc) ->
    popN(N - 1, T, [H|Acc]).
