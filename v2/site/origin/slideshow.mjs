import shuffled from './shuffled.mjs';
import { toAbsolute, toOriginal, toQrCode } from './imageUtils.mjs';

let selfUrl;
function getParameter (name) {
  if (!selfUrl) {
    selfUrl = new URL(window.location);
  }
  return selfUrl.searchParams.get(name);
}

const FORWARD = 'forward';
const BACKWARD = 'backward';
const interval = Number(getParameter('interval') || 60000);
const animationDuration = getParameter('animationDuration') || '3000ms';
const animationDelay = getParameter('animationDelay') || '50ms';
const svgScale = Number(getParameter('svgScale') || 2);
const svgRight = getParameter('svgRight') || '50px';
const svgBottom = getParameter('svgBottom') || '50px';
const svgOpacity = Number(getParameter('svgOpacity') || 0.5);
const autoStartDelay = Number(getParameter('autoStartDelay') || 30000);
let direction = getParameter('direction') || FORWARD;

function doSetInterval () {
  clearInterval(intervalId);
  intervalId = setInterval(nextImage, interval);
}

function getNext (offset = 1) {
  let next;
  let nextNext;
  if (direction === FORWARD) {
    for (let i = 0; i < offset; i++) {
      next = shuffled.shift();
      shuffled.push(next);
    }
    nextNext = shuffled[0];
  } else {
    for (let i = 0; i < offset; i++) {
      next = shuffled.pop();
      shuffled.unshift(next);
    }
    nextNext = shuffled[shuffled.length - 1];
  }
  const eagerImage = document.createElement('img');
  eagerImage.className = 'eager-image';
  eagerImage.src = toAbsolute(toOriginal(nextNext));
  eagerImage.onload = () => eagerImage.remove();
  document.body.appendChild(eagerImage);
  return next;
}

function styleSlide (slide, image) {
  slide.style.backgroundImage = `url(${toAbsolute(toOriginal(image))})`;
  return slide;
}

function styleSvg (svg, image) {
  const base64QrCode = toQrCode(image);
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

let slideDiv;
function getSlideDiv () {
  if (slideDiv) {
    return slideDiv;
  }
  slideDiv = document.createElement('div');
  slideDiv.className = 'slide';
  // slideDiv.style.transition = `all ${animationDuration} linear ${animationDelay}`;

  ['', '-o-', '-ms-', '-moz-', '-webkit-'].forEach((prefix) => {
    slideDiv.style[`${prefix}transition`] = `all ${animationDuration} linear ${animationDelay}`;
  });
  const onSecondClick = () => {
    if (document.fullscreenElement) {
      document.exitFullscreen();
    } else {
      slideDiv.requestFullscreen();
    }
    slideDiv.addEventListener('pointerup', onFirstClick, { once: true });
  };
  const onFirstClick = () => {
    setTimeout(() => {
      slideDiv.removeEventListener('pointerup', onSecondClick);
      slideDiv.addEventListener('pointerup', onFirstClick, { once: true });
    }, 1000);
    slideDiv.addEventListener('pointerup', onSecondClick, { once: true });
  };
  slideDiv.addEventListener('pointerup', onFirstClick, { once: true });
  return getSlideDiv();
}

let isTransitioning = false;
getSlideDiv().addEventListener('transitionstart', () => {
  isTransitioning = true;
});
getSlideDiv().addEventListener('transitionend', () => {
  isTransitioning = false;
});

function nextImage (offset = 1) {
  if (isTransitioning) {
    return;
  }
  const next = getNext(offset);
  styleSlide(getSlideDiv(), next);
  styleSvg(getSvgDiv(), next);
}

function getClickArea (style, text, callback) {
  const clickArea = document.createElement('div');
  clickArea.className = 'click-area';

  const clickText = document.createElement('h3');
  clickText.className = 'click-area--text';
  clickText.textContent = text;
  clickArea.appendChild(clickText);

  Object.entries(style).forEach(([key, value]) => {
    clickArea.style[key] = value;
  });
  let clickAreaTimeoutId;
  clickArea.addEventListener('pointerenter', () => {
    clickArea.style.opacity = 1;
    clearTimeout(clickAreaTimeoutId);
    clickAreaTimeoutId = setTimeout(() => {
      clickArea.style.opacity = 0;
    }, 5000);
  });
  clickArea.addEventListener('pointerleave', () => {
    clearTimeout(clickAreaTimeoutId);
    clickArea.style.opacity = 0;
  });
  clickArea.addEventListener('pointerup', (e) => {
    if (Number(clickArea.style.opacity) !== 1) {
      clickArea.style.opacity = 1;
      clearTimeout(clickAreaTimeoutId);
      clickAreaTimeoutId = setTimeout(() => {
        clickArea.style.opacity = 0;
      }, 5000);
      return;
    }
    e.stopPropagation();
    if (isTransitioning) {
      return;
    }
    clearTimeout(clickAreaTimeoutId);
    clickArea.style.opacity = 0;
    callback();
  });
  return clickArea;
}

function directionClickCallback (intendedDirection) {
  const currentDirection = direction;
  direction = intendedDirection;
  nextImage(currentDirection !== direction ? 2 : 1);
  doSetInterval();
}

let leftClickArea;
function getLeftClickArea () {
  if (leftClickArea) {
    return leftClickArea;
  }
  leftClickArea = getClickArea(
    {
      left: '5%',
      width: '20%',
      height: '80%',
      bottom: '10%'
    },
    BACKWARD,
    () => directionClickCallback(BACKWARD)
  );
  return getLeftClickArea();
}

let rightClickArea;
function getRightClickArea () {
  if (rightClickArea) {
    return rightClickArea;
  }
  rightClickArea = getClickArea(
    {
      right: '5%',
      width: '20%',
      height: '80%',
      bottom: '10%'
    },
    FORWARD,
    () => directionClickCallback(FORWARD)
  );
  return getRightClickArea();
}

let bottomClickArea;
function getBottomClickArea () {
  if (bottomClickArea) {
    return bottomClickArea;
  }
  bottomClickArea = getClickArea(
    {
      width: '90%',
      height: '10%',
      padding: '5%',
      bottom: '2%'
    },
    'pause',
    () => clearInterval(intervalId)
  );
  return getBottomClickArea();
}

let svgDiv;
function getSvgDiv () {
  if (svgDiv) {
    return svgDiv;
  }
  svgDiv = document.createElement('div');
  svgDiv.className = 'qrcode';
  svgDiv.style.transition = `all ${animationDuration} linear ${animationDelay}`;
  svgDiv.style.right = svgRight;
  svgDiv.style.bottom = svgBottom;
  svgDiv.style.opacity = svgOpacity;
  return getSvgDiv();
}

const info = document.createElement('div');
info.className = 'info';

const parametersTable = document.createElement('table');
const parameters = [
  ['animationDuration', animationDuration, 'how long it takes for one image to transition to the next'],
  ['interval', interval, 'how long (milliseconds) to wait before transitioning to the next image'],
  ['animationDelay', animationDelay, 'how long to wait before starting the transition (ensures smooth animation, mostly)'],
  ['svgScale', svgScale, 'scale modifier for the QR code'],
  ['svgRight', svgRight, 'how far from the right edge of the screen to place the QR code'],
  ['svgBottom', svgBottom, 'how far from the bottom edge of the screen to place the QR code'],
  ['svgOpacity', svgOpacity, 'how transparent the QR code should be'],
  ['autoStartDelay', autoStartDelay, 'how long to wait before automatically starting the slideshow'],
  ['direction', direction, 'initial direction of the slideshow']
];

const forceConfigUrl = new URL(`${window.location.origin}${window.location.pathname}`);
parameters.forEach(([name, value, description]) => {
  forceConfigUrl.searchParams.set(name, value);
  const tr = document.createElement('tr');
  const tdName = document.createElement('td');
  tdName.textContent = name;
  tr.appendChild(tdName);
  const tdValue = document.createElement('td');
  tdValue.textContent = value;
  tr.appendChild(tdValue);
  const tdDescription = document.createElement('td');
  tdDescription.textContent = description;
  tr.appendChild(tdDescription);
  parametersTable.appendChild(tr);
});
info.appendChild(parametersTable);

const forceConfigUrlText = document.createElement('p');
forceConfigUrlText.innerHTML = 'force current config with this URL: <a href="' + forceConfigUrl + '">' + forceConfigUrl + '</a>';
info.appendChild(forceConfigUrlText);

const instructionsText = document.createElement('p');
instructionsText.textContent = 'instructions';
info.appendChild(instructionsText);

const ul = document.createElement('ul');
const lis = [
  'customize any of the above values by including them as query parameters in the URL (like the example above)',
  'press the button to start',
  'enter key to enter fullscreen',
  'escape key to exit fullscreen',
  'spacebar to pause',
  'arrow left to go to previous image and set direction to backward',
  'arrow right to go to next image and set direction to forward',
  'double click to toggle fullscreen'
];
lis.forEach((li) => {
  const liElement = document.createElement('li');
  liElement.textContent = li;
  ul.appendChild(liElement);
});
info.appendChild(ul);

const now = Date.now();
const autoStart = now + autoStartDelay;
const autoStartText = document.createElement('p');
autoStartText.textContent = `auto start in ${Math.ceil((autoStart - now) / 1000)} seconds (autostarted slideshow will not be fullscreen)`;
const autoStartIntervalId = setInterval(() => {
  const remaining = autoStart - Date.now();
  if (remaining <= 0) {
    clearInterval(autoStartIntervalId);
    button.dispatchEvent(new window.PointerEvent('pointerup'));
    return;
  }
  autoStartText.textContent = `auto start in ${Math.ceil(remaining / 1000)} seconds (autostarted slideshow will not be fullscreen)`;
}, 1000);

function hideCursor () {
  document.body.style.cursor = 'none';
  document.body.addEventListener('mousemove', () => {
    document.body.style.cursor = 'unset';
    setTimeout(hideCursor, 10000);
  }, { once: true });
}

let intervalId;
const button = document.createElement('button');
button.innerText = 'Start';

function keyDownCallback (e) {
  if (e.code !== 'Enter') {
    return;
  }
  button.dispatchEvent(new window.PointerEvent('pointerup'));
  button.removeEventListener('keydown', keyDownCallback);
}
button.addEventListener('keydown', keyDownCallback);

button.addEventListener('pointerup', () => {
  button.removeEventListener('keydown', keyDownCallback);
  info.remove();
  clearInterval(autoStartIntervalId);
  const next = getNext();
  const slide = styleSlide(getSlideDiv(), next);
  const svg = styleSvg(getSvgDiv(), next);
  slide.appendChild(getLeftClickArea());
  slide.appendChild(getRightClickArea());
  slide.appendChild(getBottomClickArea());
  slide.appendChild(svg);
  document.body.appendChild(slide);
  slide.requestFullscreen().finally(() => {
    hideCursor();
    document.addEventListener(
      'keydown',
      (e) => {
        if (e.code === 'Space') {
          clearInterval(intervalId);
          return;
        }
        if (e.code === 'Enter') {
          getSlideDiv().requestFullscreen();
          return;
        }
        if (!/^Arrow(?:Left|Right)$/.test(e.code)) {
          return;
        }
        doSetInterval();
        const currentDirection = direction;
        direction = e.key === 'ArrowLeft' ? BACKWARD : FORWARD;
        nextImage(currentDirection !== direction ? 2 : 1);
      }
    );
    doSetInterval();
  });
}, { once: true });
info.appendChild(button);
info.appendChild(autoStartText);

document.body.appendChild(info);
