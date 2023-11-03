const log = (label, object) => console.log(`${label}:`, JSON.stringify(object, null, 2))

exports.handler = (event, context, callback) => {
    const request = event.Records[0].cf.request;
    log('request', request);

    if (request.method !== 'POST') {
        return callback(null, request);
    }

    const body = Buffer.from(request.body.data, request.body.encoding).toString();
    log('body', body);

    callback(null, request);
}