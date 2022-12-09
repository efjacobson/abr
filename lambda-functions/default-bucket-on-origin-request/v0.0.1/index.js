const serialize = (object) => JSON.stringify(object, null, 2);

exports.handler = (event, context, callback) => {
    console.log('process.env', serialize(process.env));
    console.log('event', serialize(event));
    console.log('context', serialize(context));

    const request = event.Records[0].cf.request;
    const urlSearchParams = new URLSearchParams(request.querystring);

    if (urlSearchParams.has('ping')) {
        const headerName = 'X-Table-Tennis';
        request.headers[headerName.toLowerCase()] = [{ value: 'ping' }];
        urlSearchParams.delete('ping');
    }

    request.querystring = urlSearchParams.toString();
    console.log('request', serialize(request));
    callback(null, request);
}