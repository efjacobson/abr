#! /usr/bin/env bash
# set -x

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

for evar in 'ABR_REGION' 'ABR_PROFILE' 'ABR_STACK_NAME' 'ABR_SITE_DOMAIN_NAME'; do
    if [ -z "${!evar}" ]; then
        echo "Environment variable ${evar} is not set"
        exit 1
    fi
done

origin_bucket_arn=
while read -r id; do
    if [ "${id}" != 'OriginBucket' ]; then
        continue
    fi
    origin_bucket_arn="$(

aws cloudformation describe-stacks \
    --region "${ABR_REGION}" \
    --profile "${ABR_PROFILE}" \
    --stack-name "${ABR_STACK_NAME}" \
    --query 'Stacks[0].Outputs[?OutputKey==`OriginBucketArn`].OutputValue' \
    --output text

)"

    break
done < <(
    aws cloudformation list-stack-resources \
        --region "${ABR_REGION}" \
        --profile "${ABR_PROFILE}" \
        --stack-name "${ABR_STACK_NAME}" \
        --query 'StackResourceSummaries[?ResourceType==`AWS::S3::Bucket`].LogicalResourceId' \
    | jq -cr '.[]'
)

if [ -z "${origin_bucket_arn}" ]; then
    echo 'unable to determine origin bucket arn'
    exit 1
fi
bucket="${origin_bucket_arn/arn:aws:s3:::/}"

optimized_images="$(

aws s3api list-objects-v2 \
    --bucket "${bucket}" \
    --profile "${ABR_PROFILE}" \
    --query 'Contents[?Size > `0`].Key' \
    --prefix 'image/' | jq -r '. | map(select(. | test(".optimized.jpg$"))) | .[]'

)"

qrcodes="$(jq '.' <<< '{}')"
while read -r key; do
    extension="${key##*.}"
    key_without_optimized_or_extension="${key%.optimized.${extension}}"
    original="${key_without_optimized_or_extension}.${extension}"
    absolute="${ABR_SITE_DOMAIN_NAME}/${original}"
    tmp="$(mktemp).svg"
    segno "${absolute}" -o "${tmp}"
    qrcodes="$(jq --arg qrcode "$(base64 -w 0 < "${tmp}")" ".[\"${original}\"] = \$qrcode" <<< "${qrcodes}")"
    rm -f "${tmp}"
done <<< "${optimized_images}"

echo "export default $(jq '.' <<< "${qrcodes}")" > "${selfdir}/origin/qrcodes.mjs"