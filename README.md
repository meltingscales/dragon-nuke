# dragon-reboot
remotely reboot using a gcp object storage listener that can be written to by a phone

## gcp configuration

- object storage: 1 file
- starts off as the string "safe"

## phone app "DragonRebootApp"

- login with creds to GCP that has write perms to object storage
- button to write "REBOOT=TRUE" to a gcp object storage file, prompts quickly ARE YOU SURE?
- that's literally it.

## server listener "DragonRebootServer"

- runs as root
- reads from object storage once per 10 seconds. if it detects exactly `REBOOT=TRUE`, then it runs this script:

```
#!/usr/bin/env bash

echo "DragonReboot triggered! Rebooting..."

# send popup message to all logged on users with screen/x11/etc

# sleep 60

reboot now
```
