{pkgs, ...}: let
  datadir = "/mnt/mirrored/filebrowser";
  vardir = "/var/lib/filebrowser";
in {
  environment.etc."filebrowser/config.json".text = ''
    {
      "port": 8080,
      "baseURL": "/filebrowser",
      "address": "127.0.0.1",
      "log": "stdout",
      "database": "${vardir}/filebrowser.db",
      "root": "${datadir}"
    }
  '';

  systemd.tmpfiles.rules = [
    "d ${vardir} 0755 filebrowser users -"
    "d ${datadir} 0755 filebrowser users -"
  ];

  users.users.filebrowser = {
    isSystemUser = true;
    group = "users";
    home = vardir;
    createHome = true;
  };

  systemd.services = {
    filebrowser = {
      description = "File Browser";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        ExecStart = "${pkgs.filebrowser}/bin/filebrowser -c /etc/filebrowser/config.json";
        Restart = "always";
        User = "filebrowser";
        Group = "users";
        WorkingDirectory = vardir;
        StateDirectory = "filebrowser";
      };
    };
  };
}
