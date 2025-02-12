-- add verbose boolean to all model calling functions

-- drop all functions that have verbose args before the arg was added.
-- list generated by the following query:
-- SELECT 'DROP FUNCTION IF EXISTS ' || ns.nspname || '.' || proname || '(' || 
--   array_to_string(proargtypes[0:array_length(proargtypes, 1)-2]::regtype[], ', ') || ');' as drop_command 
-- FROM pg_proc p 
-- JOIN pg_namespace ns ON p.pronamespace = ns.oid 
-- WHERE proargnames @> ARRAY['verbose'];

DROP FUNCTION IF EXISTS ai.openai_chat_complete(text, jsonb, text, text, text, double precision, jsonb, boolean, integer, integer, integer, integer, double precision, jsonb, integer, text, double precision, double precision, jsonb, text, text, jsonb, jsonb, jsonb, double precision);
DROP FUNCTION IF EXISTS ai.openai_list_models(text, text, text, jsonb, jsonb, double precision);
DROP FUNCTION IF EXISTS ai.openai_list_models_with_raw_response(text, text, text, jsonb, jsonb, double precision);
DROP FUNCTION IF EXISTS ai.openai_embed(text, text, text, text, text, integer, text, jsonb, jsonb, jsonb, double precision);
DROP FUNCTION IF EXISTS ai.openai_embed(text, text[], text, text, text, integer, text, jsonb, jsonb, jsonb, double precision);
DROP FUNCTION IF EXISTS ai.openai_embed(text, integer[], text, text, text, integer, text, jsonb, jsonb, jsonb, double precision);
DROP FUNCTION IF EXISTS ai.openai_embed_with_raw_response(text, text, text, text, text, integer, text, jsonb, jsonb, jsonb, double precision);
DROP FUNCTION IF EXISTS ai.openai_embed_with_raw_response(text, text[], text, text, text, integer, text, jsonb, jsonb, jsonb, double precision);
DROP FUNCTION IF EXISTS ai.openai_embed_with_raw_response(text, integer[], text, text, text, integer, text, jsonb, jsonb, jsonb, double precision);
DROP FUNCTION IF EXISTS ai.openai_chat_complete_with_raw_response(text, jsonb, text, text, text, double precision, jsonb, boolean, integer, integer, integer, integer, double precision, jsonb, integer, text, double precision, double precision, jsonb, text, text, jsonb, jsonb, jsonb, double precision);
DROP FUNCTION IF EXISTS ai.openai_chat_complete_simple(text, text, text);
DROP FUNCTION IF EXISTS ai.openai_moderate(text, text, text, text, text, jsonb, jsonb, jsonb, double precision);
DROP FUNCTION IF EXISTS ai.openai_moderate_with_raw_response(text, text, text, text, text, jsonb, jsonb, jsonb, double precision);
DROP FUNCTION IF EXISTS ai.ollama_list_models(text);
DROP FUNCTION IF EXISTS ai.ollama_ps(text);
DROP FUNCTION IF EXISTS ai.ollama_embed(text, text, text, text, jsonb);
DROP FUNCTION IF EXISTS ai.ollama_generate(text, text, text, bytea[], text, jsonb, text, text, integer[]);
DROP FUNCTION IF EXISTS ai.ollama_chat_complete(text, jsonb, text, text, jsonb, jsonb, jsonb);
DROP FUNCTION IF EXISTS ai.anthropic_list_models(text, text, text);
DROP FUNCTION IF EXISTS ai.anthropic_generate(text, jsonb, integer, text, text, text, double precision, integer, text, text, text[], double precision, jsonb, jsonb, integer, double precision);
DROP FUNCTION IF EXISTS ai.cohere_list_models(text, text, text, boolean);
DROP FUNCTION IF EXISTS ai.cohere_tokenize(text, text, text, text);
DROP FUNCTION IF EXISTS ai.cohere_detokenize(text, integer[], text, text);
DROP FUNCTION IF EXISTS ai.cohere_embed(text, text, text, text, text, text);
DROP FUNCTION IF EXISTS ai.cohere_classify(text, text[], text, text, jsonb, text);
DROP FUNCTION IF EXISTS ai.cohere_classify_simple(text, text[], text, text, jsonb, text);
DROP FUNCTION IF EXISTS ai.cohere_rerank(text, text, text[], text, text, integer, integer);
DROP FUNCTION IF EXISTS ai.cohere_rerank_simple(text, text, text[], text, text, integer, integer);
DROP FUNCTION IF EXISTS ai.cohere_chat_complete(text, jsonb, text, text, jsonb, jsonb, jsonb, jsonb, text, integer, text[], double precision, integer, double precision, double precision, integer, double precision, boolean, text, boolean);
DROP FUNCTION IF EXISTS ai.voyageai_embed(text, text, text, text, text);
DROP FUNCTION IF EXISTS ai.voyageai_embed(text, text[], text, text, text);
DROP FUNCTION IF EXISTS ai.litellm_embed(text, text, text, text, jsonb);
DROP FUNCTION IF EXISTS ai.litellm_embed(text, text[], text, text, jsonb);