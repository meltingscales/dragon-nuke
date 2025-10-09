# dragon-nuke
remotely nuke all block devices using a gcp object storage listener that can be written to by a phone

## gcp configuration

- object storage: 1 file
- starts off as the string "safe"

## phone app "DragonNukeApp"

- login with creds to GCP that has write perms to object storage
- button to write "NUKE=TRUE" to a gcp object storage file, prompts quickly ARE YOU SURE?
- that's literally it.

## server listener "DragonNukeServer"

- runs as root
- reads from object storage once per 10 seconds. if it detects exactly `NUKE=TRUE`, then it runs this script:
  - [link](./server-dragon-nuke/scripts/dragon-nuke.sh)