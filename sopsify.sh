#!/bin/bash

# Script expects the path to file to be encoded as 1-st mandatory argument
# Optional 2-nd argument is SOPS secret's name, which defaults to "sops-gpg"

# Check arguments
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "Usage: $0 <unencrypted_file> [name_of_secret]"
  exit 1
fi

# Import pubkey from local file
gpg --import .sops.pub.asc

# Unencrypted Kubernetes secret file name
input_file=$1

# Encrypted Kubernetes secret file name
output_file="${input_file%.*}-sops.${input_file##*.}"

gpg --import .sops.pub.asc

sleep 1

# Secret's name (defaults to "sops-gpg")
flux_secret_name=${2:-"sops-gpg"}

# Extract fingerprint fom local .sops.pub.asc file
local_pubkeyfile_fp=$(gpg --batch --with-fingerprint --with-colons ".sops.pub.asc" 2>/dev/null | awk -F: '$1 == "fpr" {print $10}')

## Получить список всех ключей в keyring
key_ids=$(gpg --list-keys --with-colons | awk -F: '/^pub:/ {print $5}')

# Перебор ключей и вывод информации только для ключей, соответствующих условию
for key_id in $key_ids; do
    fingerprint=$(gpg --fingerprint --with-colons "$key_id" | awk -F: '/^fpr:/ {print $10}' | head -n 1)
    uid=$(gpg --list-keys --with-colons "$key_id" | awk -F: '/^uid:/ {print $10}')
    
    # Проверка условия и вывод информации только для подходящих ключей
    if [[ "$uid" == "$flux_secret_name" || "$uid" == "$flux_secret_name "* ]] && [[ "$fingerprint" != "$local_pubkeyfile_fp" ]]; then
        # echo "Key ID: $key_id, Fingerprint: $fingerprint, UID: $uid"
        gpg --delete-keys $fingerprint
    fi
done

# Get public key fingerprint
pub_fingerprint=$(gpg --fingerprint "$flux_secret_name" | grep -A 1 "pub" | grep -v "pub" | tr -d '[:space:]' | tr 'A-F' 'a-f')

# Check if there is a key in keyring wtih fingerprint equal to local file's one
if [ -z "$pub_fingerprint" ]; then
    echo "No fingerprint for $flux_secret_name public key detected, importing from local file"
    sleep 1
fi

# File encryption
sops --encrypt --pgp "$pub_fingerprint" --encrypted-regex '^(data|stringData)$' --input-type yaml --output-type yaml "$input_file" > "$output_file"


echo "Successfully encrypted: $output_file"
echo "Pubkey is: $pub_fingerprint"