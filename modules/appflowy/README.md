Collaborative workspace for notes, wikis, projects, and databases.

- [Github](https://github.com/AppFlowy-IO/AppFlowy-Cloud)
- [Website](https://appflowy.com/)
- [Self-hosting docs](https://docs.appflowy.io/docs/guides/appflowy)

## Example

```nix
{config, ...}: {
  nps.stacks.appflowy = {
    enable = true;

    db.passwordFile = config.sops.secrets."appflowy/db_password".path;
    gotrue = {
      adminEmail = "admin@example.com";
      adminPasswordFile = config.sops.secrets."appflowy/admin_password".path;
      jwtSecretFile = config.sops.secrets."appflowy/jwt_secret".path;
    };
    minio.rootPasswordFile = config.sops.secrets."appflowy/minio_password".path;

    oidc = {
      enable = true;
      clientSecretFile = config.sops.secrets."appflowy/authelia/client_secret".path;
      clientSecretHash = "$pbkdf2-sha512$...";
    };
  };
}
```

## Authentication

AppFlowy requires GoTrue as its internal auth broker for user sessions and JWT validation. When `oidc.enable = true`, Authelia is configured as the user-facing identity provider through GoTrue's custom OIDC provider support.

In OIDC mode, GoTrue email and phone login providers are disabled by default. Users authenticate with Authelia, while AppFlowy continues to receive the GoTrue sessions it expects.
