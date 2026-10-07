/// Accept dimensions as a pair; partial metadata must not distort a video.
double mediaAspectRatio(int? width, int? height, {double fallback = 16 / 9}) =>
    width != null && height != null && width > 0 && height > 0
    ? width / height
    : fallback;
