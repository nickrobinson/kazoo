%%%-------------------------------------------------------------------
%%% @copyright (C) 2012, VoIP INC
%%% @doc
%%% 
%%% @end
%%% @contributors
%%%   James Aimonetti
%%%   Karl Anderson
%%%-------------------------------------------------------------------
-module(media_listener).

-behaviour(gen_listener).

%% API
-export([start_link/0, handle_media_req/2]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, handle_event/2
         ,terminate/2, code_change/3]).

-include("media.hrl").

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    gen_listener:start_link(?MODULE, [{bindings, [{media, []}]}
                                    ,{responders, [{{?MODULE, handle_media_req}, [{<<"media">>, <<"media_req">>}]}]}
                                   ], []).

handle_media_req(JObj, _Props) ->
    true = wapi_media:req_v(JObj),

    case find_attachment(binary:split(wh_json:get_value(<<"Media-Name">>, JObj, <<>>), <<"/">>, [global, trim])) of
        not_found ->
            send_error_resp(JObj, <<"not_found">>, <<>>);
        no_data ->
            send_error_resp(JObj, <<"no_data">>, <<>>);
        {Db, Doc, Attachment, _MetaData, CType} ->
            send_media_resp(JObj, Db, Doc, Attachment)
    end.

send_media_resp(JObj, Db, Doc, Attachment) ->
    Resp = [{<<"Media-Name">>, wh_json:get_value(<<"Media-Name">>, JObj)}
            ,{<<"Stream-URL">>, <<"vlc://http://localhost:1234/single/"
                                  ,Db/binary, "/"
                                  ,Doc/binary, "/"
                                  ,Attachment/binary>>}
            | wh_api:default_headers(?APP_NAME, ?APP_VERSION)],
    wapi_media:publish_resp(wh_json:get_value(<<"Server-ID">>, JObj), Resp).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
init([]) ->
    lager:debug("starting media_mgr listener"),
    {ok, ok}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_info(_Info, State) ->
    {noreply, State}.

handle_event(_JObj, _State) ->
    {reply, []}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

find_attachment([<<>>, Doc]) ->
    find_attachment([Doc]);
find_attachment([Doc]) ->
    find_attachment([?MEDIA_DB, Doc]);
find_attachment([<<>>, Db, Doc]) ->
    find_attachment([Db, Doc, first]);
find_attachment([Db, Doc]) ->
    find_attachment([Db, Doc, first]);
find_attachment([<<>>, Db, Doc, Attachment]) ->
    find_attachment([Db, Doc, Attachment]);
find_attachment([Db, Doc, first]) ->
    DbName = case couch_mgr:db_exists(Db) of
                 true -> Db;
                 false -> wh_util:format_account_id(Db, encoded)
             end,

    lager:debug("trying to find first attachment in doc ~s in db ~s", [Doc, DbName]),

    case couch_mgr:open_doc(DbName, Doc) of
        {ok, JObj} ->
            case is_streamable(JObj)
                andalso wh_json:get_value(<<"_attachments">>, JObj, false) of
                false ->
                    lager:debug("isn't streamable or no attachments found"),
                    no_data;
                {struct, [{Attachment, MetaData} | _]} ->
                    lager:debug("found attachment to stream: ~s", [Attachment]),
                    {DbName, Doc, Attachment, MetaData, get_content_type_extension(JObj, MetaData)}
            end;
        _->
            not_found
    end;
find_attachment([Db, Doc, Attachment]) ->
    DbName = case couch_mgr:db_exists(Db) of
                 true -> Db;
                 false -> wh_util:format_account_id(Db, encoded)
             end,

    lager:debug("trying to find ~s in doc ~s in db ~s", [Attachment, Doc, DbName]),

    case couch_mgr:open_doc(DbName, Doc) of
        {ok, JObj} ->
            case is_streamable(JObj)
                andalso wh_json:get_value([<<"_attachments">>, Attachment], JObj, false) of
                false ->
                    no_data;
                MetaData ->
                    {DbName, Doc, Attachment, MetaData, get_content_type_extension(JObj, MetaData)}
            end;
        _ ->
            not_found
    end.

-spec get_content_type_extension/2 :: (wh_json:json_object(), wh_json:json_object()) -> 'undefined' | ne_binary().
get_content_type_extension(JObj, MetaData) ->
    case valid_content_type(JObj) of
        undefined ->
            valid_content_type(MetaData);
        ContentType ->
            ContentType
    end.

-spec valid_content_type/1 :: (wh_json:json_object()) -> 'undefined' | ne_binary().
valid_content_type(JObj) ->
    case wh_json:get_value(<<"content_type">>, JObj) of
        <<"audio/mp3", _/binary>> -> <<"mp3">>; %% Jon's computer uses this, is this legit?
        <<"audio/mpeg", _/binary>> -> <<"mp3">>;
        <<"audio/x-wav", _/binary>> -> <<"wav">>;
        <<"audio/wav", _/binary>> -> <<"wav">>;
        _ -> undefined
    end.

-spec is_streamable/1 :: (wh_json:json_object()) -> boolean().
is_streamable(JObj) ->
    wh_json:is_true(<<"streamable">>, JObj, true).

send_error_resp(JObj, ErrCode, <<>>) ->
    MediaName = wh_json:get_value(<<"Media-Name">>, JObj),
    Error = [{<<"Media-Name">>, MediaName}
             ,{<<"Msg-ID">>, wh_json:get_value(<<"Msg-ID">>, JObj)}
             ,{<<"Error-Code">>, wh_util:to_binary(ErrCode)}
             | wh_api:default_headers(?APP_NAME, ?APP_VERSION)],
    lager:debug("sending error reply ~s for ~s", [ErrCode, MediaName]),
    wapi_media:publish_error(wh_json:get_value(<<"Server-ID">>, JObj), Error);
send_error_resp(JObj, _ErrCode, ErrMsg) ->
    MediaName = wh_json:get_value(<<"Media-Name">>, JObj),
    Error = [{<<"Media-Name">>, MediaName}
             ,{<<"Error-Code">>, <<"other">>}
             ,{<<"Error-Msg">>, wh_util:to_binary(ErrMsg)}
             ,{<<"Msg-ID">>, wh_json:get_value(<<"Msg-ID">>, JObj)}
             | wh_api:default_headers(?APP_NAME, ?APP_VERSION)],
    lager:debug("sending error reply ~s for ~s", [_ErrCode, MediaName]),
    wapi_media:publish_error(wh_json:get_value(<<"Server-ID">>, JObj), Error).
