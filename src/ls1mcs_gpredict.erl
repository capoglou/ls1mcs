%/--------------------------------------------------------------------
%| Copyright 2013-2014 Karolis Petrauskas
%|
%| Licensed under the Apache License, Version 2.0 (the "License");
%| you may not use this file except in compliance with the License.
%| You may obtain a copy of the License at
%|
%|     http://www.apache.org/licenses/LICENSE-2.0
%|
%| Unless required by applicable law or agreed to in writing, software
%| distributed under the License is distributed on an "AS IS" BASIS,
%| WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%| See the License for the specific language governing permissions and
%| limitations under the License.
%\--------------------------------------------------------------------

%%
%%  Predicted pass parser for GPredict.
%%
%%  1. Edit -> Preferences -> Predict:
%%      Pass Conditions:
%%          Number of passes to predict: 50
%%          Passes should occur within: 14
%%      Multiple passes:
%%          Select all options.
%%  2. Configure correct GS position.
%%  3. Select SAT in the map.
%%  4. In the SAT info view, press options button [v], and select "Future Passes".
%%  5. Click Save, then:
%%      Choose folder:  temp/data/gpredict/
%%      Filename:       gpredict-passes-summary.txt
%%      Save as:        Plain text
%%      File contents:  Summary or Complete
%%
%%  See `test/data/gpredict-passes-complete.txt` for an example and a fragment of the data follows:
%%  =================
%%    Upcoming passes for AO-27
%%    Observer: sample, Copenhagen, Denmark
%%    LAT:55,62 LON:12,65
%%    ------------------------------------------------------------------------------------------------------------------------
%%     AOS                  TCA                  LOS                  Duration  Max El  AOS Az  Max El Az  LOS Az  Orbit  Vis
%%    ------------------------------------------------------------------------------------------------------------------------
%%     2013/07/21 23:57:26  2013/07/22 00:04:00  2013/07/22 00:10:34  00:13:07   17,63   24,78      85,62  147,42   3359  VDE
%%    ...
%%     2013/07/28 08:37:02  2013/07/28 08:41:28  2013/07/28 08:45:54  00:08:52    5,70   63,84      27,06  350,30   3450  -D-
%%
%%  =================
%%
%%  See `http://manpages.ubuntu.com/manpages/trusty/man1/predict.1.html` for alternative.
%%
-module(ls1mcs_gpredict).
-behaviour(gen_server).
-compile([{parse_transform, lager_transform}]).
-export([start_link/2, parse_predicted_sat_passes/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-include("ls1mcs.hrl").
-include_lib("kernel/include/file.hrl").


-define(COLUMNS, [
    <<"AOS">>,
    <<"TCA">>,
    <<"LOS">>,
    <<"Duration">>,
    <<"Max El">>,
    <<"AOS Az">>,
    <<"Max El Az">>,
    <<"LOS Az">>,
    <<"Orbit">>,
    <<"Vis">>
]).

%%
%%  Start file poller/db-loader.
%%
-spec start_link(string(), integer())
        -> {ok, pid()} | term().

start_link(Filename, CheckInterval) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, {Filename, CheckInterval}, []).


%%
%%  Load predicted passes from a file.
%%
-spec parse_predicted_sat_passes(string())
        -> {ok, [#predicted_pass{}]}.

parse_predicted_sat_passes(Filename) ->
    {ok, File} = file:open(Filename, [read, binary, raw, {read_ahead, 2048}]),
    Response = parse_next_line(File, file_header, undefined),
    file:close(File),
    Response.



%% =============================================================================
%%  Internal state of this module.
%% =============================================================================


-record(state, {
    filename,
    interval
}).



%% =============================================================================
%%  Callbacks for gen_server (unused).
%% =============================================================================


%%
%%
%%
init({Filename, CheckInterval}) ->
    State = #state{
        filename = Filename,
        interval = CheckInterval
    },
    erlang:send_after(CheckInterval, self(), {check}),
    {ok, State}.


%%
%%
%%
handle_call(_Msg, _From, State) ->
    {reply, undefined, State}.


%%
%%
%%
handle_cast(_Msg, State) ->
    {noreply, State}.


%%
%%  Loop with delay to check if file is available for processing.
%%
handle_info({check}, State = #state{filename = Filename, interval = CheckInterval}) ->
    case file:read_file_info(Filename) of
        {ok, #file_info{type = regular}} ->
            {ok, PredictedPasses} = parse_predicted_sat_passes(Filename),
            ok = ls1mcs_store:load_predicted_passes(PredictedPasses),
            ok = file:rename(Filename, Filename ++ ".processed"),
            lager:info("ls1mcs_gpredict: Predicted passes loaded from ~p", [Filename]);
        {error, enoent} ->
            ok
    end,
    erlang:send_after(CheckInterval, self(), {check}),
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
%%  Helper functions.
%% =============================================================================




%%
%%  Reads new line, strips "\n" if needed.
%%
parse_next_line(File, NextState, Data) ->
    case file:read_line(File) of
        {ok, <<>>} ->
            parse_predicted_passes(File, NextState, <<>>, Data);
        {ok, NextLine} ->
            case binary:last(NextLine) of
                $\n ->
                    NextLineWoLF = binary:part(NextLine, 0, byte_size(NextLine) - 1),
                    parse_predicted_passes(File, NextState, NextLineWoLF, Data);
                _ ->
                    parse_predicted_passes(File, NextState, NextLine, Data)
            end;
        eof ->
            parse_predicted_passes(File, NextState, eof, Data)
    end.


%%
%%  FSM, second parameter is a state.
%%
parse_predicted_passes(_File, file_header, eof, _Data) ->
    {error, premature_eof};

parse_predicted_passes(File, file_header, <<"------------------------------------------", _/binary>>,  Data) ->
    parse_next_line(File, summary_header, Data);

parse_predicted_passes(File, file_header, _Line, Data) ->
    parse_next_line(File, file_header, Data);

parse_predicted_passes(_File, summary_header, eof, _Data) ->
    {error, premature_eof};

parse_predicted_passes(File, summary_header, <<"------------------------------------------", _/binary>>,  Data) ->
    parse_next_line(File, summary_data, Data);

parse_predicted_passes(File, summary_header, Line, _Data) ->
    GetColPosFun = fun (ColName) ->
        case binary:match(Line, ColName) of
            {Pos, _Len} -> Pos;
            nomatch -> undefined
        end
    end,
    GetColLenFun = fun ({Pos, Name}, {PrevPos, Cols}) ->
        Len = case PrevPos of
            undefined -> undefined;
            _ -> PrevPos - Pos
        end,
        {Pos, [{Pos, Len, Name} | Cols]}
    end,
    ColPositions = [ {GetColPosFun(Col), Col} || Col <- ?COLUMNS ],
    SortedPositions = lists:sort(ColPositions),
    {_, ColsWithLen} = lists:foldr(GetColLenFun, {undefined, []}, SortedPositions),
    parse_next_line(File, summary_header, {ColsWithLen, []});

parse_predicted_passes(_File, summary_data, eof, {_ColDefs, ParsedRows}) ->
    {ok, lists:reverse(ParsedRows)};

parse_predicted_passes(_File, summary_data, <<>>, {_ColDefs, ParsedRows}) ->
    {ok, lists:reverse(ParsedRows)};

parse_predicted_passes(File, summary_data, Line, {ColDefs, ParsedRows}) ->
    GetColValueFun = fun ({Pos, Len, _Name}) ->
        case {Pos, Len} of
            {undefined, _} ->
                undefined;
            {_, undefined} ->
                <<_:Pos/binary, Value/binary>> = Line,
                Value;
            {_, _} ->
                <<_:Pos/binary, Value:Len/binary, _/binary>> = Line,
                Value
        end
    end,
    Values = [ GetColValueFun(ColDef) || ColDef <- ColDefs ],
    FormattedValues = format_predicted_pass(ColDefs, Values),
    parse_next_line(File, summary_data, {ColDefs, [FormattedValues | ParsedRows]}).


%%
%%  Make output.
%%
format_predicted_pass(ColDefs, Values) ->
    {Visible, Daylight, Eclipsed} = parse_visibility(get_predicted_pass_field(<<"Vis">>, ColDefs, Values)),
    #predicted_pass{
        aos = parse_tstamp(get_predicted_pass_field(<<"AOS">>, ColDefs, Values)),
        tca = parse_tstamp(get_predicted_pass_field(<<"TCA">>, ColDefs, Values)),
        los = parse_tstamp(get_predicted_pass_field(<<"LOS">>, ColDefs, Values)),
        duration = parse_duration(get_predicted_pass_field(<<"Duration">>, ColDefs, Values)),
        max_el = parse_float(get_predicted_pass_field(<<"Max El">>, ColDefs, Values)),
        aos_az = parse_float(get_predicted_pass_field(<<"AOS Az">>, ColDefs, Values)),
        max_el_az = parse_float(get_predicted_pass_field(<<"Max El Az">>, ColDefs, Values)),
        los_az = parse_float(get_predicted_pass_field(<<"LOS Az">>, ColDefs, Values)),
        orbit = parse_integer(get_predicted_pass_field(<<"Orbit">>, ColDefs, Values)),
        visible = Visible,
        daylight = Daylight,
        eclipsed = Eclipsed
    }.


get_predicted_pass_field(_Name, [], []) ->
    undefined;

get_predicted_pass_field(Name, [ {_Pos, _Len, Name} | _ColDefs], [Value | _Values]) ->
    Value;

get_predicted_pass_field(Name, [ _ColDef | ColDefs], [_Value | Values]) ->
    get_predicted_pass_field(Name, ColDefs, Values).


%%
%%  Decode timestamp.
%%  calendar:datetime_to_gregorian_seconds({{1970, 1, 1}, {0, 0, 0}}).
%%  Eg. "2013/07/21 23:57:26".
%%
-define(UNIX_BIRTH, 62167219200).
-define(MEGA_SECS, 1000000).
parse_tstamp(undefined) ->
    undefined;

parse_tstamp(DateBin) ->
    <<
        Year:4/binary, "/", Month:2/binary, "/", Day:2/binary, " ",
        Hour:2/binary, ":", Min:2/binary, ":", Sec:2/binary,
        _Whitespace/binary
    >> = DateBin,
    Date = {
        {binary_to_integer(Year), binary_to_integer(Month), binary_to_integer(Day)},
        {binary_to_integer(Hour), binary_to_integer(Min), binary_to_integer(Sec)}
    },
    DateSecs = calendar:datetime_to_gregorian_seconds(Date) - ?UNIX_BIRTH,
    {DateSecs div ?MEGA_SECS, DateSecs rem ?MEGA_SECS, 0}.


%%
%%  Parse duration to seconds.
%%  Eg. "00:13:07".
%%
parse_duration(undefined) ->
    undefined;

parse_duration(<<Hour:2/binary, ":", Min:2/binary, ":", Sec:2/binary, _Whitespace/binary>>) ->
    binary_to_integer(Hour) * 3600 + binary_to_integer(Min) * 60 + binary_to_integer(Sec).


%%
%%
%%
parse_float(undefined) ->
    undefined;

parse_float(NumberBin) ->
    Trimmed = trim(NumberBin),
    try erlang:binary_to_float(Trimmed) of
        Number -> Number
    catch
        _:_ ->
            erlang:binary_to_integer(Trimmed) * 1.0
    end.


%%
%%
%%
parse_integer(undefined) ->
    undefined;

parse_integer(NumberBin) ->
    Trimmed = trim(NumberBin),
    erlang:binary_to_integer(Trimmed).


%%
%%  VDE
%%
parse_visibility(undefined) ->
    {undefined, undefined, undefined};

parse_visibility(Visibility) ->
    Trimmed = trim(Visibility),
    <<V:1/binary, D:1/binary, E:1/binary>> = Trimmed,
    {
        V =:= <<"V">>,
        D =:= <<"D">>,
        E =:= <<"E">>
    }.


%%
%%  http://erlang.org/pipermail/erlang-questions/2009-June/044800.html
%%
trim(Bin) ->
    re:replace(Bin, "^\\s+|\\s+$", "", [{return, binary}, global]).


