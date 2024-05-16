#! /usr/bin/env bash

profile='personal'
region='us-east-1'
dry_run=true
user=
identity_file=
instance_id=


display_help() {
  echo "
Available options:
    --profile       The AWS profile to use (default: ${profile})
    --region        The AWS region to use (default: ${region})
    --instance-id   The instance ID
    --dry-run       Whether to perform a dry-run (default: ${dry_run})
    --hot           Equivelant to --dry-run=false
    --help          This message
"
}

for opt in "$@"; do
  case ${opt} in
  --profile=*)
    profile="${opt#*=}"
    ;;
  --region=*)
    region="${opt#*=}"
    ;;
  --instance-id=*)
    instance_id="${opt#*=}"
    ;;
  --user=*)
    user="${opt#*=}"
    ;;
  --identity-file=*)
    identity_file="${opt#*=}"
    ;;
  --dry-run=*)
    if [ 'false' == "${opt#*=}" ]; then
      dry_run=false
    fi
    ;;
  --hot)
    dry_run=false
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

required_args=('user' 'identity_file' 'instance_id')
for arg in "${required_args[@]}"; do
  [ -z "${!arg}" ] && echo "${arg} is required" && exit 1
done

state=
describe_response=

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

    sleep 30 # give sshd time to start

    ssh -i "${identity_file}" -t "${user}@${public_ip}" -o StrictHostKeyChecking=no 'sudo /root/scripts/acme-renew-all.bash --yolo'

    stop
}

main