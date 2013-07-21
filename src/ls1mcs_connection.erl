-module(ls1mcs_connection).
-compile([{parse_transform, lager_transform}]).
-behaviour(gen_server).
-behaviour(ls1mcs_protocol).
-export([start_link/2]).
-export([send/2, received/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).


%% =============================================================================
%%  API Function Definitions
%% =============================================================================

%%
%%
%%
start_link(Name, LinkRef) ->
    gen_server:start_link({via, gproc, Name}, ?MODULE, {LinkRef}, []).


%% =============================================================================
%%  Internal data structures.
%% =============================================================================


-record(state, {
    link
}).



%% =============================================================================
%%  Callbacks for ls1mcs_protocol.
%% =============================================================================

%%
%%  Not used here.
%%
send(_Ref, _Data) ->
    ok.


%%
%%  Receives incoming messages from the protocol stack.
%%
received(_Ref, Data) ->
    lager:info("ls1mcs_connection received a message: ~p", [Data]).


%% =============================================================================
%%  Callbacks for gen_server.
%% =============================================================================

%%
%%
%%
init({LinkRef}) ->
    {ok, #state{link = LinkRef}}.


%%
%%
%%
handle_call(_Message, _From, State) ->
    {stop, error, State}.


%%
%%
%%
handle_cast(_Msg, State) ->
    {noreply, State}.


%%
%%
%%
handle_info(_Info, State) ->
    {noreply, State}.


%%
%%
%%
terminate(_Reason, _State) ->
    ok.


%%
%%
%%
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%% =============================================================================
%%  Internal Functions.
%% =============================================================================

