-module(universityerl_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    case universityerl_store:start() of
        ok -> universityerl_sup:start_link();
        {error, Reason} -> {error, Reason}
    end.

stop(_State) ->
    ok.