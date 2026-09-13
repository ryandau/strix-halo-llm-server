# Set up the box

This is the only part that needs you at the keyboard. About 15 minutes. When the last check passes, unplug the monitor; the rest happens over the network.

## 1. BIOS (optional)

Power on and press `Del` or `F7`. If you can find **UMA Frame Buffer Size**, set it to 96 GB. The build works either way.

## 2. Install Ubuntu Server

1. Download Ubuntu Server 26.04 LTS and write it to a USB stick with balenaEtcher.
2. Boot the box from the stick.
3. Accept the defaults, choose **use the entire disk**, and tick **Install OpenSSH server**. Skip the extra software it offers.
4. Pick a username. Reboot and pull the stick.

The installer only uses part of the disk. That gets fixed later, automatically.

## 3. Find the box's address

Log in and run:

```console
$ ip a | grep "inet 192"
```

Write down the address. In your router, pin it to this machine so it never changes.

A network cable is faster than Wi-Fi for the 94 GB download, but Wi-Fi works.

## 4. Let the agent run admin commands

The agent can't type a password when asked for one, and most of the build needs admin rights. This removes the password prompt for your user:

```console
$ echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/90-$USER
$ sudo chmod 440 /etc/sudoers.d/90-$USER
$ sudo -n true && echo OK
```

This is a trade-off. The box is a single-purpose machine on your home network, and anyone holding your SSH key already controls it. If you'd rather not, delete that file after the build and run the admin steps yourself when the agent asks.

## 5. Give your computer a key to the box

On your own computer, not the box:

```console
$ ls ~/.ssh/id_ed25519.pub || ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
$ ssh-copy-id <user>@<box-ip>
$ ssh -o BatchMode=yes <user>@<box-ip> 'sudo -n true && echo READY'
```

You'll type the box password once. `READY` means you're done. Anything else, repeat this step.

## 6. Get the repo

```console
$ git clone https://github.com/ryandau/strix-halo-llm-server.git
$ cd strix-halo-llm-server
```

Open that folder in your AI coding agent and paste the one-line prompt from the README.
