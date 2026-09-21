# Set up the box

This is the only part that needs you at the keyboard. About 15 minutes. When the last check passes, unplug the monitor; the rest happens over the network.

## 1. BIOS

Nothing to change. The build works with the default **UMA Frame Buffer Size**; the model uses about 28 GB of GPU memory, and any carve-out of 32 GB or more is enough. If you set it to 96 GB for the previous version of this repo, leave it.

<details>
<summary>Advanced: running models larger than the carve-out</summary>

Linux can give the GPU memory beyond the BIOS carve-out through the kernel's GTT pool. AMD's guidance for Strix Halo is a small carve-out (512 MB to 2 GB) plus the kernel parameters `ttm.pages_limit=31457280 ttm.page_pool_size=31457280` (120 GiB). Lower the carve-out first; the kernel does not cap GTT against it, and 96 GB carved out plus 120 GiB of GTT over-commits the machine. This build does not need it and it has not been tested on the reference box.
</details>

## 2. Install Ubuntu Server

1. Download Ubuntu Server 26.04 LTS and write it to a USB stick with balenaEtcher.
2. Boot the box from the stick.
3. Accept the defaults, choose **use the entire disk**, and tick **Install OpenSSH server**. Skip the extra software it offers.
4. Pick a username. Reboot and pull the stick.

The installer only uses part of the disk. That gets fixed later, automatically.

## 3. Plug in a network cable if you can

Wi-Fi works, but a cable is the difference between a server you never think about and one you occasionally walk over to. With Wi-Fi as the only link, a driver hiccup or a regulatory-domain change takes the box off the network and there is no other way in. The build guide turns off Wi-Fi power saving, which otherwise adds 50 to 120 ms to every request.

Then log in and run:

```console
$ ip a | grep "inet 192"
```

Write down the address. In your router, pin it to this machine so it never changes.

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

## 6. Install Kilo Code

In VS Code, install the **Kilo Code** extension. On macOS, the first time it tries to reach the box it will be blocked until you allow it under **System Settings → Privacy & Security → Local Network** (enable Visual Studio Code, then restart VS Code). The build guide writes its config.

## 7. Get the repo

```console
$ git clone https://github.com/ryandau/strix-halo-llm-server.git
$ cd strix-halo-llm-server
```

Open that folder in your AI coding agent and paste the one-line prompt from the README.
