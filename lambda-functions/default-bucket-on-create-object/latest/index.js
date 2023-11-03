const serialize = (object) => JSON.stringify(object, null, 2);
const regex = /$^/;

exports.handler = (event, context) => {
    console.log('process.env', serialize(process.env));
    console.log('event', serialize(event));
    console.log('context', serialize(context));

    (event?.Records || []).forEach(record => {
        const key = record?.s3?.object?.key;
        if ('string' !== typeof key) {
            return;
        }
        const match = key.match(regex);
        if (null === match) {
            return;
        }
        console.log(`\${match[1]}/o/\${match[3]}: ${match[1]}/o/${match[3]}`);
    });
}