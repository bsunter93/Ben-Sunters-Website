-- Knock-On v5 / W2: migration ripples_v5_pipeline_payload_resume
-- ripples._job_payload: a retried screen job only asks for titles not yet screened, a retried split job only for hops
-- not yet split (partial results of a rate-limited job are kept). The definition is the one in sql/02 (re-declared
-- there so a fresh install gets it directly); this file is kept as the record of the applied migration.
select 'ripples._job_payload is defined in 02_ripples_v5_pipeline_ingest.sql' as note;
