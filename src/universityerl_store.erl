-module(universityerl_store).

-export([start/0, list_units/0, get_unit/1, create_unit/1, update_unit/2,
         delete_unit/1, list_activity/0]).

-define(UNITS, academic_units).
-define(ACTIVITY, academic_activity).

start() ->
    DataDir = data_dir(),
    ok = filelib:ensure_dir(filename:join(DataDir, "placeholder")),
    ok = application:set_env(mnesia, dir, DataDir),
    case ensure_schema() of
        ok ->
            case application:ensure_all_started(mnesia) of
                {ok, _} -> initialize_tables();
                {error, Reason} -> {error, {mnesia_start_failed, Reason}}
            end;
        {error, _} = Error -> Error
    end.

list_units() ->
    Units = lists:append([mnesia:dirty_read(?UNITS, Id) || Id <- mnesia:dirty_all_keys(?UNITS)]),
    {ok, [unit_map(Unit) || Unit <- lists:sort(fun unit_order/2, Units)]}.

get_unit(Id) ->
    case mnesia:dirty_read(?UNITS, Id) of
        [Unit] -> {ok, unit_map(Unit)};
        [] -> {error, unit_not_found}
    end.

create_unit(Input) when is_map(Input) ->
    with_valid_input(Input, undefined, fun(Fields) ->
        Id = new_id(),
        Now = timestamp(),
        Unit = list_to_tuple([academic_unit, Id | Fields] ++ [Now, Now]),
        transaction(fun() ->
            validate_unit(Unit, undefined),
            mnesia:write(?UNITS, Unit, write),
            log_activity(<<"إضافة"/utf8>>, Unit),
            unit_map(Unit)
        end)
    end);
create_unit(_) ->
    {error, invalid_body}.

update_unit(Id, Input) when is_map(Input) ->
    transaction(fun() ->
        case mnesia:read(?UNITS, Id, write) of
            [Existing] ->
                case with_valid_input(Input, Existing, fun(Fields) -> Fields end) of
                    [Type, Code, Name, ParentId, Status] ->
                        case Type =:= element(3, Existing) of
                            false -> mnesia:abort({domain_error, type_immutable});
                            true ->
                                Now = timestamp(),
                                Updated = setelement(9,
                                    setelement(7, Existing, Status), Now),
                                Updated2 = setelement(4, Updated, Code),
                                Updated3 = setelement(5, Updated2, Name),
                                Updated4 = setelement(6, Updated3, ParentId),
                                validate_unit(Updated4, Id),
                                mnesia:write(?UNITS, Updated4, write),
                                log_activity(<<"تعديل"/utf8>>, Updated4),
                                unit_map(Updated4)
                        end;
                    {error, Reason} -> mnesia:abort({domain_error, Reason})
                end;
            [] -> mnesia:abort({domain_error, unit_not_found})
        end
    end);
update_unit(_Id, _Input) ->
    {error, invalid_body}.

delete_unit(Id) ->
    transaction(fun() ->
        case mnesia:read(?UNITS, Id, write) of
            [Unit] ->
                Children = mnesia:foldl(fun(Child, Acc) ->
                    case element(6, Child) =:= Id of
                        true -> [Child | Acc];
                        false -> Acc
                    end
                end, [], ?UNITS),
                case Children of
                    [] ->
                        mnesia:delete({?UNITS, Id}),
                        log_activity(<<"حذف"/utf8>>, Unit),
                        ok;
                    _ -> mnesia:abort({domain_error, has_children})
                end;
            [] -> mnesia:abort({domain_error, unit_not_found})
        end
    end).

list_activity() ->
    Events = lists:append([mnesia:dirty_read(?ACTIVITY, Id) || Id <- mnesia:dirty_all_keys(?ACTIVITY)]),
    Sorted = lists:sublist(lists:sort(fun activity_order/2, Events), 20),
    {ok, [activity_map(Event) || Event <- Sorted]}.

initialize_tables() ->
    case create_table(?UNITS,
            [id, type, code, name, parent_id, status, created_at, updated_at],
            academic_unit) of
        ok ->
            case create_table(?ACTIVITY,
                    [id, action, name, detail, occurred_at], activity_record) of
                ok ->
                    case mnesia:wait_for_tables([?UNITS, ?ACTIVITY], 10000) of
                        ok -> seed_if_empty();
                        {timeout, Tables} -> {error, {tables_unavailable, Tables}}
                    end;
                {error, _} = Error -> Error
            end;
        {error, _} = Error -> Error
    end.

create_table(Name, Attributes, RecordName) ->
    case mnesia:create_table(Name, [
        {attributes, Attributes},
        {record_name, RecordName},
        {type, set},
        {disc_copies, [node()]}
    ]) of
        {atomic, ok} -> ok;
        {aborted, {already_exists, Name}} -> ok;
        {aborted, Reason} -> {error, {table_creation_failed, Name, Reason}}
    end.

seed_if_empty() ->
    case transaction(fun() ->
        case mnesia:table_info(?UNITS, size) of
            0 ->
                Now = timestamp(),
                Seeds = [
                    {<<"reg-central">>, <<"region">>, <<"CTR">>, <<"المنطقة الوسطى"/utf8>>, undefined},
                    {<<"cam-riyadh">>, <<"campus">>, <<"RUH">>, <<"فرع الرياض"/utf8>>, <<"reg-central">>},
                    {<<"col-computing">>, <<"college">>, <<"CCS">>, <<"كلية الحوسبة"/utf8>>, <<"cam-riyadh">>},
                    {<<"dep-cs">>, <<"department">>, <<"CS">>, <<"علوم الحاسب"/utf8>>, <<"col-computing">>},
                    {<<"prg-software">>, <<"program">>, <<"SE-BS">>, <<"بكالوريوس هندسة البرمجيات"/utf8>>, <<"dep-cs">>}
                ],
                lists:foreach(fun({Id, Type, Code, Name, ParentId}) ->
                    Unit = {academic_unit, Id, Type, Code, Name, ParentId,
                        <<"active">>, Now, Now},
                    mnesia:write(?UNITS, Unit, write)
                end, Seeds),
                ok;
            _ -> ok
        end
    end) of
        {ok, ok} -> ok;
        {error, _} = Error -> Error
    end.

ensure_schema() ->
    case mnesia:create_schema([node()]) of
        ok -> ok;
        {error, {_, {already_exists, _}}} -> ok;
        {error, {already_exists, _}} -> ok;
        {error, Reason} -> {error, {schema_creation_failed, Reason}}
    end.

with_valid_input(Input, Existing, Continue) ->
    Type = maps:get(<<"type">>, Input, existing_type(Existing)),
    Code = normalize_text(maps:get(<<"code">>, Input, undefined)),
    Name = normalize_text(maps:get(<<"name">>, Input, undefined)),
    ParentId = normalize_parent(maps:get(<<"parentId">>, Input, undefined)),
    Status = maps:get(<<"status">>, Input, <<"active">>),
    case {valid_type(Type), valid_text(Code, 24), valid_text(Name, 100),
          valid_status(Status), valid_parent_shape(Type, ParentId)} of
        {true, true, true, true, true} ->
            Continue([Type, normalize_code(Code), Name, ParentId, Status]);
        {false, _, _, _, _} -> {error, invalid_type};
        {_, false, _, _, _} -> {error, invalid_code};
        {_, _, false, _, _} -> {error, invalid_name};
        {_, _, _, false, _} -> {error, invalid_status};
        _ -> {error, invalid_parent}
    end.

validate_unit(Unit, ExcludedId) ->
    Type = element(3, Unit),
    Code = element(4, Unit),
    ParentId = element(6, Unit),
    Units = mnesia:foldl(fun(Existing, Acc) -> [Existing | Acc] end, [], ?UNITS),
    case lists:any(fun(Existing) ->
        element(2, Existing) =/= ExcludedId andalso
        element(3, Existing) =:= Type andalso
        element(4, Existing) =:= Code andalso
        element(6, Existing) =:= ParentId
    end, Units) of
        true -> mnesia:abort({domain_error, duplicate_code});
        false -> validate_parent(Type, ParentId, Units)
    end.

validate_parent(<<"region">>, undefined, _Units) -> ok;
validate_parent(_Type, undefined, _Units) ->
    mnesia:abort({domain_error, parent_required});
validate_parent(Type, ParentId, Units) ->
    Expected = parent_type(Type),
    case lists:keyfind(ParentId, 2, Units) of
        false -> mnesia:abort({domain_error, parent_not_found});
        Parent ->
            case {element(3, Parent), element(7, Parent)} of
                {Expected, <<"active">>} -> ok;
                {Expected, _} -> mnesia:abort({domain_error, parent_inactive});
                _ -> mnesia:abort({domain_error, invalid_parent})
            end
    end.

valid_parent_shape(<<"region">>, undefined) -> true;
valid_parent_shape(<<"region">>, _ParentId) -> false;
valid_parent_shape(_Type, ParentId) -> is_binary(ParentId) andalso byte_size(ParentId) > 0.

valid_type(<<"region">>) -> true;
valid_type(<<"campus">>) -> true;
valid_type(<<"college">>) -> true;
valid_type(<<"department">>) -> true;
valid_type(<<"program">>) -> true;
valid_type(_) -> false.

valid_status(<<"active">>) -> true;
valid_status(<<"inactive">>) -> true;
valid_status(_) -> false.

valid_text(Value, MaxLength) when is_binary(Value) ->
    Size = byte_size(Value),
    Size > 0 andalso Size =< MaxLength andalso
        string:trim(unicode:characters_to_list(Value)) =/= [];
valid_text(_, _) -> false.

normalize_text(Value) when is_binary(Value) ->
    unicode:characters_to_binary(string:trim(unicode:characters_to_list(Value)));
normalize_text(_) -> undefined.

normalize_code(Code) ->
    unicode:characters_to_binary(string:uppercase(unicode:characters_to_list(Code))).

normalize_parent(null) -> undefined;
normalize_parent(undefined) -> undefined;
normalize_parent(Value) when is_binary(Value) -> Value;
normalize_parent(_) -> invalid.

parent_type(<<"campus">>) -> <<"region">>;
parent_type(<<"college">>) -> <<"campus">>;
parent_type(<<"department">>) -> <<"college">>;
parent_type(<<"program">>) -> <<"department">>.

existing_type(undefined) -> undefined;
existing_type(Existing) -> element(3, Existing).

unit_map({academic_unit, Id, Type, Code, Name, ParentId, Status, CreatedAt, UpdatedAt}) ->
    #{<<"id">> => Id, <<"type">> => Type, <<"code">> => Code,
      <<"name">> => Name, <<"parentId">> => json_parent(ParentId),
      <<"status">> => Status, <<"createdAt">> => CreatedAt,
      <<"updatedAt">> => UpdatedAt}.

activity_map({activity_record, Id, Action, Name, Detail, OccurredAt}) ->
    #{<<"id">> => Id, <<"action">> => Action, <<"name">> => Name,
      <<"detail">> => Detail, <<"createdAt">> => OccurredAt}.

json_parent(undefined) -> null;
json_parent(ParentId) -> ParentId.

log_activity(Action, Unit) ->
    ParentId = element(6, Unit),
    Detail = case ParentId of
        undefined -> <<"الهيكل الأكاديمي">>;
        _ -> case mnesia:read(?UNITS, ParentId, read) of
            [Parent] -> element(5, Parent);
            [] -> <<"الهيكل الأكاديمي">>
        end
    end,
    Event = {activity_record, new_id(), Action, element(5, Unit), Detail, timestamp()},
    mnesia:write(?ACTIVITY, Event, write).

unit_order(A, B) -> element(5, A) < element(5, B).
activity_order(A, B) -> element(6, A) > element(6, B).

transaction(Fun) ->
    case mnesia:transaction(Fun) of
        {atomic, Result} -> {ok, Result};
        {aborted, {domain_error, Reason}} -> {error, Reason};
        {aborted, Reason} -> {error, {storage_error, Reason}}
    end.

new_id() ->
    << <<(hex_digit(N bsr 4)), (hex_digit(N band 15))>> ||
        <<N>> <= crypto:strong_rand_bytes(16) >>.

hex_digit(N) when N < 10 -> $0 + N;
hex_digit(N) -> $a + N - 10.

timestamp() ->
    list_to_binary(calendar:system_time_to_rfc3339(
        erlang:system_time(second), [{unit, second}, {offset, "Z"}])).

data_dir() ->
    case os:getenv("UNIVERSITYERL_DATA_DIR") of
        false -> filename:absname("data/mnesia");
        Path -> filename:absname(Path)
    end.