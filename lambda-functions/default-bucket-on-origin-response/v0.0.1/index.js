const log = (label, object) => console.log(`${label}:`, JSON.stringify(object, null, 2))

exports.handler = (event, context, callback) => {
    log('process.env', process.env);
    log('event', event);
    log('context', context);
    log('event.Records[0].cf.response', event.Records[0].cf.response);

    const request = event.Records[0].cf.request;
    const response = event.Records[0].cf.response;

    const headerName = 'X-Table-Tennis';
    response.headers[headerName.toLowerCase()] = [{
        value: request.headers?.[headerName.toLowerCase()]?.[0]?.value === 'ping' ? 'pong' : 'ping',
    }];

    log('response', response);
    callback(null, response);
}