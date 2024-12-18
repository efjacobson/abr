import getOrigin from './getOrigin.mjs';

const originRegex = RegExp(`^${getOrigin()}`);
const isAbsolute = (src) => originRegex.test(src);
const isOptimized = (src) => /\.optimized\.jpg$/.test(src);

export const toAbsolute = (src) => {
    if (isAbsolute(src)) {
        return src;
    }
    return `${getOrigin()}/${src}`;
}

export const toOptimized = (src) => {
    if (isOptimized(src)) {
        return src;
    }
    return src.replace(/\.jpg$/, '.optimized.jpg');
}

export const toOriginal = (src) => {
    if (!isOptimized(src)) {
        return src;
    }
    return src.replace(/\.optimized\.jpg$/, '.jpg');
}