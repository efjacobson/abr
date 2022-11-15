// v0.0.1

const serialize = (object) => JSON.stringify(object, null, 2);

exports.handler = (event, context) => {
    console.log('## ENVIRONMENT VARIABLES: ' + serialize(process.env));
    console.log('## CONTEXT: ' + serialize(context));
    console.log('## EVENT: ' + serialize(event));
}