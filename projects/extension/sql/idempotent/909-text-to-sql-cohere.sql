--FEATURE-FLAG: text_to_sql

-------------------------------------------------------------------------------
-- text_to_sql_cohere
create or replace function ai.text_to_sql_cohere
( model pg_catalog.text
, api_key text default null
, api_key_name text default null
, max_tokens int default null
, stop_sequences text[] default null
, temperature float8 default null
, seed int default null
, frequency_penalty float8 default null
, presence_penalty float8 default null
, k int default null
, p float8 default null
, logprobs boolean default null
, max_iter pg_catalog.int2 default null
, max_results pg_catalog.int8 default null
, max_vector_dist pg_catalog.float8 default null
, min_ts_rank pg_catalog.float4 default null
, obj_renderer pg_catalog.regprocedure default null
, sql_renderer pg_catalog.regprocedure default null
) returns pg_catalog.jsonb
as $func$
    select json_object
    ( 'provider': 'cohere'
    , 'model': model
    , 'api_key': api_key
    , 'api_key_name': api_key_name
    , 'max_tokens': max_tokens
    , 'stop_sequences': stop_sequences
    , 'temperature': temperature
    , 'seed': seed
    , 'frequency_penalty': frequency_penalty
    , 'presence_penalty': presence_penalty
    , 'k': k
    , 'p': p
    , 'logprobs': logprobs
    , 'max_iter': max_iter
    , 'max_results': max_results
    , 'max_vector_dist': max_vector_dist
    , 'min_ts_rank': min_ts_rank
    , 'obj_renderer': obj_renderer
    , 'sql_renderer': sql_renderer
    absent on null
    )
$func$ language sql immutable security invoker
set search_path to pg_catalog, pg_temp
;

-------------------------------------------------------------------------------
-- _text_to_sql_cohere
create function ai._text_to_sql_cohere
( question text
, catalog_name text default 'default'
, config jsonb default null
) returns jsonb
as $func$
declare
    _config jsonb = config;
    _tools jsonb;
    _catalog_name text = catalog_name;
    _max_iter int2;
    _iter_remaining int2;
    _max_results int8;
    _max_vector_dist float8;
    _min_ts_rank real;
    _obj_renderer regprocedure;
    _sql_renderer regprocedure;
    _model text;
    _api_key text;
    _api_key_name text;
    _max_tokens int;
    _stop_sequences text[];
    _temperature float8;
    _seed int;
    _frequency_penalty float8;
    _presence_penalty float8;
    _k int;
    _p float8;
    _logprobs boolean;
    _system_prompt text;
    _questions jsonb = jsonb_build_array(question);
    _questions_embedded @extschema:vector@.vector[];
    _keywords jsonb = jsonb_build_array();
    _ctx_obj jsonb = jsonb_build_array();
    _ctx_sql jsonb = jsonb_build_array();
    _sql text;
    _prompt_obj text;
    _prompt_sql text;
    _prompt text;
    _response jsonb;
    _tool_call record;
    _answer text;
begin
    -- if a config was provided, use the settings available. defaults where missing
    -- if no config provided, use defaults for everything
    _max_iter = coalesce(case when _config is not null then (_config->>'max_iter')::int2 end, 10);
    _iter_remaining = _max_iter;
    _max_results = coalesce(case when _config is not null then (_config->>'max_results')::int8 end, 5);
    _max_vector_dist = case when _config is not null then (_config->>'max_vector_dist')::float8 end;
    _min_ts_rank = case when _config is not null then (_config->>'min_ts_rank')::real end;
    _obj_renderer = coalesce(case when _config is not null then (_config->>'obj_renderer')::pg_catalog.regprocedure end, 'ai.render_semantic_catalog_obj(bigint, oid, oid)'::pg_catalog.regprocedure);
    _sql_renderer = coalesce(case when _config is not null then (_config->>'sql_renderer')::pg_catalog.regprocedure end, 'ai.render_semantic_catalog_sql(bigint, text, text)'::pg_catalog.regprocedure);
    _model = coalesce(case when _config is not null and _config operator(pg_catalog.?) 'model' then _config->>'model' end, 'claude-3-5-sonnet-latest');
    _api_key = (case when _config is not null then _config operator(pg_catalog.->>) 'api_key' end);
    _api_key_name = (case when _config is not null then _config operator(pg_catalog.->>) 'api_key_name' end);
    _max_tokens = (case when _config is not null then _config operator(pg_catalog.->>) 'max_tokens' end)::int4;
    _stop_sequences = (case when _config is not null then (select array_agg(x) from jsonb_array_elements_text(_config operator(pg_catalog.->) '_stop_sequences') x) end);
    _temperature = (case when _config is not null then _config operator(pg_catalog.->>) 'temperature' end)::float8;
    _seed = (case when _config is not null then _config operator(pg_catalog.->>) 'seed' end)::int4;
    _frequency_penalty = (case when _config is not null then _config operator(pg_catalog.->>) 'frequency_penalty' end)::float8;
    _presence_penalty = (case when _config is not null then _config operator(pg_catalog.->>) 'presence_penalty' end)::float8;
    _k = (case when _config is not null then _config operator(pg_catalog.->>) 'k' end)::int;
    _p = (case when _config is not null then _config operator(pg_catalog.->>) 'p' end)::float8;
    _logprobs = (case when _config is not null then _config operator(pg_catalog.->>) 'logprobs' end)::boolean;
    _system_prompt = pg_catalog.concat_ws
    ( ' '
    , 'You are an expert at analyzing PostgreSQL database schemas and writing SQL statements to answer questions.'
    , 'You have access to tools.'
    );

    while _iter_remaining > 0 loop
        raise debug 'iteration: %', (_max_iter - _iter_remaining + 1);
        raise debug 'searching with % questions', jsonb_array_length(_questions);
        raise debug 'searching with % sets of keywords', jsonb_array_length(_keywords);

        -- search -------------------------------------------------------------

        -- embed questions
        if jsonb_array_length(_questions) > 0 then
            raise debug 'embedding % questions', jsonb_array_length(_questions);
            select array_agg(ai._semantic_catalog_embed(k.id, q))
            into strict _questions_embedded
            from ai.semantic_catalog k
            cross join jsonb_array_elements_text(_questions) q
            where k.catalog_name = _catalog_name
            ;
        end if;

        -- search obj
        if jsonb_array_length(_questions) > 0 or jsonb_array_length(_keywords) > 0 then
            raise debug 'searching for database objects';
            select jsonb_agg(x.obj)
            into _ctx_obj
            from
            (
                select jsonb_build_object
                ( 'id', row_number() over (order by x.objid)
                , 'classid', x.classid
                , 'objid', x.objid
                ) as obj
                from
                (
                    -- search for relevant objects
                    -- if a column matches, we want to render the whole table/view, so discard the objsubid
                    -- semantic search
                    select distinct x.classid, x.objid
                    from unnest(_questions_embedded) q
                    cross join lateral ai._search_semantic_catalog_obj
                    ( q
                    , catalog_name
                    , _max_results
                    , _max_vector_dist
                    ) x
                    union
                    -- keyword search
                    select distinct x.classid, x.objid
                    from jsonb_to_recordset(_keywords) k(keywords text[])
                    cross join lateral ai._search_semantic_catalog_obj
                    ( k.keywords
                    , catalog_name
                    , _max_results
                    , _min_ts_rank
                    ) x
                    union
                    -- unroll objects previously marked as relevant
                    select *
                    from jsonb_to_recordset(_ctx_obj) r(classid oid, objid oid)
                ) x
            ) x
            ;
            raise debug 'search found % database objects', jsonb_array_length(_ctx_obj);
        end if;

        -- search sql
        if jsonb_array_length(_questions) > 0 or jsonb_array_length(_keywords) > 0 then
            raise debug 'searching for sql examples';
            select jsonb_agg(x)
            into _ctx_sql
            from
            (
                -- search for relevant sql examples
                -- semantic search
                select distinct x.id, x.sql, x.description
                from unnest(_questions_embedded) q
                cross join lateral ai._search_semantic_catalog_sql
                ( q
                , catalog_name
                , _max_results
                , _max_vector_dist
                ) x
                union
                -- keyword search
                select distinct x.id, x.sql, x.description
                from jsonb_to_recordset(_keywords) k(keywords text[])
                cross join lateral ai._search_semantic_catalog_sql
                ( k.keywords
                , catalog_name
                , _max_results
                , _min_ts_rank
                ) x
                union
                -- unroll sql examples previously marked as relevant
                select *
                from jsonb_to_recordset(_ctx_sql) r(id int, sql text, description text)
            ) x
            ;
            raise debug 'search found % sql examples', coalesce(jsonb_array_length(_ctx_sql), 0);
        end if;

        -- reset our search params
        _questions = jsonb_build_array();
        _questions_embedded = null;
        _keywords = jsonb_build_array();

        -- render prompt ------------------------------------------------------
        -- render obj
        raise debug 'rendering database objects';
        select format
        ( $sql$
        select string_agg(%I.%I(x.id, x.classid, x.objid), E'\n\n')
        from jsonb_to_recordset($1) x(id bigint, classid oid, objid oid)
        $sql$
        , n.nspname
        , f.proname
        )
        into strict _sql
        from pg_proc f
        inner join pg_namespace n on (f.pronamespace = n.oid)
        where f.oid = _obj_renderer::oid
        ;
        execute _sql using _ctx_obj into _prompt_obj;

        -- render sql
        raise debug 'rendering sql examples';
        select format
        ( $sql$
        select string_agg(%I.%I(x.id, x.sql, x.description), E'\n\n')
        from jsonb_to_recordset($1) x(id int, sql text, description text)
        $sql$
        , n.nspname
        , f.proname
        )
        into strict _sql
        from pg_proc f
        inner join pg_namespace n on (f.pronamespace = n.oid)
        where f.oid = _sql_renderer::oid
        ;
        execute _sql using _ctx_sql into _prompt_sql;

        -- render the user prompt
        select concat_ws
        ( E'\n'
        , $$Below are descriptions of database objects and examples of SQL statements that are meant to give context to a user's question.$$
        , $$Analyze the context provided. Identify the elements that are relevant to the user's question.$$
        , $$If enough context has been provided to confidently address the question, use the "answer_user_question_with_sql_statement" tool to record your final answer in the form of a valid SQL statement.$$
        , E'\n'
        , coalesce(_prompt_obj, '')
        , E'\n'
        , coalesce(_prompt_sql, '')
        , E'\n'
        , concat('Q: ', question)
        , 'A: '
        ) into strict _prompt
        ;
        raise debug '%', _prompt;

        -- call llm -----------------------------------------------------------
        /*
            {
                "type": "function":
                "function": {
                    "name": "request_more_context_by_keywords",
                    "description": "If you do not have enough context to confidently answer the user's question, use this tool to ask for more context by providing a list of keywords to use in performing a full-text search.",
                    "parameters": {
                        "type": "object",
                        "properties" : {
                            "keywords": {
                                "type": "array",
                                "items": {"type": "string"},
                                "description": "A list of keywords relevant to the user's question that will be used to perform a full-text search to gather more context. Each item must be a single word with no whitespace."
                            }
                        },
                        "required": ["keywords"],
                        "additionalProperties": false
                    },
                    "strict": true
                }
            },
        */
        _tools = $json$
        [
            {
                "type": "function",
                "function": {
                    "name": "request_more_context_by_question",
                    "description": "If you do not have enough context to confidently answer the user's question, use this tool to ask for more context by providing a question to be used for semantic search.",
                    "parameters": {
                        "type": "object",
                        "properties" : {
                            "question": {
                                "type": "string",
                                "description": "A new natural language question relevant to the user's question that will be used to perform a semantic search to gather more context"
                            }
                        },
                        "required": ["question"],
                        "additionalProperties": false
                    },
                    "strict": true
                }
            },
            {
                "type": "function",
                "function": {
                    "name": "answer_user_question_with_sql_statement",
                    "description": "If you have enough context to confidently answer the user's question, use this tool to provide the answer in the form of a valid PostgreSQL SQL statement.",
                    "parameters": {
                        "type": "object",
                        "properties" : {
                            "sql_statement": {
                                "type": "string",
                                "description": "A valid SQL statement that addresses the user's question."
                            },
                            "relevant_database_object_ids": {
                                "type": "array",
                                "items": {"type": "integer"},
                                "description": "Provide a list of the ids of the database examples which were relevant to the user's question and useful in providing the answer."
                            },
                            "relevant_sql_example_ids": {
                                "type": "array",
                                "items": {"type": "integer"},
                                "description": "Provide a list of the ids of the SQL examples which were relevant to the user's question and useful in providing the answer."
                            }
                        },
                        "required": ["sql_statement", "relevant_database_object_ids", "relevant_sql_example_ids"],
                        "additionalProperties": false
                    },
                    "strict": true
                }
            }
        ]
        $json$::jsonb
        ;

        raise debug 'calling llm';
        select ai.cohere_chat_complete
        ( _model
        , jsonb_build_array
          ( jsonb_build_object('role', 'system', 'content', _system_prompt)
          , jsonb_build_object('role', 'user', 'content', _prompt)
          )
        , tools=>_tools
        , api_key=>_api_key
        , api_key_name=>_api_key_name
        , max_tokens=>_max_tokens
        , stop_sequences=>_stop_sequences
        , temperature=>_temperature
        , seed=>_seed
        , frequency_penalty=>_frequency_penalty
        , presence_penalty=>_presence_penalty
        , k=>_k
        , p=>_p
        , logprobs=>_logprobs
        , tool_choice=>'REQUIRED'
        , strict_tools=>true
        ) into strict _response
        ;

        -- process the response -----------------------------------------------
        raise debug 'response: %', jsonb_pretty(_response);
        for _tool_call in
        (
            select
              t.id
            , t.type
            , t.function->>'name' as name
            , (t.function->>'arguments')::jsonb as arguments -- it's a string *containing* json :eyeroll:
            from jsonb_to_recordset(_response->'message'->'tool_calls') t
            ( id text
            , type text
            , function jsonb
            )
        )
        loop
            case _tool_call.name
                when 'request_more_context_by_question' then
                    raise debug 'tool use: request_more_context_by_question: %', _tool_call.arguments->'question';
                    -- append the question to the list of questions to use on the next iteration
                    select _questions || jsonb_build_array(_tool_call.arguments->'question')
                    into strict _questions
                    ;
                when 'request_more_context_by_keywords' then
                    raise debug 'tool use: request_more_context_by_keywords: %', _tool_call.arguments->'keywords';
                    -- append the keywords to the list of keywords to use on the next iteration
                    select _keywords || jsonb_build_array(jsonb_build_object('keywords', _tool_call.arguments->'keywords'))
                    into strict _keywords
                    ;
                when 'answer_user_question_with_sql_statement' then
                    raise debug 'tool use: answer_user_question_with_sql_statement: %', _tool_call.arguments;
                    select _tool_call.arguments->>'sql_statement' into strict _answer;
                    -- throw out any obj that the LLM did NOT mark as relevant
                    select jsonb_agg(r) into _ctx_obj
                    from jsonb_array_elements_text(_tool_call.arguments->'relevant_database_object_ids') i
                    inner join jsonb_to_recordset(_ctx_obj) r(id bigint, classid oid, objid oid)
                    on (i::bigint = r.id)
                    ;
                    -- throw out any sql that the LLM did NOT mark as relevant
                    select jsonb_agg(r) into _ctx_sql
                    from jsonb_array_elements_text(_tool_call.arguments->'relevant_sql_example_ids') i
                    inner join jsonb_to_recordset(_ctx_sql) r(id bigint, sql text, description text)
                    on (i::int = r.id)
                    ;
                    return jsonb_build_object
                    ( 'sql_statement', _answer
                    , 'relevant_database_objects', _ctx_obj
                    , 'relevant_sql_examples', _ctx_sql
                    , 'iterations', (_max_iter - _iter_remaining)
                    );
            end case
            ;
        end loop;
        _iter_remaining = _iter_remaining - 1;
    end loop;
    return null;
end
$func$ language plpgsql stable security invoker
set search_path to pg_catalog, pg_temp
;
