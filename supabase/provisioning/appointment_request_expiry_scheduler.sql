\set ON_ERROR_STOP on

-- SPEC-APT-015: schedules the authoritative SYSTEM materialization of
-- logically expired Appointment requests (REQUESTED -> EXPIRED) every five
-- minutes, the repository's existing operational cadence. The job runs
-- plain SQL in the database; it needs no Edge Function, network call, or
-- secret. Correctness never depends on its cadence: confirmation,
-- cancellation, rescheduling, pending-request evaluation, and pre-care
-- access already apply logical expiry directly.
--
-- Provision only after client applications in this environment can parse
-- and present EXPIRED (SPEC-APT-015 §7). Safe to rerun. To stop it, run
-- appointment_request_expiry_scheduler_disable.sql.

begin;

create extension if not exists pg_cron;

select cron.unschedule(job.jobid)
from cron.job as job
where job.jobname = 'petcare-appointment-request-expiry-v1';

select cron.schedule(
    'petcare-appointment-request-expiry-v1',
    '*/5 * * * *',
    $expiry$select public.expire_lapsed_appointment_requests();$expiry$
);

commit;
