# ProxmoxRox

## What is this?
A repo of info and scripts to help you quickly build Ubuntu and Windows VMs on Proxmox.  Here's the breakdown:

## Ubuntu folder
* `2build.sh` - this script creates a basic Ubuntu cloud server template, which will be used to deploy fresh VMs when you run...

* `2deploy.sh` - this script will run you through some prompts to deploy a Ubuntu VM off the template you created with `2build.sh`.  The script will ask you for disk size and RAM requirements, what VLAN you want to stick the VM on, storage name to use, and MAC address (if you want to specify one).  

* `user-data.yaml` - **IMPORTANT!** - you will want to stick this file in the `/var/lib/vz/snippets/` folder on your Proxmox server.  This file is the "guts" of the VM build - you choose what packages are installed, the user config, etc.

## Windows folder
* `auto11.xml` - an auto-answer file for a Windows 11 build

* `inventory.xml` - this is where you give "nicknames" to your Proxmox servers and provide credentials for ansible to use

* `iso-files (folder)` - here's where you stick all the scripts/files/etc. that you want to be mounted and available during the Windows client install.

* `iso-files-server (folder)` - here's where you stick all the scripts/files/etc. that you want to be mounted and available during the Windows server install.

* `provision.yml` - this Ansible playbook file automates the creation and provisioning of virtual machines in Proxmox. It handles the entire process from creating a custom Windows installation ISO with automated setup files, to creating the VM with specified hardware configurations, and finally booting and waiting for the VM to be ready. The playbook is highly configurable through variables, supporting different Windows templates (like Windows 11 or Windows Server), and includes features like automatic VMID assignment, network configuration, and cleanup of temporary files after deployment. *(yes, ChatGPT wrote this summary.  Sue me.)*

* `vars.xml` - this file defines configuration templates for creating virtual machines in Proxmox VE, including specific settings for Windows 11, Windows Server 2019, and Ubuntu VMs, with parameters for CPU, memory, storage, and OS-specific configurations. *(yep, ChatGPT wrote this summary too because I'm lazy and didn't wanna.  Sue me twice.)*