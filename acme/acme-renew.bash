#! /usr/bin/env bash
set -e

whoareyou=
subdomain=
domain=
tld=
yolo='false'
sites=()

display_help() {
  echo "
Available options:
    --whoareyou     The user to run as
    --subdomain     The subdomain to use
    --domain        The domain to use
    --tld           The TLD to use
    --sites         Comma separated list of sites
    --yolo          Skip all confirmations
    --identity_file The identity file to in the resulting scp command
    --help          This message
"
}

for opt in "$@"; do
  case ${opt} in
  --whoareyou=*)
    whoareyou="${opt#*=}"
    ;;
  --subdomain=*)
    subdomain="${opt#*=}"
    ;;
  --domain=*)
    domain="${opt#*=}"
    ;;
  --tld=*)
    tld="${opt#*=}"
    ;;
  --identity_file=*)
    identity_file="${opt#*=}"
    ;;
  --sites=*)
    IFS=',' read -r -a sites <<< "${opt#*=}"
    ;;
  --yolo)
    yolo='true'
    ;;
  --help)
    display_help
    exit
    ;;
  *)
    display_help
    exit
    ;;
  esac
done

required_args=('whoareyou' 'identity_file')
for arg in "${required_args[@]}"; do
  [ -z "${!arg}" ] && echo "${arg} is required" && exit 1
done

if [ "${yolo}" != 'true' ]; then
  while true; do
    read -r -p "did you remember to update dns? (y/N): " answer
    case "$answer" in
    Y | y)
      break
      ;;
    *)
      exit 1
      ;;
    esac
  done
fi

if [ ${#sites[@]} -eq 0 ]; then
  args=('subdomain' 'domain' 'tld')
  for arg in "${args[@]}"; do
    if [ -n "${!arg}" ]; then
      continue
    fi
    while true; do
      read -r -p "which ${arg}? " answer
      case "${answer}" in
      '')
        echo "an empty string is not a valid ${arg}"
        exit 1
        ;;
      *)
        eval "${arg}=${answer}"
        break
        ;;
      esac
    done
  done
  sites+=("${subdomain}.${domain}.${tld}")
fi

if [ "${yolo}" != 'true' ]; then
  while true; do
    read -r -p "renew cert(s) for $(IFS=','; echo "${sites[*]}")? (y/N): " answer
    case "${answer}" in
    Y | y)
      break
      ;;
    *)
      exit 0
      ;;
    esac
  done
fi

mkdir "/home/${whoareyou}/certs"
for site in "${sites[@]}"; do
  here_ip="$(dig +short myip.opendns.com @resolver1.opendns.com)"
  dns_ip="$(dig "${site}" | jc --dig | jq -r '.[0].answer[0].data')"
  if [[ "${here_ip}" != "${dns_ip}" ]]; then
    echo "dns is not setup for ${site}!"
    exit 1
  fi

  runuser -u acme -- /etc/acme/.acme.sh/acme.sh --renew -d "${site}" --force
  if [ -e "/etc/nginx/ssl/${site}/${site}.key" ]; then
    mv "/etc/nginx/ssl/${site}/${site}.key" "/etc/nginx/ssl/${site}/${site}.key.bak"
  fi
  if [ -e "/etc/nginx/ssl/${site}/${site}.cer" ]; then
    mv "/etc/nginx/ssl/${site}/${site}.cer" "/etc/nginx/ssl/${site}/${site}.cer.bak"
  fi
  ln -s "/etc/acme/.acme.sh/${site}_ecc/${site}.key" "/etc/nginx/ssl/${site}/${site}.key"
  ln -s "/etc/acme/.acme.sh/${site}_ecc/${site}.cer" "/etc/nginx/ssl/${site}/${site}.cer"

  systemctl restart nginx

  echo ''
  echo 'EMPTY PASSWORD'
  echo ''

  runuser -u acme -- /etc/acme/.acme.sh/acme.sh --to-pkcs12 -d "${site}" --force
  openssl pkcs12 -export -out "/etc/acme/.acme.sh/${site}_ecc/${site}.p12" \
    -certpbe AES-256-CBC \
    -keypbe AES-256-CBC \
    -macalg SHA256 \
    -inkey "/etc/acme/.acme.sh/${site}_ecc/${site}.key" \
    -in "/etc/acme/.acme.sh/${site}_ecc/${site}.cer" \
    -certfile "/etc/acme/.acme.sh/${site}_ecc/ca.cer" \
    -password pass:""

  7z a "/home/${whoareyou}/${site}_ecc.7z" "/etc/acme/.acme.sh/${site}_ecc"
  chown "${whoareyou}:${whoareyou}" "/home/${whoareyou}/${site}_ecc.7z"
  mv "/home/${whoareyou}/${site}_ecc.7z" "/home/${whoareyou}/certs/"

  if [ -e "/etc/nginx/ssl/${site}/${site}.key.bak" ]; then
    rm "/etc/nginx/ssl/${site}/${site}.key.bak"
  fi
  if [ -e "/etc/nginx/ssl/${site}/${site}.cer.bak" ]; then
    rm "/etc/nginx/ssl/${site}/${site}.cer.bak"
  fi
done

echo ''
echo 'THIS IS THE 7Z PASSWORD'
echo ''

7z a "/home/${whoareyou}/certs.7z" "/home/${whoareyou}/certs" -p -mhe=on
chown "${whoareyou}:${whoareyou}" "/home/${whoareyou}/certs.7z"
echo "you have 60 seconds to run this command: scp -i ${identity_file} ${whoareyou}@${here_ip}:/home/${whoareyou}/certs.7z ./"

sleep 60
rm "/home/${whoareyou}/certs.7z"
rm -rf "/home/${whoareyou}/certs"