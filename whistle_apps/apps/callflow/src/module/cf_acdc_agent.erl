%%%-------------------------------------------------------------------
%%% @copyright (C) 2012, VoIP INC
%%% @doc
%%% Handles changing an agent's status
%%%
%%% "data":{
%%%   "action":["login","logout","paused","resume"] // one of these
%%%   ,"timeout":600 // in seconds, for "paused" status
%%% }
%%% @end
%%% @contributors
%%%   James Aimonetti
%%%-------------------------------------------------------------------
-module(cf_acdc_agent).

-export([handle/2
         ,find_agent/1
         ,find_agent_status/2
         ,play_not_an_agent/1
         ,play_agent_invalid/1
         ,login_agent/2
         ,logout_agent/2
        ]).

-include("../callflow.hrl").

%%--------------------------------------------------------------------
%% @public
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec handle(wh_json:object(), whapps_call:call()) -> 'ok'.
handle(Data, Call) ->
    whapps_call_command:answer(Call),
    _ = case find_agent(Call) of
            {'ok', 'undefined'} ->
                lager:info("no owner on this device == no agent"),
                play_not_an_agent(Call);
            {'ok', AgentId} ->
                Status = find_agent_status(Call, AgentId),
                NewStatus = fix_data_status(wh_json:get_value(<<"action">>, Data)),
                lager:info("agent ~s maybe changing status from ~s to ~s", [AgentId, Status, NewStatus]),

                maybe_update_status(Call, AgentId, Status, NewStatus, Data);
            {'error', 'multiple_owners'} ->
                lager:info("too many owners of device ~s, not logging in", [whapps_call:authorizing_id(Call)]),
                play_agent_invalid(Call)
        end,
    lager:info("finished with acdc agent callflow"),
    cf_exe:continue(Call).

-spec find_agent_status(whapps_call:call() | ne_binary(), ne_binary()) -> ne_binary().
find_agent_status(?NE_BINARY = AcctId, AgentId) ->
    fix_agent_status(acdc_util:agent_status(AcctId, AgentId));
find_agent_status(Call, AgentId) ->
    find_agent_status(whapps_call:account_id(Call), AgentId).

fix_agent_status(<<"resume">>) -> <<"ready">>;
fix_agent_status(<<"wrapup">>) -> <<"ready">>;
fix_agent_status(<<"busy">>) -> <<"ready">>;
fix_agent_status(<<"logout">>) -> <<"logged_out">>;
fix_agent_status(<<"login">>) -> <<"ready">>;
fix_agent_status(<<"outbound">>) -> <<"ready">>;
fix_agent_status(Status) -> Status.

fix_data_status(<<"pause">>) -> <<"paused">>;
fix_data_status(Status) -> Status.

maybe_update_status(Call, AgentId, _Curr, <<"logout">>, _Data) ->
    lager:info("agent ~s wants to log out (currently: ~s)", [AgentId, _Curr]),
    logout_agent(Call, AgentId),
    play_agent_logged_out(Call);
maybe_update_status(Call, AgentId, <<"logged_out">>, <<"resume">>, _Data) ->
    lager:debug("agent ~s is logged out, resuming doesn't make sense", [AgentId]),
    play_agent_invalid(Call);
maybe_update_status(Call, AgentId, <<"logged_out">>, <<"login">>, _Data) ->
    lager:debug("agent ~s wants to log in", [AgentId]),
    login_agent(Call, AgentId),
    play_agent_logged_in(Call);

maybe_update_status(Call, AgentId, <<"ready">>, <<"login">>, _Data) ->
    lager:info("agent ~s is already logged in", [AgentId]),
    _ = play_agent_logged_in_already(Call),
    send_new_status(Call, AgentId, fun wapi_acdc_agent:publish_login/1, 'undefined');

maybe_update_status(Call, AgentId, FromStatus, <<"paused">>, Data) ->
    maybe_pause_agent(Call, AgentId, FromStatus, Data);

maybe_update_status(Call, AgentId, <<"paused">>, <<"ready">>, _Data) ->
    lager:info("agent ~s is coming back from pause", [AgentId]),
    resume_agent(Call, AgentId),
    play_agent_resume(Call);
maybe_update_status(Call, AgentId, <<"paused">>, <<"resume">>, _Data) ->
    lager:info("agent ~s is coming back from pause", [AgentId]),
    resume_agent(Call, AgentId),
    play_agent_resume(Call);
maybe_update_status(Call, AgentId, <<"outbound">>, <<"resume">>, _Data) ->
    lager:info("agent ~s is coming back from pause", [AgentId]),
    resume_agent(Call, AgentId),
    play_agent_resume(Call);
maybe_update_status(Call, AgentId, <<"ready">>, <<"resume">>, _Data) ->
    lager:info("agent ~s is coming back from pause", [AgentId]),
    resume_agent(Call, AgentId),
    play_agent_resume(Call);

maybe_update_status(Call, _AgentId, _Status, _NewStatus, _Data) ->
    lager:info("agent ~s: invalid status change from ~s to ~s", [_AgentId, _Status, _NewStatus]),
    play_agent_invalid(Call).

maybe_pause_agent(Call, AgentId, <<"ready">>, Data) ->
    pause_agent(Call, AgentId, Data);
maybe_pause_agent(Call, _AgentId, FromStatus, _Data) ->
    lager:info("unable to go from ~s to paused", [FromStatus]),
    play_agent_invalid(Call).

login_agent(Call, AgentId) ->
    update_agent_status(Call, AgentId, <<"ready">>, fun wapi_acdc_agent:publish_login/1).

logout_agent(Call, AgentId) ->
    update_agent_status(Call, AgentId, <<"logged_out">>, fun wapi_acdc_agent:publish_logout/1).

pause_agent(Call, AgentId, Timeout) when is_integer(Timeout) ->
    _ = play_agent_pause(Call),
    update_agent_status(Call, AgentId, <<"paused">>, fun wapi_acdc_agent:publish_pause/1, Timeout);
pause_agent(Call, AgentId, Data) ->
    Timeout = wh_json:get_integer_value(<<"timeout">>
                                        ,Data
                                        ,whapps_config:get(<<"acdc">>, <<"default_agent_pause_timeout">>, 600)
                                       ),
    lager:info("agent ~s is pausing work for ~b s", [AgentId, Timeout]),
    pause_agent(Call, AgentId, Timeout).

resume_agent(Call, AgentId) ->
    update_agent_status(Call, AgentId, <<"ready">>, fun wapi_acdc_agent:publish_resume/1).

update_agent_status(Call, AgentId, Status, PubFun) ->
    update_agent_status(Call, AgentId, Status, PubFun, 'undefined').
update_agent_status(Call, AgentId, Status, PubFun, Timeout) ->
    AcctId = whapps_call:account_id(Call),

    Extra = [{<<"Call-ID">>, whapps_call:call_id(Call)}
             ,{<<"Wait-Time">>, Timeout}
             | wh_api:default_headers(?APP_NAME, ?APP_VERSION)
            ],

    'ok' = acdc_util:update_agent_status(AcctId, AgentId, Status, Extra),

    send_new_status(Call, AgentId, PubFun, Timeout).

-spec send_new_status(whapps_call:call(), ne_binary(), wh_amqp_worker:publish_fun(), integer() | 'undefined') -> 'ok'.
send_new_status(Call, AgentId, PubFun, Timeout) ->
    Update = props:filter_undefined(
               [{<<"Account-ID">>, whapps_call:account_id(Call)}
                ,{<<"Agent-ID">>, AgentId}
                ,{<<"Time-Limit">>, Timeout}
                | wh_api:default_headers(?APP_NAME, ?APP_VERSION)
               ]),
    PubFun(Update).

-type find_agent_error() :: 'unknown_endpoint' | 'multiple_owners'.
-spec find_agent(whapps_call:call()) ->
                        {'ok', api_binary()} |
                        {'error', find_agent_error()}.
find_agent(Call) ->
    find_agent(Call, whapps_call:authorizing_id(Call)).

find_agent(_Call, 'undefined') ->
    {'error', 'unknown_endpoint'};
find_agent(Call, EndpointId) ->
    {'ok', Endpoint} = couch_mgr:open_doc(whapps_call:account_db(Call), EndpointId),
    find_agent(Call, Endpoint, wh_json:get_value([<<"hotdesk">>, <<"users">>], Endpoint)).

find_agent(Call, Endpoint, 'undefined') ->
    find_agent_owner(Call, wh_json:get_value(<<"owner_id">>, Endpoint));
find_agent(Call, Endpoint, Owners) ->
    case wh_json:get_keys(Owners) of
        [] -> find_agent_owner(Call, wh_json:get_value(<<"owner_id">>, Endpoint));
        [OwnerId] -> {'ok', OwnerId};
        _ -> {'error', 'multiple_owners'}
    end.

find_agent_owner(Call, 'undefined') -> {'ok', whapps_call:owner_id(Call)};
find_agent_owner(_Call, EPOwnerId) -> {'ok', EPOwnerId}.

play_not_an_agent(Call) -> whapps_call_command:b_prompt(<<"agent-not_call_center_agent">>, Call).
play_agent_logged_in_already(Call) -> whapps_call_command:b_prompt(<<"agent-already_logged_in">>, Call).
play_agent_logged_in(Call) -> whapps_call_command:b_prompt(<<"agent-logged_in">>, Call).
play_agent_logged_out(Call) -> whapps_call_command:b_prompt(<<"agent-logged_out">>, Call).
play_agent_resume(Call) -> whapps_call_command:b_prompt(<<"agent-resume">>, Call).
play_agent_pause(Call) -> whapps_call_command:b_prompt(<<"agent-pause">>, Call).
play_agent_invalid(Call) -> whapps_call_command:b_prompt(<<"agent-invalid_choice">>, Call).
