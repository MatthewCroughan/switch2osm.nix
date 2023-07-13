{
  imports = [ ./switch2osm.nix ];
  virtualisation.memorySize = 8192;
  virtualisation.cores = 4;
  virtualisation.diskSize = 10 * 1024;
  nixos-shell.mounts = {
    mountHome = false;
    extraMounts = {
      "/map-data" = ./map-data;
    };
  };
}
