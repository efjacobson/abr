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

    origin_distribution_id="$(

aws cloudformation describe-stacks \
    --region "${ABR_REGION}" \
    --profile "${ABR_PROFILE}" \
    --stack-name "${ABR_STACK_NAME}" \
    --query 'Stacks[0].Outputs[?OutputKey==`OriginDistributionId`].OutputValue' \
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

if [ -z "${origin_distribution_id}" ]; then
    echo 'unable to determine origin distribution id'
    exit 1
fi

mime_type() {
    local path="${1}"
    local extension
    extension="${path##*.}"
    if [ 'css' == "${extension}" ]; then
        echo 'text/css'
    elif [ 'html' == "${extension}" ]; then
        echo 'text/html'
    elif [ 'js' == "${extension}" ]; then
        echo 'application/javascript'
    elif [ 'json' == "${extension}" ]; then
        echo 'application/json'
    elif [ 'png' == "${extension}" ]; then
        echo 'image/png'
    elif [ 'svg' == "${extension}" ]; then
        echo 'image/svg+xml'
    elif [ 'txt' == "${extension}" ]; then
        echo 'text/plain'
    elif [ 'xml' == "${extension}" ]; then
        echo 'application/xml'
    else
        file --mime-type "${path}" | cut -d' ' -f2
    fi
}

while read -r tpl; do
        dest="${tpl%.*}"
        envsubst < "${tpl}" > "${dest}"
done < <(find "${selfdir}/origin" -type f -name "*.tpl")

images_json_key='images.json'
invalidation_paths=()
while read -r path; do
    key="${path/$selfdir\/origin\//}"
    if [ "${key}" == "${images_json_key}" ]; then
        continue
    fi

    extension="${path##*.}"
    if [ "${extension}" == 'tpl' ]; then
        continue
    fi

    local_etag="$(md5sum "${path}" | cut -d ' ' -f 1)"
    aws_etag="$(
        curl -sI "https://${ABR_SITE_DOMAIN_NAME}/${key}" | grep etag | cut -d ' ' -f 2 | cut -d '"' -f 2
    )"

    if [ "${local_etag}" == "${aws_etag}" ]; then
        continue
    fi

    if [ -n "${aws_etag}" ]; then
        invalidation_paths+=("${key}")
    fi

    checksum="$(openssl dgst -sha256 -binary "${path}" | openssl enc -base64)"
    aws s3api put-object \
        --body "$(realpath "${path}")" \
        --bucket "${bucket}" \
        --checksum-sha256 "${checksum}" \
        --content-type "$(mime_type "${path}")" \
        --key "${key}" \
        --profile "${ABR_PROFILE}"

done < <(find "${selfdir}/origin" -type f)

while read -r tpl; do
        dest="${tpl%.*}"
        rm "${dest}"
done < <(find "${selfdir}/origin" -type f -name "*.tpl")

images_json_path="${selfdir}/origin/${images_json_key}"
aws s3api list-objects-v2 \
    --bucket "${bucket}" \
    --profile "${ABR_PROFILE}" \
    --query 'Contents[?Size > `0`].Key' \
    --prefix 'image/' | jq '. | map(select(. | test(".optimized.jpg$")))' > "${images_json_path}"

local_etag="$(md5sum "${images_json_path}" | cut -d ' ' -f 1)"
aws_etag="$(
    curl -sI "https://${ABR_SITE_DOMAIN_NAME}/${images_json_key}" | grep etag | cut -d ' ' -f 2 | cut -d '"' -f 2
)"

if [ "${local_etag}" != "${aws_etag}" ]; then
    aws s3api put-object \
        --body "${images_json_path}" \
        --bucket "${bucket}" \
        --checksum-sha256 "$(openssl dgst -sha256 -binary "${images_json_path}" | openssl enc -base64)" \
        --content-type "$(mime_type "${images_json_path}")" \
        --key "${images_json_key}" \
        --profile "${ABR_PROFILE}"
    invalidation_paths+=("${images_json_key}")
fi

if [ ${#invalidation_paths[@]} -eq 0 ]; then
    exit
fi

paths=
for path in "${invalidation_paths[@]}"; do
    paths="${paths} /${path}"
done

echo "paths needing invalidation: ${paths}"

# aws cloudfront create-invalidation \
#     --distribution-id "${origin_distribution_id}" \
#     --paths $paths \
#     --profile "${ABR_PROFILE}"