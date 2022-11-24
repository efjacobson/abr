const https = require('https');
const serialize = (object) => JSON.stringify(object, null, 2);

exports.handler = (event, context, callback) => {
    console.log('## ENVIRONMENT VARIABLES: ' + serialize(process.env));
    console.log('## CONTEXT: ' + serialize(context));
    console.log('## EVENT: ' + serialize(event));
    const options = {
        hostname: 'developer.mozilla.org',
        port: 443,
        path: '/en-US/docs/Web/API/URL/URL',
        method: 'GET'
    };

    const req = https.request(options, (res) => {
        console.log('## serialize(Object.keys(res)) ' + serialize(Object.keys(res)));
        console.log('## res.headers', serialize(res.headers));
        console.log('## res.rawHeaders', serialize(res.rawHeaders));
        const data = [];
        res.on('data', (d) => {
            data.push(d);
        });
        res.on('end', () => {
            const response = {
                body: '<html><head><title>hi</title></head><body><p>sup</p></body></html>',
                bodyEncoding: 'text',
                status: '200',
                headers: res.headers,
                statusDescription: res.statusMessage,
            };
            callback(null, response);
        })
    });

    req.on('error', (e) => {
        console.error(e);
        callback(Error(e));
    });
    req.end();
}