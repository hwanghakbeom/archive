-- GE 사용량 분석 뷰 (네이티브 파티션 테이블 위). 데이터 적재(transfer) 후 실행.
--   bq query --use_legacy_sql=false < views.sql
-- 대상: `kis-gemini-common-prod.ge_logs.{obs_activity, data_access, activity}`
--   (DAY 파티션, field=timestamp / 중첩부 protoPayload·jsonPayload = JSON 타입 컬럼)
--
-- 주의:
--  * 중첩 필드는 JSON 타입 → JSON_VALUE(col,'$.path') 로 추출.
--  * 질문 = StreamAssist (AdvancedCompleteQuery=자동완성 제외).
--  * KST 일자 = DATE(timestamp, "Asia/Seoul").  timestamp는 파티션 키 → 날짜 필터 시 pruning.
--  * (★) observability(jsonPayload) 필드 경로는 실제 로그 샘플로 확정 필요.

------------------------------------------------------------------
-- 1) data_access — 계정×일 질문수
------------------------------------------------------------------
CREATE OR REPLACE VIEW `kis-gemini-common-prod.ge_logs.v_daily_user_questions` AS
SELECT
  DATE(timestamp, "Asia/Seoul")                                          AS event_date_kst,
  REGEXP_EXTRACT(logName, r'projects/([^/]+)/logs')                      AS project_id,
  JSON_VALUE(protoPayload, '$.authenticationInfo.principalEmail')        AS user_email,
  COUNTIF(REGEXP_EXTRACT(JSON_VALUE(protoPayload,'$.methodName'), r'[^.]+$') IN ('StreamAssist','AsyncAssist','ReadAsyncAssist')) AS questions,
  COUNTIF(REGEXP_EXTRACT(JSON_VALUE(protoPayload,'$.methodName'), r'[^.]+$') = 'Search')                AS searches,
  COUNTIF(REGEXP_EXTRACT(JSON_VALUE(protoPayload,'$.methodName'), r'[^.]+$') = 'AdvancedCompleteQuery') AS autocompletes,
  COUNT(*)                                                               AS total_events
FROM `kis-gemini-common-prod.ge_logs.data_access`
WHERE JSON_VALUE(protoPayload, '$.serviceName') = 'discoveryengine.googleapis.com'
  AND JSON_VALUE(protoPayload, '$.authenticationInfo.principalEmail') IS NOT NULL
  AND JSON_VALUE(protoPayload, '$.authenticationInfo.principalEmail') NOT LIKE '%gserviceaccount.com'
GROUP BY 1, 2, 3;

------------------------------------------------------------------
-- 2) data_access — 자회사×일 DAU / 질문자수
------------------------------------------------------------------
CREATE OR REPLACE VIEW `kis-gemini-common-prod.ge_logs.v_daily_active_users` AS
SELECT
  DATE(timestamp, "Asia/Seoul")                                            AS event_date_kst,
  REGEXP_EXTRACT(logName, r'projects/([^/]+)/logs')                        AS project_id,
  COUNT(DISTINCT JSON_VALUE(protoPayload,'$.authenticationInfo.principalEmail')) AS active_users,
  COUNT(DISTINCT IF(REGEXP_EXTRACT(JSON_VALUE(protoPayload,'$.methodName'), r'[^.]+$') IN ('StreamAssist','AsyncAssist'),
                    JSON_VALUE(protoPayload,'$.authenticationInfo.principalEmail'), NULL)) AS asking_users
FROM `kis-gemini-common-prod.ge_logs.data_access`
WHERE JSON_VALUE(protoPayload,'$.serviceName') = 'discoveryengine.googleapis.com'
  AND JSON_VALUE(protoPayload,'$.authenticationInfo.principalEmail') NOT LIKE '%gserviceaccount.com'
GROUP BY 1, 2;

------------------------------------------------------------------
-- 3) data_access — 기능별(NotebookLM / Idea / Search) 일별
------------------------------------------------------------------
CREATE OR REPLACE VIEW `kis-gemini-common-prod.ge_logs.v_feature_usage` AS
WITH e AS (
  SELECT
    DATE(timestamp, "Asia/Seoul") AS d,
    REGEXP_EXTRACT(logName, r'projects/([^/]+)/logs') AS project_id,
    JSON_VALUE(protoPayload,'$.authenticationInfo.principalEmail') AS u,
    REGEXP_EXTRACT(JSON_VALUE(protoPayload,'$.methodName'), r'[^.]+$') AS m
  FROM `kis-gemini-common-prod.ge_logs.data_access`
  WHERE JSON_VALUE(protoPayload,'$.serviceName') = 'discoveryengine.googleapis.com'
)
SELECT
  d AS event_date_kst, project_id,
  COUNTIF(m IN ('CreateNotebook','GetNotebook','UpdateNotebook','GenerateNotebookGuide','GenerateDocumentGuides',
                'GetAudioOverview','GenerateFreeFormStreamed','UploadSourceFile','GetNotebookAnalytics','CreateNote','BatchGetNotes')) AS notebooklm_events,
  COUNT(DISTINCT IF(m LIKE '%Notebook%', u, NULL))                          AS notebooklm_users,
  COUNTIF(m IN ('GetIdea','GeneratePersonalContext'))                       AS idea_events,
  COUNTIF(m = 'Search')                                                     AS searches
FROM e
GROUP BY 1, 2;

------------------------------------------------------------------
-- 4) (★) observability — Agent×일 질문수
--    obs_activity.jsonPayload 실제 스키마 확정 후 경로 교체:
--      $.userEmail / $.agentId / $.eventType (예시 — 검증 필요)
------------------------------------------------------------------
-- CREATE OR REPLACE VIEW `kis-gemini-common-prod.ge_logs.v_daily_agent_questions` AS
-- SELECT
--   DATE(timestamp, "Asia/Seoul")                     AS event_date_kst,
--   REGEXP_EXTRACT(logName, r'projects/([^/]+)/logs')  AS project_id,
--   JSON_VALUE(jsonPayload, '$.agentId')               AS agent_id,    -- ★ 확정 필요
--   JSON_VALUE(jsonPayload, '$.userEmail')             AS user_email,  -- ★ 확정 필요
--   COUNT(*)                                           AS questions
-- FROM `kis-gemini-common-prod.ge_logs.obs_activity`
-- WHERE JSON_VALUE(jsonPayload, '$.eventType') = 'QUERY'              -- ★ 확정 필요
-- GROUP BY 1, 2, 3, 4;
