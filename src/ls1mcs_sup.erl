-module(ls1mcs_sup).
-behaviour(supervisor).
-export([start_link/1]).    % API
-export([init/1]).          % CB


%% =============================================================================
%%  API functions.
%% =============================================================================


%%
%% @doc Create this supervisor.
%%
start_link(LinkCfg) ->
    supervisor:start_link(?MODULE, {LinkCfg}).



%% =============================================================================
%%  Callbacks for supervisor.
%% =============================================================================


%%
%% @doc Supervisor initialization (CB).
%%
init({LinkCfg}) ->
    {LinkType, LinkOptions} = LinkCfg,

    ConnMod = ls1mcs_connection,
    LSupMod = ls1mcs_link_sup,
    StoreMod = ls1mcs_store,

    LinkRef = LSupMod:top_ref(),
    ConnName = {n, l, ConnMod},
    ConnRef  = ls1mcs_protocol:make_ref(ConnMod, ConnName),

    ConnArgs = [ConnName, LinkRef],
    LSupArgs = [ConnRef, LinkType, LinkOptions],

    {ok, {{one_for_all, 100, 10}, [
        {store, {StoreMod, start_link, []},       permanent, 5000, worker,     [StoreMod]},
        {link,  {LSupMod,  start_link, LSupArgs}, permanent, 5000, supervisor, [LSupMod]},
        {conn,  {ConnMod,  start_link, ConnArgs}, permanent, 5000, worker,     [ConnMod]}
    ]}}.


