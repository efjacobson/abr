import shuffled from './shuffled.mjs';
import { toAbsolute, toHash, toOptimized, toOriginal } from './imageUtils.mjs';

// todo: reimplement light dom rendering

const renders = new Map();
function render (src = shuffled.pop()) {
  if (!src) {
    performanceObserver.disconnect();
    intersectionObserver.disconnect();
    const fin = document.createElement('h2');
    fin.textContent = 'fin';
    throbber.parentNode.insertBefore(fin, throbber);
    throbber.parentNode.removeChild(throbber);
    return;
  }

  const hash = toHash(src);
  if (renders.has(hash)) {
    return;
  }
  renders.set(hash, () => {
    intersectionObserver.observe(throbber);
    renders.delete(hash);
  });

  const div = document.createElement('div');
  div.className = 'card';

  const img = document.createElement('img');
  img.loading = 'lazy';
  img.src = toAbsolute(toOptimized(src));
  div.appendChild(img);

  const anchor = document.createElement('a');
  anchor.href = toAbsolute(toOriginal(src));
  anchor.target = '_blank';
  anchor.textContent = 'Open high(er) resolution image in new tab';
  div.appendChild(anchor);

  throbber.parentNode.insertBefore(div, throbber);
}

const intersectionObserver = new window.IntersectionObserver((entries) => {
  if (!entries[0].isIntersecting) {
    return;
  }
  intersectionObserver.unobserve(throbber);
  render();
});

const performanceObserver = new PerformanceObserver((list) => {
  list.getEntries().forEach((entry) => {
    const hash = toHash(entry.name);
    if (!renders.has(hash)) {
      return;
    }
    renders.get(hash)();
  });
});
performanceObserver.observe({ type: 'resource', buffered: true });

let throbber;
import('./throbber.mjs').then((module) => {
  throbber = module.default;
  intersectionObserver.observe(throbber);
});
