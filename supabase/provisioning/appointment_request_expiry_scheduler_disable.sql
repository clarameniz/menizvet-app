\set ON_ERROR_STOP on

-- Stops the SPEC-APT-015 expiry job. Already materialized EXPIRED outcomes
-- are unaffected, and logical expiry keeps applying directly in every
-- operation; only materialization pauses.

begin;

select cron.unschedule(job.jobid)
from cron.job as job
where job.jobname = 'petcare-appointment-request-expiry-v1';

commit;
