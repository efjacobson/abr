const serialize = (object) => JSON.stringify(object, null, 2);

exports.handler = (event, context, callback) => {
    console.log('process.env', serialize(process.env));
    console.log('event', serialize(event));
    console.log('context', serialize(context));
    console.log('context', serialize(context));

    const request = event.Records[0].cf.request;
    const response = event.Records[0].cf.response;

    const tableTennisHeaderName = 'X-Table-Tennis';
    response.headers[tableTennisHeaderName.toLowerCase()] = [{
        value: request.headers?.[tableTennisHeaderName.toLowerCase()]?.[0]?.value === 'ping' ? 'pong' : 'ping',
    }];

    console.log('response', serialize(response));
    callback(null, response);
}