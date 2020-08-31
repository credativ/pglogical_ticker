/***
    There may be a race condition in WaitForBackgroundWorkerStartup that 
    leads to indeterminate behavior on a bad launch.

    For this reason, we set log_min_messages to ERROR.  These tests then
    really only ensure that the server lives OK during a bad launch.
***/
SET client_min_messages TO ERROR;

--The _launch function is not supposed to be used directly
--This tests that stupid things don't do something really bad
DROP TABLE IF EXISTS bad_pid;
CREATE TEMP TABLE bad_pid AS
SELECT pglogical_ticker._launch(9999999::OID) AS pid;

--Verify that it exits cleanly if the SQL within the worker errors out
--In this case, renaming the function will do it
ALTER FUNCTION pglogical_ticker.tick() RENAME TO tick_oops;
DROP TABLE IF EXISTS bad_pid_2;
CREATE TEMP TABLE bad_pid_2 AS
SELECT pglogical_ticker.launch() AS pid;

-- Give it time to die asynchronously
SELECT pg_sleep(2);

-- Fix it
ALTER FUNCTION pglogical_ticker.tick_oops() RENAME TO tick;

--Verify we can't start multiple workers - the second attempt should return NULL
--We know this is imperfect but so long as pglogical_ticker.launch is not executed
--at the same exact moment this is good enough insurance for now.
--Also, multiple workers still could be running without any bad side effects.

--Should be false because the process should start OK
SELECT pglogical_ticker.launch() IS NULL AS pid;
SELECT pg_sleep(1);

--Should be true because we already have one running
SELECT pglogical_ticker.launch() IS NULL AS next_attempt_no_pid;

-- We do this because of race condition above.  We may be killing more than one pid
WITH canceled AS (
SELECT pg_cancel_backend(pid)
FROM pg_stat_activity
WHERE NOT pid = pg_backend_pid()
 AND query LIKE '%pglogical_ticker%')

SELECT (SELECT COUNT(1) FROM canceled) > 0 AS at_least_one_canceled;

SELECT pg_sleep(1);
SELECT COUNT(1) AS ticker_still_running
FROM pg_stat_activity
WHERE NOT pid = pg_backend_pid()
 AND query LIKE '%pglogical_ticker%';
