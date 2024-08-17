#! /usr/bin/env bash
set -e

yolo='false'
domain=
tld=

display_help() {
  echo "
Available options:
    --whoareyou The user to run as
    --domain    The domain to use
    --tld       The TLD to use
    --yolo      Skip all confirmations
    --help      This message
"
}

for opt in "$@"; do
  case ${opt} in
  --whoareyou=*)
    whoareyou="${opt#*=}"
    ;;
  --yolo)
    yolo='true'
    ;;
  --domain=*)
    domain="${opt#*=}"
    ;;
  --tld=*)
    tld="${opt#*=}"
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

required_args=('whoareyou' 'domain' 'tld')
for arg in "${required_args[@]}"; do
  [ -z "${!arg}" ] && echo "${arg} is required" && exit 1
done

self="${BASH_SOURCE[0]}"
while [ -L "${self}" ]; do
    self_dir="$(cd -P "$(dirname "${self}")" >/dev/null 2>&1 && pwd)"
    self="$(readlink "${self}")"
    [[ ${self} != /* ]] && self="${self_dir}/${self}"
done
self="$(readlink -f "${self}")"
selfdir=$(dirname "${self}")

if [ "${yolo}" != 'true' ]; then
  while true; do
    read -r -p "did you remember to update dns? (y/N): " answer
    case "${answer}" in
    Y | y)
      break
      ;;
    *)
      exit 1
      ;;
    esac
  done
fi

subdomains=('ha' 'omv' 'plex' 'pp' 'prime' 'pve' 'sb')

sites=()
for subdomain in "${subdomains[@]}"; do
    sites+=("${subdomain}.${domain}.${tld}")
done

cmd="${selfdir}/acme-renew.bash --whoareyou=${whoareyou} --sites=$(IFS=','; echo "${sites[*]}")"

if [ "${yolo}" == 'true' ]; then
  cmd="${cmd} --yolo"
fi

eval "${cmd}"