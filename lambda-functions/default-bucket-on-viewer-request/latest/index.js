const log = (label, object) => console.log(`${label}:`, JSON.stringify(object, null, 2))

exports.handler = (event, context, callback) => {
    log('process.env', process.env);
    log('event', event);
    log('context', context);
    log('event.Records[0].cf.request', event.Records[0].cf.request);

    const request = event.Records[0].cf.request;
    log('request', request);

    callback(null, request);
}