{
  lib,
  config,
  ...
}: let
  monitoringEnabled = config.nps.stacks.monitoring.enable;
  defaultAlloyCollection = config.nps.stacks.monitoring.alloy.collectByDefault;
in {
  # If a container has the logging label, add alloy
  options.services.podman.containers = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule ({config, ...}: {
      options.alloy.enable = lib.mkOption {
        type = lib.types.bool;
        description = "Alloy Log Scraping. If enabled, Alloy will scrape logs from the container and ship them to Loki.;";
        default = defaultAlloyCollection;
        defaultText = lib.literalExpression ''config.nps.stacks.monitoring.alloy.collectByDefault'';
      };
      config = lib.mkIf (monitoringEnabled && config.alloy.enable) {
        labels."logging.alloy" = "true";
      };
    }));
  };
}
