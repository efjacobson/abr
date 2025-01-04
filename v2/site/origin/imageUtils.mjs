import getOrigin from './getOrigin.mjs';
import qrcodes from './qrcodes.mjs';

const extensionRegex = /(\.[^.]+)$/;

const originRegex = RegExp(`^${getOrigin()}`);
const isAbsolute = (src) => originRegex.test(src);
const isOptimized = (src) => /\.optimized$/.test(src.replace(extensionRegex, ''));
const isThumbnail = (src) => /\.thumbnail$/.test(src.replace(extensionRegex, ''));

export const toHash = (src) => src.split('/').pop().split('.').shift();

export const toAbsolute = (src) => {
  if (isAbsolute(src)) {
    return src;
  }
  return `${getOrigin()}/${src}`;
};

export const toRelative = (src) => {
  if (!isAbsolute(src)) {
    return src;
  }
  return src.replace(originRegex, '');
};

export const toOptimized = (src) => {
  if (isOptimized(src)) {
    return src;
  }
  const extension = extensionRegex.exec(src)[1];
  return src.replace(extensionRegex, `.optimized${extension}`);
};

export const toThumbnail = (src) => {
  if (isThumbnail(src)) {
    return src;
  }
  const extension = extensionRegex.exec(src)[1];
  return src.replace(extensionRegex, `.thumbnail${extension}`);
};

export const toOriginal = (src) => {
  if (!isOptimized(src) && !isThumbnail(src)) {
    return src;
  }
  const extension = extensionRegex.exec(src)[1];
  const withoutExtension = src.replace(extensionRegex, '');
  return `${withoutExtension.replace(/\.(?:optimized|thumbnail)$/, '')}${extension}`;
};

export const toQrCode = (src) => qrcodes[toOriginal(toRelative(src))];
