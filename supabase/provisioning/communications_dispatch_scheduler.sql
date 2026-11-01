\set ON_ERROR_STOP on

begin;

create extension if not exists pg_cron;
create extension if not exists pg_net;

do $validation$
declare
    dispatch_url text;
    maintenance_secret text;
begin
    select secret.decrypted_secret
    into strict dispatch_url
    from vault.decrypted_secrets as secret
    where secret.name = 'communications_dispatch_url';

    select secret.decrypted_secret
    into strict maintenance_secret
    from vault.decrypted_secrets as secret
    where secret.name = 'communications_maintenance_secret';

    if dispatch_url !~ '^https://[^/]+/functions/v1/communications-dispatch$'
       or maintenance_secret = '' then
        raise exception 'Communications scheduler Vault configuration is invalid';
    end if;
end;
$validation$;

select cron.unschedule(job.jobid)
from cron.job as job
where job.jobname = 'petcare-communications-dispatch-v1';

select cron.schedule(
    'petcare-communications-dispatch-v1',
    '*/5 * * * *',
    $dispatch$
    select net.http_post(
        url := (
            select secret.decrypted_secret
            from vault.decrypted_secrets as secret
            where secret.name = 'communications_dispatch_url'
        ),
        headers := jsonb_build_object(
            'content-type', 'application/json',
            'x-maintenance-secret', (
                select secret.decrypted_secret
                from vault.decrypted_secrets as secret
                where secret.name = 'communications_maintenance_secret'
            )
        ),
        body := '{}'::jsonb,
        timeout_milliseconds := 15000
    );
    $dispatch$
);

commit;
