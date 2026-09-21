## JobOps

JobOps is a job search assistant.

- GitHub: <https://github.com/DaKheera47/job-ops>

## Example

```nix
{config, ...}: {
  nps.stacks.job-ops = {
    enable = true;
    rxResumeApiKeyFile = config.sops.secrets."job-ops/rxresume_api_key".path;
    extraEnv = {
      GMAIL_OAUTH_CLIENT_ID.fromFile = config.sops.secrets."job-ops/gmail_client_id".path;
      GMAIL_OAUTH_CLIENT_SECRET.fromFile = config.sops.secrets."job-ops/gmail_client_secret".path;
    };
  };
}
```

When `nps.stacks.reactive-resume.enable` is true, JobOps defaults `RXRESUME_URL` to the local Reactive Resume container URL. Set `rxResumeUrl` to override it or leave Reactive Resume disabled to complete configuration through the JobOps onboarding flow.
