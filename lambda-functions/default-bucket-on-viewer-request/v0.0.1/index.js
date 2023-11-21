const crypto = require('crypto');

const COOKIE = 'abr.id'
const TWENTY_YEARS_IN_SECONDS = 20 * 365 * 24 * 60 * 60;
const UUID_REGEX = new RegExp(`^${[8, 4, 4, 4, 12].map(n => `[0-9a-fA-F]{${n}}`).join('-')}$`);

const isUuidV4 = (value) => UUID_REGEX.test(value) && value[14] === '4';

const createResponse = (domain, value) => ({
    status: '200',
    statusDescription: 'OK',
    body: JSON.stringify({ [COOKIE]: value }),
    headers: {
        'set-cookie': [{
            key: 'Set-Cookie',
            value: [
                `${COOKIE}=${value}`,
                `expires=${new Date(Date.now() + TWENTY_YEARS_IN_SECONDS * 1000).toUTCString()}`,
                `Max-Age=${TWENTY_YEARS_IN_SECONDS}`,
                'path=/',
                `domain=${domain}`,
                'secure',
                'samesite=none',
            ].join('; '),
        }],
    },
});

exports.handler = (event, context, callback) => {
    const request = event.Records[0].cf.request;

    if (request.method !== 'POST') {
        return callback(null, {
            status: '405',
            statusDescription: 'Method Not Allowed',
            headers: {
                'allow': [{
                    key: 'Allow',
                    value: 'POST',
                }],
            },
        });
    }

    const body = Buffer.from(request.body.data, request.body.encoding).toString();
    const domain = request.headers.host[0].value.split('.').slice(-2).join('.');

    try {
        const payload = JSON.parse(body);
        const value = payload[COOKIE];
        if (isUuidV4(value)) {
            return callback(null, createResponse(domain, value));
        }
    } catch (e) {
        console.error('ERROR', JSON.stringify(e, Object.getOwnPropertyNames(e)), JSON.stringify(event), JSON.stringify(context));
    }

    const cookieHeaders = request.headers.cookie || [];
    while (cookieHeaders.length > 0) {
        const cookies = cookieHeaders.shift().value.split(';').map(cookie => cookie.trim());
        while (cookies.length > 0) {
            const [key, value] = cookies.shift().split('=');
            if (key === COOKIE && isUuidV4(value)) {
                return callback(null, createResponse(domain, value));
            }
        }
    }

    return callback(null, createResponse(domain, crypto.randomUUID()));
}