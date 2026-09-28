-module(universityerl_store_tests).

-include_lib("eunit/include/eunit.hrl").

store_test_() ->
    {setup,
        fun start_store/0,
        fun stop_store/1,
        [
            ?_test(rejects_duplicate_sibling_codes()),
            ?_test(rejects_a_parent_of_the_wrong_type()),
            ?_test(prevents_deleting_a_parent_with_children()),
            ?_test(prevents_changing_a_unit_type()),
            ?_test(requires_active_parents_for_new_units()),
            ?_test(updates_unit_and_records_activity())
        ]}.

start_store() ->
    DataDir = filename:join("/tmp", "universityerl_eunit_" ++
        integer_to_list(erlang:unique_integer([positive]))),
    true = os:putenv("UNIVERSITYERL_DATA_DIR", DataDir),
    ok = universityerl_store:start(),
    DataDir.

stop_store(DataDir) ->
    ok = application:stop(mnesia),
    ok = mnesia:delete_schema([node()]),
    ok = file:del_dir_r(DataDir),
    true = os:unsetenv("UNIVERSITYERL_DATA_DIR"),
    ok.

rejects_duplicate_sibling_codes() ->
    Input = unit(<<"region">>, <<"TST">>, <<"منطقة اختبار">>, null, <<"active">>),
    ?assertMatch({ok, _}, universityerl_store:create_unit(Input)),
    ?assertEqual({error, duplicate_code}, universityerl_store:create_unit(Input)).

rejects_a_parent_of_the_wrong_type() ->
    Input = unit(<<"college">>, <<"BAD">>, <<"كلية غير صالحة">>,
        <<"reg-central">>, <<"active">>),
    ?assertEqual({error, invalid_parent}, universityerl_store:create_unit(Input)).

prevents_deleting_a_parent_with_children() ->
    ?assertEqual({error, has_children}, universityerl_store:delete_unit(<<"reg-central">>)).

prevents_changing_a_unit_type() ->
    Input = unit(<<"campus">>, <<"CTR">>, <<"المنطقة الوسطى">>,
        <<"reg-central">>, <<"active">>),
    ?assertEqual({error, type_immutable},
        universityerl_store:update_unit(<<"reg-central">>, Input)).

requires_active_parents_for_new_units() ->
    Region = unit(<<"region">>, <<"OFF">>, <<"منطقة غير نشطة">>, null, <<"inactive">>),
    {ok, Created} = universityerl_store:create_unit(Region),
    Campus = unit(<<"campus">>, <<"OFF-C">>, <<"فرع تجريبي">>,
        maps:get(<<"id">>, Created), <<"active">>),
    ?assertEqual({error, parent_inactive}, universityerl_store:create_unit(Campus)).

updates_unit_and_records_activity() ->
    Input = unit(<<"region">>, <<"UPD">>, <<"منطقة قبل التعديل">>, null, <<"active">>),
    {ok, Created} = universityerl_store:create_unit(Input),
    Id = maps:get(<<"id">>, Created),
    UpdatedInput = unit(<<"region">>, <<"UPD2">>, <<"منطقة بعد التعديل">>, null, <<"inactive">>),
    {ok, Updated} = universityerl_store:update_unit(Id, UpdatedInput),
    ?assertEqual(<<"منطقة بعد التعديل">>, maps:get(<<"name">>, Updated)),
    ?assertEqual(<<"UPD2">>, maps:get(<<"code">>, Updated)),
    ?assertEqual(<<"inactive">>, maps:get(<<"status">>, Updated)),
    {ok, Activity} = universityerl_store:list_activity(),
    ?assert(lists:any(fun(Event) ->
        maps:get(<<"action">>, Event) =:= <<"تعديل">> andalso
        maps:get(<<"name">>, Event) =:= <<"منطقة بعد التعديل">>
    end, Activity)).

unit(Type, Code, Name, ParentId, Status) ->
    #{<<"type">> => Type, <<"code">> => Code, <<"name">> => Name,
      <<"parentId">> => ParentId, <<"status">> => Status}.