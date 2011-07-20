-module(utp_test).

-include("log.hrl").
-include_lib("common_test/include/ct.hrl").

-export([
         test_connect_n_communicate_connect/0,
         test_connect_n_communicate_listen/1,
         test_backwards_connect/0,
         test_backwards_listen/1,
         test_full_duplex_out/0, test_full_duplex_in/1,
         test_close_in_1/1,
         test_close_out_1/0,
         test_close_in_2/1,
         test_close_out_2/0,
         test_close_in_3/1,
         test_close_out_3/0,
         test_send_large_file/1,
         test_recv_large_file/2,

         test_piggyback_in/2,
         test_piggyback_out/1,

         test_rwin_in/2,
         test_rwin_out/1,

         get/1,

         c/0, c/1, l/0, l/1
         ]).

%% ----------------------------------------------------------------------
    
test_connect_n_communicate_connect() ->
    {ok, Sock} = repeating_connect("localhost", 3333),
    ok = gen_utp:send(Sock, "HELLO"),
    ok = gen_utp:send(Sock, "WORLD"),
    timer:sleep(1000),
    ok = gen_utp:close(Sock),
    {ok, gen_utp_trace:grab()}.

test_connect_n_communicate_listen(Options) ->
    ok =  listen(Options),
    {ok, Port} = gen_utp:accept(),
    {ok, R1} = gen_utp:recv(Port, 5),
    {ok, R2} = gen_utp:recv(Port, 5),
    ok = gen_utp:close(Port),
    {<<"HELLO">>, <<"WORLD">>} = {R1, R2},
    {ok, gen_utp_trace:grab()}.

test_backwards_connect() ->
    {ok, Sock} = repeating_connect("localhost", 3333),
    case gen_utp:recv(Sock, 10) of
        {ok, <<"HELLOWORLD">>} ->
            ok = gen_utp:close(Sock),
            {ok, gen_utp_trace:grab()};
        {error, econnreset} ->
            {{error, econnreset}, gen_utp_trace:grab()}
    end.

test_backwards_listen(Options) ->
    ok = listen(Options),
    {ok, Sock} = gen_utp:accept(),
    ok = gen_utp:send(Sock, <<"HELLO">>),
    ok = gen_utp:send(Sock, <<"WORLD">>),
    ok = gen_utp:close(Sock),
    {ok, gen_utp_trace:grab()}.

test_full_duplex_in(Options) ->
    ok = listen(Options),
    {ok, Sock} = gen_utp:accept(),
    ok = gen_utp:send(Sock, <<"HELLO">>),
    ok = gen_utp:send(Sock, <<"WORLD">>),
    {ok, <<"12345">>} = gen_utp:recv(Sock, 5),
    {ok, <<"67890">>} = gen_utp:recv(Sock, 5),
    ok = gen_utp:close(Sock),
    {ok, gen_utp_trace:grab()}.

test_full_duplex_out() ->
    {ok, Sock} = repeating_connect("localhost", 3333),
    ok = gen_utp:send(Sock, "12345"),
    ok = gen_utp:send(Sock, "67890"),
    {ok, <<"HELLOWORLD">>} = gen_utp:recv(Sock, 10),
    ok = gen_utp:close(Sock),
    {ok, gen_utp_trace:grab()}.

test_close_out_1() ->
    {ok, Sock} = repeating_connect("localhost", 3333),
    ok = gen_utp:close(Sock),
    {error, econnreset} = gen_utp:send(Sock, <<"HELLO">>),
    {ok, gen_utp_trace:grab()}.

test_close_in_1(Options) ->
    ok = listen(Options),
    {ok, Sock} = gen_utp:accept(),
    timer:sleep(3000),
    case gen_utp:send(Sock, <<"HELLO">>) of
        ok ->
            ignore;
        {error, econnreset} ->
            ignore
    end,
    ok = gen_utp:close(Sock),
    {ok, gen_utp_trace:grab()}.

test_close_out_2() ->
    {ok, Sock} = repeating_connect("localhost", 3333),
    timer:sleep(3000),
    case gen_utp:send(Sock, <<"HELLO">>) of
        ok ->
            ignore;
        {error, econnreset} ->
            ignore
    end,
    ok = gen_utp:close(Sock),
    {ok, gen_utp_trace:grab()}.

test_close_in_2(Options) ->
    ok =  listen(Options),
    {ok, Sock} = gen_utp:accept(),
    ok = gen_utp:close(Sock),
    case gen_utp:recv(Sock, 5) of
        {error, eof} ->
            ignore;
        {error, econnreset} ->
            ignore
    end,
    {ok, gen_utp_trace:grab()}.

test_close_out_3() ->
    {ok, Sock} = repeating_connect("localhost", 3333),
    ok = gen_utp:send(Sock, <<"HELLO">>),
    {ok, <<"WORLD">>} = gen_utp:recv(Sock, 5),
    ok = gen_utp:close(Sock),
    {ok, gen_utp_trace:grab()}.

test_close_in_3(Options) ->
    ok = listen(Options),
    {ok, Sock} = gen_utp:accept(),
    ok = gen_utp:send(Sock, "WORLD"),
    {ok, <<"HELLO">>} = gen_utp:recv(Sock, 5),
    ok = gen_utp:close(Sock),
    {ok, gen_utp_trace:grab()}.

test_send_large_file(Data) ->
    {ok, Sock} = repeating_connect("localhost", 3333),
    ok = gen_utp:send(Sock, Data),
    ok = gen_utp:close(Sock),
    {ok, gen_utp_trace:grab()}.

%% Infinitely repeat connecting. A timetrap will capture the problem
-spec repeating_connect(term(), integer()) -> no_return() | {ok, any()}.
repeating_connect(Host, Port) ->
    case gen_utp:connect(Host, Port) of
        {ok, Sock} ->
            {ok, Sock};
        {error, etimedout} ->
            repeating_connect(Host, Port)
    end.

test_rwin_in(Data, Options) ->
    Sz = byte_size(Data),
    ok = listen(Options),
    {ok, Sock} = gen_utp:accept(),
    Data = rwin_recv(Sock, Sz, <<>>),
    ok = gen_utp:close(Sock),
    {ok, gen_utp_trace:grab()}.

rwin_recv(_Sock, 0, Binary) ->
    Binary;
rwin_recv(Sock, Sz, Acc) when Sz =< 10000 ->
    timer:sleep(3000),
    {ok, B} = gen_utp:recv(Sock, Sz),
    rwin_recv(Sock, 0, <<Acc/binary, B/binary>>);
rwin_recv(Sock, Sz, Acc) when Sz > 10000 ->
    timer:sleep(3000),
    {ok, B} = gen_utp:recv(Sock, 10000),
    rwin_recv(Sock, Sz - 10000, <<Acc/binary, B/binary>>).

test_rwin_out(Data) ->
    {ok, Sock} = repeating_connect("localhost", 3333),
    ok = gen_utp:send(Sock, Data),
    ok = gen_utp:close(Sock),
    {ok, gen_utp_trace:grab()}.

test_piggyback_out(Data) ->
    Sz = byte_size(Data),
    {ok, Sock} = repeating_connect("localhost", 3333),
    {Recv, Ref} = {self(), make_ref()},
    spawn_link(fun() ->
                       ok = gen_utp:send(Sock, Data),
                       Recv ! {done, Ref}
               end),
    {ok, Data} = gen_utp:recv(Sock, Sz),
    gen_utp_trace:tr("Received out, waiting for done"),
    receive
        {done, Ref} ->
            ok
    end,
    {ok, Sock, gen_utp_trace:grab()}.
    

test_piggyback_in(Data, Options) ->
    Sz = byte_size(Data),
    ok = listen(Options),
    {ok, Sock} = gen_utp:accept(),
    {Recv, Ref} = {self(), make_ref()},
    spawn_link(fun() ->
                       ok = gen_utp:send(Sock, Data),
                       Recv ! {done, Ref}
               end),
    {ok, Data} = gen_utp:recv(Sock, Sz),
    gen_utp_trace:tr("Received in, waiting for done"),
    receive
        {done, Ref} ->
            ok
    end,
    {ok, Sock, gen_utp_trace:grab()}.

test_recv_large_file(Data, Options) ->
    Sz = byte_size(Data),
    case listen(Options) of
        ok ->
            ignore;
        {error, ealreadylistening} ->
            ignore
    end,
    {ok, Port} = gen_utp:accept(),
    {ok, Data} = gen_utp:recv(Port, Sz),
    ok = gen_utp:close(Port),
    {ok, gen_utp_trace:grab()}.

get(N) when is_integer(N) ->
    {ok, Sock} = gen_utp:connect("port1394.ds1-vby.adsl.cybercity.dk", 3333),
    ok = gen_utp:send(Sock, <<N:32/integer>>),
    {ok, <<FnLen:32/integer>>} = gen_utp:recv(Sock, 4),
    {ok, FName}        = gen_utp:recv(Sock, FnLen),
    {ok, <<Len:32/integer>>} = gen_utp:recv(Sock, 4),
    {ok, Data} = gen_utp:recv(Sock, Len),
    file:write_file(FName, Data),
    ok = gen_utp:close(Sock),
    {ok, gen_utp_trace:grab()}.

listen(Config) ->
    Opts = case proplists:get_value(force_seq_no, Config) of
               K when is_integer(K),
                      K >= 0,
                      K =<  16#FFFF ->
                   [{force_seq_no, K}];
               _Otherwise ->
                   []
           end,
    case gen_utp:listen(Opts) of
        ok ->
            ok;
        {error, ealreadylistening} ->
            ok
    end.

%% ----------------------------------------------------------------------
l() ->
    l(test_close_3).

l(T) ->
    utp:start_app(3333),
    utp_filter:start(),
    (parse_listen(T))([]).

parse_listen(test_close_3) ->
    fun test_close_in_3/1;
parse_listen(test_close_2) ->
    fun test_close_in_2/1;
parse_listen(test_close_1) ->
    fun test_close_in_1/1;
parse_listen(test_full_duplex) ->
    fun test_full_duplex_in/1;
parse_listen(test_backwards) ->
    fun test_backwards_listen/1;
parse_listen(test_connect_n_communicate) ->
    fun test_connect_n_communicate_listen/1.

c() ->
    c(test_close_3).

c(T) ->
    utp:start_app(3334),
    utp_filter:start(),
    (parse_connect(T))().


parse_connect(test_close_3) ->
    fun test_close_out_3/0;
parse_connect(test_close_2) ->
    fun test_close_out_2/0;
parse_connect(test_close_1) ->
    fun test_close_out_1/0;
parse_connect(test_full_duplex) ->
    fun test_full_duplex_out/0;
parse_connect(test_backwards) ->
    fun test_backwards_connect/0;
parse_connect(test_connect_n_communicate) ->
    fun test_connect_n_communicate_connect/0.


