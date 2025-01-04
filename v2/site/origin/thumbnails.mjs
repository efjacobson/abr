import shuffled from './shuffled.mjs';
import { toAbsolute, toOriginal, toThumbnail } from './imageUtils.mjs';

while (shuffled.length > 0) {
  ((a, div, url) => {
    div.className = 'image';
    div.style.backgroundImage = `url(${toAbsolute(toThumbnail(url))})`;
    a.target = '_blank';
    a.href = toAbsolute(toOriginal(url));
    a.appendChild(div);
    document.body.appendChild(a);
  })(document.createElement('a'), document.createElement('div'), shuffled.pop());
}
