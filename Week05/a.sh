bash -x "$(which ishare2)" pull qemu 102 --overwrite 2>&1 | grep -o 'https\?://[^ "'"'"']*' | sort -u
