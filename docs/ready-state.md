# Set up the box

This is the only part you do at the keyboard. About 15 minutes. When you're done, you can unplug the monitor. Everything else happens over the network from your own computer.

## 1. BIOS

Nothing to change. Leave the defaults.

## 2. Install Ubuntu Server

1. Download [Ubuntu Server 26.04 LTS](https://ubuntu.com/download/server) and write it to a USB stick with [balenaEtcher](https://etcher.balena.io).
2. Plug the stick into the box and boot from it.
3. Accept the defaults, choose **Use an entire disk**, and tick **Install OpenSSH server**. Skip the extra software it offers at the end.
4. Choose a username and password. When it finishes, reboot and remove the stick.

The installer only uses part of the disk. The agent fixes that later.

## 3. Find the box's address

Log in at the box and run:

```console
$ ip a | grep "inet 192"
```

Write down the address that starts with `192.168`. Then, in your router's settings, reserve that address for this machine so it doesn't change. (Routers call this a static lease, an address reservation or DHCP reservation.)

## 4. Let the agent run admin commands

The agent can't type a password when the box asks for one, and most of the setup needs admin rights. This stops the box asking your user for a password:

```console
$ echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/90-$USER
$ sudo chmod 440 /etc/sudoers.d/90-$USER
$ sudo -n true && echo OK
```

It should print `OK`.

**Is this safe?** It means anyone who can log in as your user can also run admin commands without a password. On a box that does one job on your own network and only accepts your SSH key, that's a reasonable trade. To undo it after the build: `sudo rm /etc/sudoers.d/90-$USER`, and the agent will ask you to run admin steps yourself.

## 5. Give your computer a key to the box

On your own computer, not the box. Replace `<user>` with the username you chose and `<box-ip>` with the address from step 3:

```console
$ ls ~/.ssh/id_ed25519.pub || ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
$ ssh-copy-id <user>@<box-ip>
$ ssh -o BatchMode=yes <user>@<box-ip> 'sudo -n true && echo READY'
```

You'll type the box's password once. `READY` means it worked. Anything else, repeat this step.

## 6. Install Kilo Code

In VS Code, install the [Kilo Code](https://kilocode.ai) extension. On a Mac, the first time it tries to reach the box, macOS will block it: go to **System Settings → Privacy & Security → Local Network**, turn on Visual Studio Code, and restart VS Code. The agent writes the settings for you.

## 7. Get this repo

```console
$ git clone https://github.com/ryandau/strix-halo-llm-server.git
$ cd strix-halo-llm-server
```

Open that folder in your AI coding agent and paste the one-line instruction from the README.
