const serialize = (object) => JSON.stringify(object, null, 2);

exports.handler = (event, context, callback) => {
    // console.log('## ENVIRONMENT VARIABLES: ' + serialize(process.env));
    // console.log('## CONTEXT: ' + serialize(context));
    // console.log('## EVENT: ' + serialize(event));
    console.log('v1');
    console.log('## serialize(event.Records[0].cf.request): ' + serialize(event.Records[0].cf.request));

    const request = event.Records[0].cf.request;

    callback(null, request);
}