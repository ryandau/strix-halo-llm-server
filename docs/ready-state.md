# Ready state: the 15 minutes at the keyboard

Everything in this file needs a monitor and keyboard on the box, or your own terminal on the workstation. Nothing else in the repo does. When the final check passes, unplug the monitor and hand the box to your agent.

## 1. BIOS (optional, 2 minutes)

Power on, press `Del` or `F7`. Under the memory or graphics settings, set **UMA Frame Buffer Size** to 96 GB if the option exists. The build works either way with Vulkan; 96 GB is what the reference numbers were measured with.

## 2. Install Ubuntu Server 26.04 LTS (10 minutes)

1. Download the ISO and flash it to a USB stick with balenaEtcher.
2. Boot from the stick.
3. In the installer accept the defaults, choose **use the entire disk**, and tick **Install OpenSSH server**. Skip the featured snaps. Pick a username you're happy typing; the guide calls it `<user>`.
4. Reboot, remove the stick.

Do not worry about the disk layout. The installer only allocates about 100 GB and the first build phase fixes that.

## 3. Get the IP (1 minute)

Log in at the console and run:

```console
$ ip a | grep "inet 192"
```

Note the address. Reserve it against the machine's MAC address in your router so it never changes. A wired connection is better than Wi-Fi for the 94 GB download, but Wi-Fi 6 works; today's reference build ran on Wi-Fi at about 11 MB/s.

## 4. Passwordless sudo (1 minute)

An agent cannot answer a password prompt, and every privileged step of the build needs sudo. Still at the console:

```console
$ echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/90-$USER
$ sudo chmod 440 /etc/sudoers.d/90-$USER
$ sudo -n true && echo OK
```

This is a deliberate trade-off. The box is a single-purpose appliance on your LAN; anyone with your SSH key already controls it. If that doesn't suit you, delete the file after the build and be prepared to run the sudo steps yourself when the agent asks.

## 5. SSH key from the workstation (1 minute)

On your workstation, not the box:

```console
$ ls ~/.ssh/id_ed25519.pub || ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
$ ssh-copy-id <user>@<box-ip>          # type the box password one last time
$ ssh -o BatchMode=yes <user>@<box-ip> 'sudo -n true && echo READY'
```

`READY` means the box passes. If you see a password prompt or `Permission denied`, repeat this step.

## 6. Clone this repo on the workstation

```console
$ git clone https://github.com/ryandau/strix-halo-llm-server.git
$ cd strix-halo-llm-server
$ claude
```

Then paste the handoff prompt from the README. You're done at the keyboard.
