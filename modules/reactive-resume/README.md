## Example

```nix
{config, ...}: {
  nps.stacks.reactive-resume = {
    enable = true;
    authSecretFile = config.sops.secrets."reactive_resume/auth_secret".path;
    db.passwordFile = config.sops.secrets."reactive_resume/db_password".path;
    oidc = {
      enable = true;
      clientSecretFile = config.sops.secrets."reactive_resume/authelia/client_secret".path;
    };
    jobOps = {
      enable = true;
      rxResumeApiKeyFile = config.sops.secrets."reactive_resume/job_ops/rxresume_api_key".path;
      extraEnv = {
        GMAIL_OAUTH_CLIENT_ID.fromFile = config.sops.secrets."reactive_resume/job_ops/gmail_client_id".path;
        GMAIL_OAUTH_CLIENT_SECRET.fromFile = config.sops.secrets."reactive_resume/job_ops/gmail_client_secret".path;
      };
    };
  };
}
```

JobOps is disabled by default. When enabled, it is deployed in the same stack and preconfigured to use the local Reactive Resume container via `RXRESUME_URL`.
