# OverWatch: A Solaris Command Logger

![Solaris 10](https://img.shields.io/badge/OS-Solaris_10-orange.svg)

OverWatch is a small forensics and monitoring tool designed to log command-line activity for targeted users on the Solaris 10 operating system. It operates by intercepting system calls and is intended for security analysis and incident response.

Usually dtrace is a better option. However, you may find yourself in a situation where you need to log commands within a Local Zone and you don't have access to the Global Zone, or maybe you don't have permissions to install a dtrace probe.

## How It Works

The core of OverWatch is a shared library (`mailq.so`) that leverages the `LD_PRELOAD` environment variable.

1.  **Preloading:** When a shell like `bash` or `sh` is started for a target user, the `LD_PRELOAD` variable instructs the dynamic linker to load `mailq.so` before any standard system libraries.
2.  **Interception:** This library contains a custom implementation of the `execve()` function. Because our library is loaded first, any call to `execve()` from the shell is redirected to our custom function instead of the original one in libc.
3.  **Logging:** Our custom `execve()` function records the command and its arguments to a log file.
4.  **Execution:** After logging, it calls the original `execve()` function to allow the command to execute normally, ensuring transparency to the user.

## Core Logic & Features

The `mailq.so` library is designed to be lightweight and cautious. When loaded into a process it performs several checks and actions:

*   **Targeted Shells:** Logging is only activated if the parent process is `/bin/sh` or `/bin/bash` (or ends in `/sh` or `/bash`).
*   **32-bit Only:** It verifies that the host process is a 32-bit binary, which is the default for standard shells on Solaris 10 SPARC.
*   **Interactive Sessions Only:** To avoid logging system scripts and daemons, it checks that the user's TTY is a pseudo-terminal (`/dev/pts/*`).
*   **Log Format:** Logs are written in a clear, parsable format:
    ```
    [ timestamp - username - pid parent_pid ] command_path arguments
    ```
*   **Child Process Safety:** Crucially, it unsets the `LD_PRELOAD` variable before executing the logged command. This prevents child processes from inheriting the variable, which avoids infinite loops and potential conflicts with other tools.
*   **Filesystem Check:** It ensures there is more than 500MB of free disk space before activating. This prevents the tool from causing a denial-of-service by filling up the disk.

### Configuration

The following paths are hardcoded in the source code but can be configured before compilation:
*   **Library Path:** `/var/tmp/tblSffasX2/mailq.so`
*   **Log File Path:** `/var/tmp/.xixXS244s/.mail`
*   **Disk Space Threshold:** `500` MB

---

## Building

Make sure you have a compiler and maketools installed. 

```bash
make
```

## Deployment Guide

Deploying OverWatch involves three main steps: preparing the environment, deploying the library, and configuring a target user's shell.

### ⚠️ Prerequisite: "Break-Glass" Account

**Before you begin, ensure you have a separate `root` access account that is NOT targeted by this tool.** This account is your safety net for disabling the logger or fixing any issues that may arise.

### Step 1: Prepare the Environment (as root or target user)

Create the hidden directories for the shared library and the log file. These obfuscated paths help reduce the chance of accidental discovery.

```bash
# Create directory for the shared library
mkdir /var/tmp/tblSffasX2
chmod 755 /var/tmp/tblSffasX2

# Create directory for the log file
mkdir /var/tmp/.xixXS244s
chmod 755 /var/tmp/.xixXS244s

# Create the log file with permissive permissions
touch /var/tmp/.xixXS244s/.mail
chmod 666 /var/tmp/.xixXS244s/.mail
```

### Step 2: Deploy the Shared Library (as root)

Copy the compiled `mailq.so` library to its designated path.

```bash
cp mailq.so /var/tmp/tblSffasX2/mailq.so
chmod 755 /var/tmp/tblSffasX2/mailq.so
```

### Step 3: Configure a Target User

This method backdoors the user's shell configuration file (`.bashrc` or `.profile`) to load the library. We create a small script that sets `LD_PRELOAD` and then re-executes the shell. An environment variable (`$MAILQ` or `$MAILQB`) is used as a guard to prevent an infinite recursion loop.

1.  **Create a hidden directory in the user's home (e.g., `user1`):**

    ```bash
    cd ~user1
    mkdir .sunw
    chown user1:staff .sunw
    cd .sunw
    ```

2.  **Create the loader scripts inside `~user1/.sunw/`:**

    Create `.mailq1` for **bash** users:
    ```bash
    # File: .mailq1
    if [ -z "$MAILQ" ]; then
      export MAILQ=1
      LD_PRELOAD=/var/tmp/tblSffasX2/mailq.so exec bash
    fi
    ```

    Create `.mailq2` for **Bourne shell (sh)** users:
    ```bash
    # File: .mailq2
    if [ -z "$MAILQB" ]; then
      export MAILQB=1
      export LD_PRELOAD=/var/tmp/tblSffasX2/mailq.so
      exec sh
    fi
    ```

3.  **Modify the user's shell profile to source the script:**

    *   For a **bash** user, add this line to the **top** of `~user1/.bashrc`:
        ```bash
        source ~/.sunw/.mailq1
        ```

    *   For a **Bourne shell (sh)** user, add this line to the **top** of `~user1/.profile`:
        ```bash
        . ~/.sunw/.mailq2
        ```

## Verification

1.  From any terminal, start monitoring the log file:
    ```bash
    tail -f /var/tmp/.xixXS244s/.mail
    ```

2.  In a new terminal, log in as the target user (`user1`) and execute some commands:
    ```bash
    $ ssh user1@host
    $ id
    uid=101(user1) gid=10(staff)
    $ ls -l /etc/passwd
    -r--r--r--   1 root     sys         2548 Dec 15  2023 /etc/passwd
    $
    ```

3.  Check the log file output. You should see entries similar to this:
    ```log
    [2024-11-20 12:13:12 - user1 - 3447 3430] /usr/bin/id: id
    [2024-11-20 12:13:17 - user1 - 3518 3430] /usr/bin/ls: ls -l /etc/passwd
    ```
    > **ℹ️ Note:** You may see multiple entries for a single command (e.g., `/usr/local/bin/ps` and `/usr/bin/ps`). This is normal. It reflects the shell searching through the directories in the `$PATH` variable and attempting to `execve` at each location until it finds the executable.

## Risks and Considerations

*   **Stability:** Injecting a shared library into a core process like a shell carries inherent risks. While tested, unexpected interactions could cause shell instability for the targeted user.
*   **System Accounts:** Avoid deploying this on high-volume system or automation accounts. The performance overhead of logging every command could impact critical automated tasks.
*   **Legitimate Use of `LD_PRELOAD`:** The tool intentionally unsets `LD_PRELOAD` for child processes. If a targeted user's workflow legitimately relies on `LD_PRELOAD` for other purposes, this tool will break that functionality.
