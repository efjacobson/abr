#! /usr/bin/env bash
set -e

self="${BASH_SOURCE[0]}"
while [ -L "${self}" ]; do
    self_dir="$(cd -P "$(dirname "${self}")" >/dev/null 2>&1 && pwd)"
    self="$(readlink "${self}")"
    [[ ${self} != /* ]] && self="${self_dir}/${self}"
done
self="$(readlink -f "${self}")"
selfdir=$(dirname "${self}")

if [ -e "${selfdir}/.env" ]; then
    set -a
    source "${selfdir}/.env"
    set +a
fi

parameter_overrides="$(jq '.' <<< "[\"SiteDomainName=${ABR_SITE_DOMAIN_NAME}\"]")"
deploy() {
    aws cloudformation deploy \
        --region "${ABR_REGION}" \
        --profile "${ABR_PROFILE}" \
        --stack-name "${ABR_STACK_NAME}" \
        --capabilities CAPABILITY_NAMED_IAM \
        --template-file "${selfdir}/stack.yaml" \
        --parameter-overrides "$(jq -c '.' <<< "${parameter_overrides}")"
}

if ! [ "$(

aws cloudformation describe-stacks \
    --region "${ABR_REGION}" \
    --profile "${ABR_PROFILE}" \
    --stack-name "${ABR_STACK_NAME}"

)" ]; then
    deploy
fi

while read -r resource; do
    id="$(jq -r '.LogicalResourceId' <<< "${resource}")"
    type="$(jq -r '.ResourceType' <<< "${resource}")"
    case "${type}" in
        'AWS::CloudFront::Distribution')
            if [ "${id}" == "OriginDistribution" ]; then
                parameter_overrides="$(jq '. += ["OriginDistributionExists=true"]' <<< "${parameter_overrides}")"
            fi
            ;;
        'AWS::S3::Bucket')
            if [ "${id}" == "OriginBucket" ]; then
                parameter_overrides="$(jq '. += ["OriginBucketExists=true"]' <<< "${parameter_overrides}")"
            fi
            ;;
    esac
done < <(
    aws cloudformation list-stack-resources \
        --region "${ABR_REGION}" \
        --profile "${ABR_PROFILE}" \
        --stack-name "${ABR_STACK_NAME}" \
        --query 'StackResourceSummaries[?ResourceType==`AWS::CloudFront::Distribution` || ResourceType==`AWS::S3::Bucket`].{LogicalResourceId: LogicalResourceId, ResourceType: ResourceType}' \
    | jq -c '.[]'
)

deploy