# ProxmoxRox

## What is this?
A repo of info and scripts to help you quickly build Ubuntu and Windows VMs on Proxmox.

## Break it down for me
The repo has a few primary folders and files:

### Ubuntu folder
* `2build.sh` - this script creates a basic Ubuntu cloud server template, which will be used to deploy fresh VMs when you run...

* `2deploy.sh` - this script will run you through some prompts to deploy a Ubuntu VM off the template you created with `2build.sh`.  The script will ask you for disk size and RAM requirements, what VLAN you want to stick the VM on, storage name to use, and MAC address (if you want to specify one).  

* `user-data.yaml` - **IMPORTANT!** - you will want to stick this file in the `/var/lib/vz/snippets/` folder on your Proxmox server.  This file is the "guts" of the VM build - you choose what packages are installed, the user config, etc.

### Windows folder

