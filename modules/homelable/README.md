Self-hosted homelab infrastructure visualizer — interactive network diagram with live status monitoring.

- [Github](https://github.com/Pouzor/homelable)
- [Website](https://homelable.net)

## Example

```nix
{config, ...}: {
  nps.stacks.homelable = {
    enable = true;
    secretKeyFile = config.sops.secrets."homelable/secret_key".path;
    oidc = {
      enable = true;
      clientSecretFile = config.sops.secrets."homelable/authelia/client_secret".path;
      clientSecretHash = "$pbkdf2-sha512$...";
    };
  };
}
```
