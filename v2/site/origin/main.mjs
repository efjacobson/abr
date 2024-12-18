import shuffled from './shuffled.mjs';
import { toOriginal } from './imageUtils.mjs';

// todo: reimplement light dom rendering

const renders = new Map();
function render(next = shuffled.pop()) {
    if (!next) {
        performanceObserver.disconnect();
        intersectionObserver.disconnect();
        const fin = document.createElement('h2');
        fin.textContent = 'fin';
        throbber.parentNode.insertBefore(fin, throbber);
        throbber.parentNode.removeChild(throbber);
        return;
    }

    const src = `./${next}`;
    if (renders.has(src)) {
        return;
    }
    renders.set(src, () => {
        intersectionObserver.observe(throbber);
        renders.delete(src);
    });

    const div = document.createElement('div');
    div.className = 'card';

    const img = document.createElement('img');
    img.loading = 'lazy';
    img.src = src;
    div.appendChild(img);

    const anchor = document.createElement('a');
    anchor.href = toOriginal(src);
    anchor.target = '_blank';
    anchor.textContent = 'Open high(er) resolution image in new tab';
    div.appendChild(anchor);

    throbber.parentNode.insertBefore(div, throbber);
}

const intersectionObserver = new IntersectionObserver((entries) => {
    if (!entries[0].isIntersecting) {
        return;
    }
    intersectionObserver.unobserve(throbber);
    render();
});

const performanceObserver = new PerformanceObserver((list) => {
    list.getEntries().forEach((entry) => {
        const src = `.${new URL(entry.name).pathname}`;
        if (!renders.has(src)) {
            return;
        }
        renders.get(src)();
    });
});
performanceObserver.observe({ type: "resource", buffered: true })

import('./throbber.mjs').then(({ default: throbber }) => {
    intersectionObserver.observe(throbber);
});