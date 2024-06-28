const THROBBER_DOM_ID = 'throbber';

export default (() => document.getElementById(THROBBER_DOM_ID) || (() => {
    const throbber = document.createElement('div');
    throbber.id = THROBBER_DOM_ID;
    document.getElementsByTagName('body')[0].appendChild(throbber);
    return throbber;
})())();