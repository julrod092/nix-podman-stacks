{
  config,
  lib,
  ...
}: let
  name = "job-ops";
  containerName = "job-ops";

  cfg = config.nps.stacks.${name};
  storage = "${config.nps.storageBaseDir}/${containerName}";

  category = "General";
  description = "Job Search Assistant";
  displayName = "JobOps";
in {
  imports = import ../mkAliases.nix config lib name [containerName];

  options.nps.stacks.${name} = {
    enable = lib.mkEnableOption name;
    rxResumeUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Reactive Resume URL for JobOps to use. When the Reactive Resume stack is enabled,
        this defaults to its local container URL. If unset, JobOps can still be configured
        through its onboarding flow.
      '';
    };
    rxResumeApiKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = ''
        Path to the file containing a Reactive Resume v5 API key for JobOps.
        If unset, JobOps can still be configured through its onboarding flow.
      '';
    };
    extraEnv = lib.mkOption {
      type = (import ../types.nix lib).extraEnv;
      default = {};
      description = ''
        Extra environment variables to set for the container.
        Variables can be either set directly or sourced from a file (e.g. for secrets).

        See <https://github.com/DaKheera47/job-ops/blob/main/.env.example>
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf config.nps.stacks.reactive-resume.enable {
      nps.stacks.${name}.rxResumeUrl = lib.mkDefault "http://reactive-resume:3000";
    })
    {
      services.podman.containers.${containerName} = {
        image = "ghcr.io/dakheera47/job-ops:v0.6.2";
        volumeMap = {
          data = "${storage}/data:/app/data";
          codexHome = "${storage}/codex-home:/app/codex-home";
        };

        extraEnv =
          {
            NODE_ENV = "production";
            PORT = 3001;
            PYTHON_PATH = "/usr/bin/python3";
            CODEX_HOME = "/app/codex-home";
            JOBOPS_PUBLIC_BASE_URL = cfg.containers.${containerName}.traefik.serviceUrl;
          }
          // lib.optionalAttrs (cfg.rxResumeUrl != null) {
            RXRESUME_URL = cfg.rxResumeUrl;
          }
          // lib.optionalAttrs (cfg.rxResumeApiKeyFile != null) {
            RXRESUME_API_KEY.fromFile = cfg.rxResumeApiKeyFile;
          }
          // cfg.extraEnv;

        wantsContainer = lib.optional config.nps.stacks.reactive-resume.enable "reactive-resume";

        stack = name;
        port = 3001;
        traefik.name = containerName;
        homepage = {
          inherit category;
          name = displayName;
          settings = {
            inherit description;
            icon = "sh-job-ops";
          };
        };
        glance = {
          inherit category description;
          name = displayName;
          id = containerName;
          icon = "sh:job-ops";
        };
      };
    }
  ]);
}
