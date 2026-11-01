\set ON_ERROR_STOP on

begin;

select cron.unschedule(job.jobid)
from cron.job as job
where job.jobname = 'petcare-communications-dispatch-v1';

commit;
