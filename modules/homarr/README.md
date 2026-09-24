Personalized, multi-user application dashboard

- [Github](https://github.com/homarr-labs/homarr)
- [Website](https://homarr.dev/)

## Example

```nix
{config, ...}: {
  nps.stacks.homarr = {
    enable = true;
    secretEncryptionKeyFile = config.sops.secrets."homarr/encryption_key".path;
    authSecretFile = config.sops.secrets."homarr/auth_secret".path;
    oidc = {
      enable = true;
      clientSecretFile = config.sops.secrets."homarr/oidc_client_secret".path;
    };
  };
}
```

Complete the external-provider onboarding after the first deployment. Create the configured OIDC admin group in Homarr to synchronize administrator privileges from Authelia.

## Stack Options

<RenderDocs :options="data" :include="/nps\.stacks\.homarr\.(?!containers($|\.)).*/" />

## Container Aliases

<RenderDocs :options="data" :include="/nps\.stacks\.homarr\.containers\..*/" />
