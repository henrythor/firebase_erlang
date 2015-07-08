% file: firebase.erl
-module(firebase).
-export([get/1, get/2]).

% TODO: in-memory caching

get(Path) ->
    get(Path, []).

get(Path, Opts) ->
    Url = application:get_env(firebase, url),
    AuthToken = gen_server:call(firebase_auth_srv, get_token),
    Shallow = proplists:get_value(shallow, Opts, false),
    _Fresh = proplists:get_value(fresh, Opts, false),
    FullUrl = lists:flatten(io_lib:format("~s/~s?auth=~s&shallow=~s",
        [Url, Path, AuthToken, Shallow])),
    Fetch = fun(URL) ->
        case {httpc_return, httpc:request(URL)} of
            {httpc_return, {ok, {{_,200,_}, _, Result}}} ->
                case {result, jiffy:decode(Result)} of
                    {result, {Proplist}} when is_list(Proplist) ->
                        {ok, Proplist};
                    {result, _} ->
                        {ok, []}
                end;
            {httpc_return, {ok, {{_,401,_}, _, ErrJSON}}} ->
                case {errjson, jiffy:decode(ErrJSON)} of
                    {errjson, {ErrorList}} when is_list(ErrorList) ->
                        case {err, proplists:get_value(<<"error">>, ErrorList)} of
                            {err, <<"Auth token is expired">>} ->
                                {error, auth_token_expired};
                            {err, <<"Permission denied">>} ->
                                {error, permission_denied};
                            {err, Error} ->
                                {error, Error}
                        end;
                    {errjson, Error} ->
                        {error, Error}
                end;
            {httpc_return, {ok, {{_,Errcode,_}, _, _Content}}} ->
                {error, Errcode};
            {httpc_return, {error, Error}} ->
                {error, Error}
        end
    end,
    % Check cache, if it exists in cache and isn't too old, return from cache
    % otherwise run Fetch(Url) and insert into cache if we get an 'ok' response.
    % If Fresh is true, just return from Fetch and update cache.
    Fetch(FullUrl).
