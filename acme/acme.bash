#! /usr/bin/env bash
set -e

profile='personal'
region='us-east-1'
whoareyou=
identity_file=
instance_id=
terminate=true
domain=
tld=

self="${BASH_SOURCE[0]}"
while [ -L "${self}" ]; do
    self_dir="$(cd -P "$(dirname "${self}")" >/dev/null 2>&1 && pwd)"
    self="$(readlink "${self}")"
    [[ ${self} != /* ]] && self="${self_dir}/${self}"
done
self="$(readlink -f "${self}")"
selfdir=$(dirname "${self}")


display_help() {
  echo "
Available options:
    --profile=      The AWS profile to use (default: ${profile})
    --region=       The AWS region to use (default: ${region})
    --domain        The domain to use
    --tld           The TLD to use
    --instance-id=  The instance ID
    --terminate=    Whether to stop the instance at the end (default: ${terminate})
    --preserve      Equivalant to --terminate=false
    --help          This message
"
}

for opt in "$@"; do
  case ${opt} in
  --profile=*)
    profile="${opt#*=}"
    ;;
  --domain=*)
    domain="${opt#*=}"
    ;;
  --tld=*)
    tld="${opt#*=}"
    ;;
  --region=*)
    region="${opt#*=}"
    ;;
  --instance-id=*)
    instance_id="${opt#*=}"
    ;;
  --whoareyou=*)
    whoareyou="${opt#*=}"
    ;;
  --identity-file=*)
    identity_file="${opt#*=}"
    ;;
  --terminate=*)
    if [ 'false' == "${opt#*=}" ]; then
      terminate=false
    fi
    ;;
  --preserve)
    terminate=false
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

required_args=('whoareyou' 'identity_file' 'instance_id' 'domain' 'tld')
for arg in "${required_args[@]}"; do
  [ -z "${!arg}" ] && echo "${arg} is required" && exit 1
done

state=
describe_response=
started=false

describe() {
    describe_response=$(aws ec2 describe-instances \
        --instance-ids "${instance_id}" \
        --profile "${profile}" \
        --region "${region}")
    state=$(jq -r '.Reservations[0].Instances[0].State.Name' <<< "${describe_response}")
}

start() {
    aws ec2 start-instances \
        --instance-ids "${instance_id}" \
        --profile "${profile}" \
        --region "${region}"

    describe

    while [ 'running' != "${state}" ]; do
        sleep 5
        describe
    done

    started=true
}

stop() {
    aws ec2 stop-instances \
        --instance-ids "${instance_id}" \
        --profile "${profile}" \
        --region "${region}"

    describe

    while [ 'stopping' != "${state}" ]; do
        sleep 5
        describe
    done
}

main() {
    describe
    while [ 'stopping' == "${state}" ]; do
        sleep 5
        describe
    done

    if [ 'stopped' == "${state}" ]; then
        start
    fi

    if [ 'running' != "${state}" ]; then
        echo "Instance state ${state} is not valid"
    fi

    public_ip=$(jq -r '.Reservations[0].Instances[0].PublicIpAddress' <<< "${describe_response}")

    printf "\npublic ip: %s\n\n" "${public_ip}"

    if [ "${started}" == 'true' ]; then
      echo 'waiting for sshd to start. you should go update dns...'
      printf 'countdown: '
      for i in {30..1}
      do
        printf '%s...' $i
        sleep 1
      done
      echo ''
    fi

    scp -i "${identity_file}" -o StrictHostKeyChecking=no "${selfdir}/acme-issue.bash" "${whoareyou}@${public_ip}:/home/${whoareyou}/scripts/acme-issue.bash"
    scp -i "${identity_file}" -o StrictHostKeyChecking=no "${selfdir}/acme-renew.bash" "${whoareyou}@${public_ip}:/home/${whoareyou}/scripts/acme-renew.bash"
    scp -i "${identity_file}" -o StrictHostKeyChecking=no "${selfdir}/acme-renew-all.bash" "${whoareyou}@${public_ip}:/home/${whoareyou}/scripts/acme-renew-all.bash"

    if [ "${started}" == 'false' ]; then
      while true; do
        read -r -p "did you remember to update dns? (y/N): " answer
        case "$answer" in
        Y | y)
          ssh -i "${identity_file}" -t "${whoareyou}@${public_ip}" -o StrictHostKeyChecking=no "sudo /home/${whoareyou}/scripts/acme-renew-all.bash --identity_file=${identity_file} --whoareyou=${whoareyou} --domain=${domain} --tld=${tld} --yolo"
          break
          ;;
        *)
          break
          ;;
        esac
      done
    fi

    if [ 'true' == "${terminate}" ]; then
      stop
    fi
}


cp "${HOME}/.ssh/known_hosts" "${HOME}/.ssh/known_hosts.bak"
trap 'mv "${HOME}/.ssh/known_hosts.bak" "${HOME}/.ssh/known_hosts"' EXIT

main