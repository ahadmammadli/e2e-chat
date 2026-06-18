# e2e-chat

A simple end-to-end encrypted terminal chat written in Bash using age and socat.

# Features

* End-to-end encrypted messages
* Relay server sees ciphertext only
* No accounts
* No databases
* No cloud dependencies
* Works across Linux, macOS, and other Unix-like environments
* Uses modern age encryption

# Requirements

Client

* Bash
* age
* socat

Relay

* Bash
* socat
* flock

# Generate Keys

```
mkdir -p ~/.config/e2e-chat
age-keygen -o ~/.config/e2e-chat/identity.txt
grep -Eo 'age1[0-9a-z]+' ~/.config/e2e-chat/identity.txt > ~/.config/e2e-chat/recipients.txt
cat ~/.config/e2e-chat/recipients.txt
```

Share the public key from recipients.txt with other users.

Add all participant public keys to:

```
~/.config/e2e-chat/recipients.txt
```

# Start Relay

```
chmod +x relay.sh
./relay.sh
```

# Start Client

```
chmod +x chat.sh
./chat.sh
```

Enter:

* Relay IP / hostname
* Relay port
* Username

# Security Notes

* Never share identity.txt
* Verify public keys out-of-band
* The relay can see metadata such as IP addresses and connection timing
* The relay cannot read encrypted messages

# License

MIT
