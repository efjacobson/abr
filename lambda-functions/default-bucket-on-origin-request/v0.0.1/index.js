const querystring = require('querystring');

const serialize = (object) => JSON.stringify(object, null, 2);

exports.handler = (event, context, callback) => {
    console.log('process.env', serialize(process.env));
    console.log('event', serialize(event));
    console.log('context', serialize(context));

    const request = event.Records[0].cf.request;

    const params = querystring.parse(request.querystring);
    console.log('params', params);

    if (params.tabletennis) {
        const headerName = 'X-Table-Tennis';
        request.headers[headerName.toLowerCase()] = [{ value: 'ping' }];
        delete params.tabletennis;
        request.querystring = querystring.stringify(params);
    }

    const testHeaderName = 'X-Abr-Test-Request';
    request.headers[testHeaderName.toLowerCase()] = [{
        value: (() => {
            let token = String(Math.ceil(Math.random() * 1000));
            while (token.length < 4) {
                token = `0${token}`;
            }
            return token;
        }
        )(),
    }];

    console.log('request', serialize(request));
    callback(null, request);
}