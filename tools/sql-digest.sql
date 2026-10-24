-- performance_schema から SQL ごとの合計時間 TOP20（slow log より軽い）
-- make bench-prep でリセットされる
SELECT
  ROUND(SUM_TIMER_WAIT / POW(1000, 4), 3) AS sum_s,
  COUNT_STAR AS count,
  ROUND(AVG_TIMER_WAIT / POW(1000, 4) * 1000, 2) AS avg_ms,
  SUM_ROWS_EXAMINED AS rows_examined,
  SUM_ROWS_SENT AS rows_sent,
  SUM_NO_INDEX_USED AS no_index,
  LEFT(DIGEST_TEXT, 200) AS query
FROM performance_schema.events_statements_summary_by_digest
WHERE SCHEMA_NAME IS NOT NULL AND SCHEMA_NAME NOT IN ('performance_schema', 'mysql', 'sys')
ORDER BY SUM_TIMER_WAIT DESC
LIMIT 20;
