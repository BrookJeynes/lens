lens
-----

A simple unix system fetch tool.

```
user@fedora
--------------
distro   Fedora Linux 40 (Workstation Edition) x86_64
uptime   6d 13h 57m
kernel   6.10.12-200.fc40.x86_64
desktop  river
shell    zsh
memory   17170 / 63572 MB (27%)
battery  96% (Charging)
cpu      AMD Ryzen 7 7840U w/ Radeon  780M Graphics
disk     30G / 1.9T (2%)
```

Configure `lens` by editing the external configuration file located at either:
- `$HOME/.lens/config.ziggy`
- `$XDG_CONFIG_HOME/lens/config.ziggy`.

lens will look for these env variables specifically. If they are not set, lens 
will not be able to find the config file.

An example config file can be found [here](./example-config.ziggy).
The config schema can be found [here](./config.ziggy-schema).

Contributions, issues, and feature requests are always welcome! This project 
is built using Zig `v0.14.0-dev.2628+5b5c60f43`.
