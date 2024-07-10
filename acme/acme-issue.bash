#! /usr/bin/env bash
set -e

whoareyou=
subdomain=
domain=
tld=

display_help() {
  echo "
Available options:
    --whoareyou The user to run as
    --subdomain The subdomain to use
    --domain    The domain to use
    --tld       The TLD to use
    --help      This message
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

templatesubdomain='sb'
site="${subdomain}.${domain}.${tld}"

while true; do
  read -r -p "do first-time acme setup for ${site}? (y/N): " answer
  case "$answer" in
  Y | y)
    break
    ;;
  *)
    exit 0
    ;;
  esac
done

here_ip="$(dig +short myip.opendns.com @resolver1.opendns.com)"
dns_ip="$(dig "${site}" | jc --dig | jq -r '.[0].answer[0].data')"
if [[ "${here_ip}" != "${dns_ip}" ]]; then
  echo 'dns is not setup!'
  exit 1
fi

cp "/etc/nginx/sites-available/${templatesubdomain}.${domain}.${tld}" "/etc/nginx/sites-available/${site}"
sed -i "s|${templatesubdomain}\.|${subdomain}\.|g" "/etc/nginx/sites-available/${site}"
sed -i "s|ssl_certificate|#ssl_certificate|g" "/etc/nginx/sites-available/${site}"
ln -s "/etc/nginx/sites-available/${site}" "/etc/nginx/sites-enabled/${site}"
cp -r "/var/www/${templatesubdomain}.${domain}.${tld}" "/var/www/${site}"
sed -i "s|${templatesubdomain}[[:space:]]dot|${subdomain} dot|g" "/var/www/${site}/index.html"
sed -i "s|acme[[:space:]]${templatesubdomain}[[:space:]]dot|acme ${subdomain} dot|g" "/var/www/${site}/.well-known/acme-challenge/index.html"
chown -R www-data:www-data "/var/www/${site}"
chmod -R 775 "/var/www/${site}"
systemctl restart nginx
runuser -u acme -- /etc/acme/.acme.sh/acme.sh --issue -d "${site}" -w "/var/www/${site}" --reloadcmd 'sudo /bin/systemctl reload nginx'
mkdir "/etc/nginx/ssl/${site}"
chown -R acme:acme "/etc/nginx/ssl/${site}"
runuser -u acme -- ln -s "/etc/acme/.acme.sh/${site}_ecc/${site}.key" "/etc/nginx/ssl/${site}/${site}.key"
ln -s "/etc/acme/.acme.sh/${site}_ecc/${site}.cer" "/etc/nginx/ssl/${site}/${site}.cer"
sed -i "s|#ssl_certificate|ssl_certificate|g" "/etc/nginx/sites-available/${site}"
systemctl restart nginx
runuser -u acme -- /etc/acme/.acme.sh/acme.sh --to-pkcs12 -d "${site}"
openssl pkcs12 -export -out "/etc/acme/.acme.sh/${site}_ecc/${site}.p12" \
  -certpbe AES-256-CBC \
  -keypbe AES-256-CBC \
  -macalg SHA256 \
  -inkey "/etc/acme/.acme.sh/${site}_ecc/${site}.key" \
  -in "/etc/acme/.acme.sh/${site}_ecc/${site}.cer" \
  -certfile "/etc/acme/.acme.sh/${site}_ecc/ca.cer" \
  -password pass:""
7z a "/home/${whoareyou}/${site}_ecc.7z" "/etc/acme/.acme.sh/${site}_ecc" -p -mhe=on
chown "${whoareyou}:${whoareyou}" "/home/${whoareyou}/${site}_ecc.7z"
echo "you have 60 seconds to run this command: scp ${whoareyou}@${here_ip}:/home/${whoareyou}/${site}_ecc.7z ./"
sleep 60
rm "/home/${whoareyou}/${site}_ecc.7z"