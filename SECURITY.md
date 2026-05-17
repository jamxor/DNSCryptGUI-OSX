## Application Based Countermeasures 

Both the DNSCryptGUIHelper and the DNSCryptGUI.app binaries are cryptographically signed by the Apple Developer ID certificate. The Helper is locked down to only allow a specific co-signed GUI to interact with it. In Addition to this, the Helper utilises the SMAppService status for a read-only view of the current registration / authorization state of the executable (Launch Daemon). 

## allowedConfigPaths

To Prevent a malicious client from using the helper as an arbitrary root-file-write primitive, DNSCryptGUI is locked to only allow write commands to by passed to the following locations:

        '/opt/homebrew/etc/dnscrypt-proxy.toml'
        '/usr/local/etc/dnscrypt-proxy.toml'

The Helper never calls the register() function and never force-opens the system settings, this is and should remain under full control of the user. Non-privileged features run through the GUI and are passed to the OS, anything that requires root is proxied through to the Helper over for seperation, as that runs as root.

## Security Policy

I will continue to audit the code when possible before each release, for now, feel free to raise any potential issues you notice.

## Supported Versions

Feature and security updates will continue to be released indefinatly with support being supplied for the latest versions of the application.

| Version | Supported          |
| ------- | ------------------ |
| 2.0.x   | n/a                |
| 1.0.x   | :white_check_mark: |
| 0.1.x.  | :x:                |

## Reporting a Vulnerability

If you notice a potential security problem, open an issue and tag it with the "Vulnerability" label. This ensures the issue is addressed as top priority.
