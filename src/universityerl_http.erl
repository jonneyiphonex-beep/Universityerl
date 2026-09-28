-module(universityerl_http).

-export([start_link/0, init/2]).

start_link() ->
    Port = configured_port(),
    WebDir = configured_web_dir(),
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/api/health", ?MODULE, []},
            {"/api/units", ?MODULE, []},
            {"/api/units/:id", ?MODULE, []},
            {"/api/activity", ?MODULE, []},
            {"/", cowboy_static, {file, filename:join(WebDir, "index.html")}},
            {"/[...]", cowboy_static, {dir, WebDir}}
        ]}
    ]),
    cowboy:start_clear(universityerl_http,
        [{ip, configured_ip()}, {port, Port}],
        #{env => #{dispatch => Dispatch}}).

init(Req, State) ->
    Method = cowboy_req:method(Req),
    Path = cowboy_req:path(Req),
    handle_request(Method, Path, Req, State).

handle_request(<<"GET">>, <<"/api/health">>, Req, State) ->
    {Milliseconds, _} = erlang:statistics(wall_clock),
    Body = #{<<"status">> => <<"ok">>,
        <<"uptimeSeconds">> => Milliseconds div 1000,
        <<"vmMemoryBytes">> => erlang:memory(total),
        <<"logicalProcessors">> => json_value(
            erlang:system_info(logical_processors_available))},
    reply_json(200, Body, Req, State);
handle_request(<<"GET">>, <<"/api/units">>, Req, State) ->
    case universityerl_store:list_units() of
        {ok, Units} -> reply_json(200, Units, Req, State);
        {error, Reason} -> reply_error(500, Reason, Req, State)
    end;
handle_request(<<"POST">>, <<"/api/units">>, Req, State) ->
    with_json_body(Req, State, fun(Input, NextReq) ->
        case universityerl_store:create_unit(Input) of
            {ok, Unit} -> reply_json(201, Unit, NextReq, State);
            {error, Reason} -> reply_error(error_status(Reason), Reason, NextReq, State)
        end
    end);
handle_request(<<"GET">>, <<"/api/units/", Id/binary>>, Req, State) ->
    case universityerl_store:get_unit(Id) of
        {ok, Unit} -> reply_json(200, Unit, Req, State);
        {error, Reason} -> reply_error(error_status(Reason), Reason, Req, State)
    end;
handle_request(<<"PUT">>, <<"/api/units/", Id/binary>>, Req, State) ->
    with_json_body(Req, State, fun(Input, NextReq) ->
        case universityerl_store:update_unit(Id, Input) of
            {ok, Unit} -> reply_json(200, Unit, NextReq, State);
            {error, Reason} -> reply_error(error_status(Reason), Reason, NextReq, State)
        end
    end);
handle_request(<<"DELETE">>, <<"/api/units/", Id/binary>>, Req, State) ->
    case universityerl_store:delete_unit(Id) of
        {ok, ok} -> reply_json(200, #{<<"deleted">> => true}, Req, State);
        {error, Reason} -> reply_error(error_status(Reason), Reason, Req, State)
    end;
handle_request(<<"GET">>, <<"/api/activity">>, Req, State) ->
    case universityerl_store:list_activity() of
        {ok, Activity} -> reply_json(200, Activity, Req, State);
        {error, Reason} -> reply_error(500, Reason, Req, State)
    end;
handle_request(_Method, <<"/api/", _/binary>>, Req, State) ->
    reply_error(404, not_found, Req, State);
handle_request(_Method, _Path, Req, State) ->
    reply_error(404, not_found, Req, State).

with_json_body(Req, State, Continue) ->
    case read_body(Req, <<>>) of
        {ok, Body, NextReq} ->
            try jsx:decode(Body, [return_maps]) of
                Input when is_map(Input) -> Continue(Input, NextReq);
                _ -> reply_error(400, invalid_body, NextReq, State)
            catch
                _:_ -> reply_error(400, invalid_json, NextReq, State)
            end;
        {error, NextReq} -> reply_error(400, invalid_body, NextReq, State)
    end.

read_body(Req, Acc) ->
    case cowboy_req:read_body(Req) of
        {ok, Body, NextReq} -> {ok, <<Acc/binary, Body/binary>>, NextReq};
        {more, Body, NextReq} -> read_body(NextReq, <<Acc/binary, Body/binary>>)
    end.

reply_json(Status, Body, Req, State) ->
    Headers = #{<<"content-type">> => <<"application/json; charset=utf-8">>,
        <<"cache-control">> => <<"no-store">>,
        <<"x-content-type-options">> => <<"nosniff">>},
    {ok, cowboy_req:reply(Status, Headers, jsx:encode(Body), Req), State}.

reply_error(Status, Reason, Req, State) ->
    reply_json(Status, #{<<"error">> => error_message(Reason)}, Req, State).

error_status(unit_not_found) -> 404;
error_status(duplicate_code) -> 409;
error_status(has_children) -> 409;
error_status(parent_inactive) -> 409;
error_status(parent_not_found) -> 422;
error_status(parent_required) -> 422;
error_status(invalid_parent) -> 422;
error_status(type_immutable) -> 422;
error_status(invalid_body) -> 400;
error_status(invalid_json) -> 400;
error_status(invalid_type) -> 422;
error_status(invalid_code) -> 422;
error_status(invalid_name) -> 422;
error_status(invalid_status) -> 422;
error_status(_) -> 500.

error_message(unit_not_found) -> <<"الوحدة غير موجودة."/utf8>>;
error_message(duplicate_code) -> <<"الرمز مستخدم لوحدة من النوع نفسه ضمن الوحدة الأعلى ذاتها."/utf8>>;
error_message(has_children) -> <<"لا يمكن حذف وحدة لها وحدات تابعة."/utf8>>;
error_message(parent_inactive) -> <<"يجب أن تكون الوحدة الأعلى نشطة."/utf8>>;
error_message(parent_not_found) -> <<"الوحدة الأعلى غير موجودة."/utf8>>;
error_message(parent_required) -> <<"اختر الوحدة الأعلى المطلوبة."/utf8>>;
error_message(invalid_parent) -> <<"الوحدة الأعلى لا تتوافق مع نوع الوحدة."/utf8>>;
error_message(type_immutable) -> <<"لا يمكن تغيير نوع الوحدة بعد إنشائها."/utf8>>;
error_message(invalid_type) -> <<"نوع الوحدة غير صالح."/utf8>>;
error_message(invalid_code) -> <<"أدخل رمزًا صالحًا لا يتجاوز 24 حرفًا."/utf8>>;
error_message(invalid_name) -> <<"أدخل اسمًا صالحًا لا يتجاوز 100 حرف."/utf8>>;
error_message(invalid_status) -> <<"حالة الوحدة غير صالحة."/utf8>>;
error_message(invalid_json) -> <<"تعذر قراءة JSON المرسل."/utf8>>;
error_message(invalid_body) -> <<"محتوى الطلب غير صالح."/utf8>>;
error_message(not_found) -> <<"المسار غير موجود."/utf8>>;
error_message(_) -> <<"حدث خطأ داخلي في الخادم."/utf8>>.

json_value(undefined) -> null;
json_value(Value) when is_atom(Value) -> null;
json_value(Value) -> Value.

configured_port() ->
    case os:getenv("UNIVERSITYERL_PORT") of
        false -> application:get_env(universityerl, port, 8080);
        PortText ->
            try list_to_integer(PortText) of
                Port when Port > 0, Port < 65536 -> Port;
                _ -> 8080
            catch _:_ -> 8080 end
    end.

configured_ip() ->
    case os:getenv("UNIVERSITYERL_BIND") of
        false -> {127, 0, 0, 1};
        Address ->
            case inet:parse_address(Address) of
                {ok, IpAddress} -> IpAddress;
                {error, _} -> {127, 0, 0, 1}
            end
    end.

configured_web_dir() ->
    case os:getenv("UNIVERSITYERL_WEB_DIR") of
        false -> filename:absname(application:get_env(universityerl, web_dir, "web"));
        Path -> filename:absname(Path)
    end.