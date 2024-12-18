import shuffled from './shuffled.mjs';
import qrcodes from './qrcodes.json' with { type: 'json' };
import { toAbsolute, toOriginal } from './imageUtils.mjs';

let selfUrl
function getParameter(name) {
    if (!selfUrl) {
        selfUrl = new URL(window.location);
    }
    return selfUrl.searchParams.get(name);
}

const interval = getParameter('interval') || 60000;
const animationDuration = getParameter('animationDuration') || '3000ms';
const animationDelay = getParameter('animationDelay') || '50ms';
const svgScale = getParameter('svgScale') || 2;
const svgRight = getParameter('svgRight') || '50px';
const svgBottom = getParameter('svgBottom') || '50px';
const svgOpacity = getParameter('svgOpacity') || 0.5;
let direction = getParameter('direction') || 'forward';

function getNext() {
    const next = shuffled[direction === 'forward' ? 'shift' : 'pop']();
    shuffled[direction === 'forward' ? 'push' : 'unshift'](next);
    return next;
}

function styleSlide(slide, image) {
    slide.style.backgroundImage = `url(${toOriginal(image)})`;
    return slide;
}

function styleSvg(svg, image) {
    const base64QrCode = qrcodes[toAbsolute(toOriginal(image))];
    const decoded = atob(base64QrCode);
    const widthMatch = decoded.match(/width="(\d+)"/);
    const scaledWidth = widthMatch[1] * svgScale;
    const withScaledWidth = decoded.replace(widthMatch[0], `width="${scaledWidth}"`);
    const heightMatch = decoded.match(/height="(\d+)"/);
    const scaledHeight = heightMatch[1] * svgScale;
    const withScaledHeight = withScaledWidth.replace(heightMatch[0], `height="${scaledHeight}"`);
    const withoutHexColor = withScaledHeight.replaceAll('#000', 'black');
    const withPathTransform = withoutHexColor.replace('<path', `<path style="transform: scale(${svgScale});"`);
    const withoutNewLines = withPathTransform.replaceAll('\n', '');
    const withUrl = `url('data:image/svg+xml;utf8,${withoutNewLines}')`;
    svg.style.backgroundImage = withUrl;
    svg.style.width = `${scaledWidth}px`;
    svg.style.height = `${scaledHeight}px`;
    return svg;
}

function nextImage() {
    const next = getNext();
    styleSlide(getSlideDiv(), next);
    styleSvg(getSvgDiv(), next);
}

let slideDiv;
function getSlideDiv() {
    if (slideDiv) {
        return slideDiv;
    }
    slideDiv = document.createElement('div');
    slideDiv.className = 'slide';
    slideDiv.style.transition = `all ${animationDuration} linear ${animationDelay}`;
    const onSecondClick = () => {
        if (document.fullscreenElement) {
            document.exitFullscreen();
        } else {
            slideDiv.requestFullscreen();
        }
        slideDiv.addEventListener('click', onFirstClick, { once: true });
    };
    const onFirstClick = () => {
        setTimeout(() => {
            slideDiv.removeEventListener('click', onSecondClick);
            slideDiv.addEventListener('click', onFirstClick, { once: true });
        }, 1000);
        slideDiv.addEventListener('click', onSecondClick, { once: true });
    };
    slideDiv.addEventListener('click', onFirstClick, { once: true });
    return getSlideDiv();
}

let svgDiv;
function getSvgDiv() {
    if (svgDiv) {
        return svgDiv;
    }
    svgDiv = document.createElement('div');
    svgDiv.style.transition = `all ${animationDuration} linear ${animationDelay}`;
    svgDiv.style.backgroundSize = 'contain';
    svgDiv.style.backgroundColor = 'white';
    svgDiv.style.position = 'fixed';
    svgDiv.style.right = svgRight;
    svgDiv.style.bottom = svgBottom;
    svgDiv.style.opacity = svgOpacity;
    return getSvgDiv();
}

const info = document.createElement('div');
info.style.margin = '10px';

const parametersTable = document.createElement('table');
const parameters = [
    ['animationDuration', animationDuration],
    ['interval', interval],
    ['animationDelay', animationDelay],
    ['svgScale', svgScale],
    ['svgRight', svgRight],
    ['svgBottom', svgBottom],
    ['svgOpacity', svgOpacity],
    ['direction', direction],
];

const forceConfigUrl = new URL(`${window.location.origin}${window.location.pathname}`);
parameters.forEach(([name, value]) => {
    forceConfigUrl.searchParams.set(name, value);
    const tr = document.createElement('tr');
    const tdName = document.createElement('td');
    tdName.textContent = name;
    tr.appendChild(tdName);
    const tdValue = document.createElement('td');
    tdValue.textContent = value;
    tr.appendChild(tdValue);
    parametersTable.appendChild(tr);
});
info.appendChild(parametersTable);

const forceConfigUrlText = document.createElement('p');
forceConfigUrlText.innerHTML = 'force current config with this URL: <a href="' + forceConfigUrl + '">' + forceConfigUrl + '</a>';
info.appendChild(forceConfigUrlText);

const instructionsText = document.createElement('p');
instructionsText.textContent = `instructions`;
info.appendChild(instructionsText);

const ul = document.createElement('ul');
const lis = [
    'press the button to start',
    'double click the image to toggle fullscreen',
    'space to pause',
    'left to go to previous image and set direction to backwards',
    'right to go to next image and set direction to forwards',
    'customize any of the above parameters by including them as query parameters in the URL',
];
lis.forEach((li) => {
    const liElement = document.createElement('li');
    liElement.textContent = li;
    ul.appendChild(liElement);
});
info.appendChild(ul);

const autoStartDelay = 120000;
const now = Date.now();
const autoStart = now + autoStartDelay;
const autoStartText = document.createElement('p');
autoStartText.textContent = `auto start in ${Math.ceil((autoStart - now) / 1000)} seconds`;
const autoStartIntervalId = setInterval(() => {
    const remaining = autoStart - Date.now();
    if (remaining <= 0) {
        clearInterval(autoStartIntervalId);
        button.click();
        return;
    }
    autoStartText.textContent = `auto start in ${Math.ceil(remaining / 1000)} seconds`;
}, 1000);

let intervalId;
const button = document.createElement('button');
button.innerText = 'Start';
button.addEventListener('click', () => {
    info.remove();
    clearInterval(autoStartIntervalId);
    const next = getNext();
    const slide = styleSlide(getSlideDiv(), next);
    const svg = styleSvg(getSvgDiv(), next);
    slide.appendChild(svg);
    document.body.appendChild(slide);
    intervalId = setInterval(nextImage, interval);
    slide.requestFullscreen();
    document.addEventListener(
        'keydown',
        (e) => {
            if (e.code === 'Space') {
                clearInterval(intervalId);
                return;
            }
            if (!/^Arrow(?:Left|Right)$/.test(e.code)) {
                return;
            }
            clearInterval(intervalId);
            const currentDirection = direction;
            direction = e.key === 'ArrowLeft' ? 'backward' : 'forward';
            if (currentDirection !== direction) {
                nextImage();
            }
            nextImage();
            intervalId = setInterval(nextImage, interval);
        },
    );
}, { once: true });
info.appendChild(button);
info.appendChild(autoStartText);

document.body.appendChild(info);