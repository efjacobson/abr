the asset filenames were generated like so:

```
file='/path/to/file'
openssl dgst -sha256 -binary "${file}" | openssl enc -base64 | base64
```

(this is the s3 checksum base64 encoded an additional time)

---

images were optimized like so:

```
file='/path/to/file.ext'
optimized='/path/to/file.optimized.ext'
convert "${file}" -sampling-factor 4:2:0 -strip -quality 85 -interlace Plane -gaussian-blur 0.05 -colorspace RGB "${optimized}"
```