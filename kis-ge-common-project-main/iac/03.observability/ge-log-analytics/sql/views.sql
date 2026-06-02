-- GE 사용량 분석 뷰 (external table 위). 데이터 적재 후 실행 (CREATE OR REPLACE).
--   bq query --use_legacy_sql=false < views.sql   (또는 콘솔)
-- 대상: `kis-gemini-common-prod.ge_logs.{obs_activity_ext, data_access_ext, activity_ext}`
--
-- 주의:
--  * GCS export JSON은 원본 LogEntry 구조를 유지 → 필드는 `protoPayload`(audit) / `jsonPayload`(observability).
--    (BigQuery 직접 sink의 `protopayload_auditlog` 와 다름)
--  * 자동완성(AdvancedCompleteQuery)은 "질문"이 아님 → 제외. 질문 = StreamAssist.
--  * KST 일자 = DATE(TIMESTAMP(timestamp), "Asia/Seoul").
--  * (★) 표시 필드는 observability 로그 실제 샘플(STG)로 경로 확정 필요.

------------------------------------------------------------------
-- 1) data_access 기반 (스키마 확정: protoPayload.*) — 계정×일 질문수
------------------------------------------------------------------
CREATE OR REPLACE VIEW `kis-gemini-common-prod.ge_logs.v_daily_user_questions` AS
SELECT
  DATE(TIMESTAMP(timestamp), "Asia/Seoul")                              AS event_date_kst,
  REGEXP_EXTRACT(logName, r'projects/([^/]+)/logs')                     AS project_id,
  protoPayload.authenticationInfo.principalEmail                        AS user_email,
  COUNTIF(REGEXP_EXTRACT(protoPayload.methodName, r'[^.]+$') IN ('StreamAssist','AsyncAssist','ReadAsyncAssist')) AS questions,
  COUNTIF(REGEXP_EXTRACT(protoPayload.methodName, r'[^.]+$') = 'Search')                 AS searches,
  COUNTIF(REGEXP_EXTRACT(protoPayload.methodName, r'[^.]+$') = 'AdvancedCompleteQuery')  AS autocompletes,
  COUNT(*)                                                              AS total_events
FROM `kis-gemini-common-prod.ge_logs.data_access_ext`
WHERE protoPayload.serviceName = 'discoveryengine.googleapis.com'
  AND protoPayload.authenticationInfo.principalEmail IS NOT NULL
  AND protoPayload.authenticationInfo.principalEmail NOT LIKE '%gserviceaccount.com'
GROUP BY 1, 2, 3;

------------------------------------------------------------------
-- 2) data_access 기반 — 자회사×일 DAU / 질문자수
------------------------------------------------------------------
CREATE OR REPLACE VIEW `kis-gemini-common-prod.ge_logs.v_daily_active_users` AS
SELECT
  DATE(TIMESTAMP(timestamp), "Asia/Seoul")                  AS event_date_kst,
  REGEXP_EXTRACT(logName, r'projects/([^/]+)/logs')         AS project_id,
  COUNT(DISTINCT protoPayload.authenticationInfo.principalEmail) AS active_users,
  COUNT(DISTINCT IF(REGEXP_EXTRACT(protoPayload.methodName, r'[^.]+$') IN ('StreamAssist','AsyncAssist'),
                    protoPayload.authenticationInfo.principalEmail, NULL)) AS asking_users
FROM `kis-gemini-common-prod.ge_logs.data_access_ext`
WHERE protoPayload.serviceName = 'discoveryengine.googleapis.com'
  AND protoPayload.authenticationInfo.principalEmail NOT LIKE '%gserviceaccount.com'
GROUP BY 1, 2;

------------------------------------------------------------------
-- 3) data_access 기반 — 기능별(NotebookLM / Idea / Search) 일별
------------------------------------------------------------------
CREATE OR REPLACE VIEW `kis-gemini-common-prod.ge_logs.v_feature_usage` AS
WITH e AS (
  SELECT
    DATE(TIMESTAMP(timestamp), "Asia/Seoul") AS d,
    REGEXP_EXTRACT(logName, r'projects/([^/]+)/logs') AS project_id,
    protoPayload.authenticationInfo.principalEmail AS u,
    REGEXP_EXTRACT(protoPayload.methodName, r'[^.]+$') AS m
  FROM `kis-gemini-common-prod.ge_logs.data_access_ext`
  WHERE protoPayload.serviceName = 'discoveryengine.googleapis.com'
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
-- 4) (★) observability 기반 — Agent×일 질문수
--    observability 로그(jsonPayload) 실제 스키마를 STG 샘플로 확정 후 필드 경로 교체.
--    아래는 추정 경로 — 반드시 검증 필요:
--      jsonPayload.userEmail (또는 .user / .principalEmail)
--      jsonPayload.agentId   (또는 .agent / .agentDisplayName)
--      jsonPayload.eventType (질문 식별)
------------------------------------------------------------------
-- CREATE OR REPLACE VIEW `kis-gemini-common-prod.ge_logs.v_daily_agent_questions` AS
-- SELECT
--   DATE(TIMESTAMP(timestamp), "Asia/Seoul")          AS event_date_kst,
--   REGEXP_EXTRACT(logName, r'projects/([^/]+)/logs')  AS project_id,
--   jsonPayload.agentId                                AS agent_id,       -- ★ 확정 필요
--   jsonPayload.userEmail                              AS user_email,     -- ★ 확정 필요
--   COUNT(*)                                           AS questions
-- FROM `kis-gemini-common-prod.ge_logs.obs_activity_ext`
-- WHERE jsonPayload.eventType = 'QUERY'                                   -- ★ 확정 필요
-- GROUP BY 1, 2, 3, 4;
