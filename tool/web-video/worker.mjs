import {Input, Output, BlobSource, BufferSource, StreamTarget, Mp4OutputFormat,
  MP4, QTFF, WEBM, Conversion, Quality, canEncodeVideo} from 'mediabunny';

const MiB = 1048576;
class ExportError extends Error {}
const fail = (message) => { throw new ExportError(message); };

// Bound encoded output while it is written, not only after allocation.
function boundedTarget(maximum) {
  let bytes = new Uint8Array(Math.min(MiB, maximum)), length = 0;
  const target = new StreamTarget(new WritableStream({write({data, position}) {
    const end = position + data.length;
    if (!Number.isSafeInteger(end) || position < 0 || end > maximum) fail('The result exceeds the selected size limit.');
    if (end > bytes.length) {
      const grown = new Uint8Array(Math.min(maximum, Math.max(end, bytes.length * 2)));
      grown.set(bytes); bytes = grown;
    }
    bytes.set(data, position); length = Math.max(length, end);
  }}));
  return {target, finish: () => bytes.slice(0, length)};
}

export function editPlan(options, sourceWidth, sourceHeight, duration) {
  const edit = options.edit || {}, turns = edit.turns ?? 0;
  const start = (edit.startMs ?? 0) / 1000, end = edit.endMs == null ? duration : edit.endMs / 1000;
  const left = edit.left ?? 0, top = edit.top ?? 0, width = edit.width ?? 1, height = edit.height ?? 1;
  if (![sourceWidth, sourceHeight, duration, start, end, left, top, width, height].every(Number.isFinite) ||
      !Number.isInteger(turns) || turns < 0 || turns > 3 || sourceWidth <= 0 || sourceHeight <= 0 ||
      sourceWidth * sourceHeight > 3840 * 2160 || duration <= 0 || duration > 3600 || start < 0 || end > duration + .05 || end <= start ||
      left < 0 || top < 0 || width <= 0 || height <= 0 || left + width > 1.000001 || top + height > 1.000001) fail('Can\'t export: the video or edit is too large or invalid.');
  const rotatedWidth = turns % 2 ? sourceHeight : sourceWidth, rotatedHeight = turns % 2 ? sourceWidth : sourceHeight;
  const crop = {left: left * rotatedWidth, top: top * rotatedHeight, width: width * rotatedWidth, height: height * rotatedHeight};
  const small = options.preset === 'smaller', edge = small ? 1280 : 1920;
  const scale = options.optimize === false ? 1 : Math.min(1, edge / Math.max(crop.width, crop.height));
  const outputWidth = Math.max(2, Math.floor(crop.width * scale / 2) * 2), outputHeight = Math.max(2, Math.floor(crop.height * scale / 2) * 2);
  const maximum = options.optimize === false ? 128 * MiB : (small ? 12 : 24) * MiB;
  const budget = Math.floor(((small ? 10 : 20) * MiB * 8) / (end - start) - 192000);
  if (options.optimize !== false && budget < 250000) fail('Too long for this size limit. Trim the video or choose Original.');
  return {start, end, crop, turns, width: outputWidth, height: outputHeight, maximum,
    bitrate: options.optimize === false ? 8000000 : Math.min(small ? 1500000 : 4000000, budget)};
}

export async function convertVideo(blob, options, report = () => {}) {
  if (!(blob instanceof Blob) || !blob.size || blob.size > 256 * MiB) fail('Over 256 MiB. Choose Original or use the native app.');
  let input, conversion, remuxInput, remux;
  try {
    input = new Input({source: new BlobSource(blob), formats: [MP4, QTFF, WEBM]});
    const track = await input.getPrimaryVideoTrack();
    if (!track) fail('No supported video track was found.');
    if ((await track.getCodedWidth()) * (await track.getCodedHeight()) > 3840 * 2160) fail('Resolution too high for browser editing. Choose Original.');
    const plan = editPlan(options, await track.getDisplayWidth(), await track.getDisplayHeight(), await input.computeDuration());
    if (!await canEncodeVideo('avc', {width: plan.width, height: plan.height, bitrate: plan.bitrate})) fail('This browser can\'t encode the video. Choose Original.');
    const encoded = boundedTarget(plan.maximum);
    const output = new Output({format: new Mp4OutputFormat({fastStart: false}), target: encoded.target});
    conversion = await Conversion.init({input, output, tracks: 'primary',
      ...(plan.start > 0 || options.edit?.endMs != null ? {trim: {start: plan.start, end: plan.end}} : {}),
      video: {codec: 'avc', width: plan.width, height: plan.height, fit: 'fill', rotate: plan.turns * 90,
        crop: plan.crop, allowTransformationMetadata: false, frameRate: 30, quality: new Quality({bitrate: plan.bitrate}),
        keyFrameInterval: 2, forceTranscode: true},
      audio: options.edit?.muted ? {discard: true} : {codec: 'aac'},
    });
    if (!conversion.isValid || conversion.discardedTracks.some(t => t.reason !== 'discarded_by_user')) fail('A video or audio track cannot be preserved by this browser. Choose Original.');
    conversion.onProgress = value => report(Math.min(.9, value * .9));
    await conversion.execute();
    // Remux the already size-bounded result to ordinary fast-start MP4.
    // Audio is copied when compatible, never silently dropped.
    const bytes = encoded.finish();
    remuxInput = new Input({source: new BufferSource(bytes), formats: [MP4]});
    const final = boundedTarget(plan.maximum);
    remux = await Conversion.init({input: remuxInput,
      output: new Output({format: new Mp4OutputFormat({fastStart: 'in-memory'}), target: final.target}), tracks: 'primary'});
    if (!remux.isValid || remux.discardedTracks.length) fail('Could not preserve the exported tracks.');
    await remux.execute();
    report(1);
    return {bytes: final.finish(), width: plan.width, height: plan.height, duration: Math.round((plan.end - plan.start) * 1000)};
  } finally {
    await conversion?.cancel().catch(() => {});
    await remux?.cancel().catch(() => {});
    input?.dispose(); remuxInput?.dispose();
  }
}

if (typeof WorkerGlobalScope !== 'undefined' && self instanceof WorkerGlobalScope) {
  self.onmessage = async ({data}) => {
    try {
      const result = await convertVideo(data.blob, data.options, progress => self.postMessage({progress}));
      self.postMessage({result}, [result.bytes.buffer]);
    } catch (error) {
      // No media bytes, filenames, credentials or raw codec diagnostics leave the worker.
      const known = error instanceof ExportError;
      self.postMessage({error: known ? error.message : 'Browser video export failed. Retry or choose Original.'});
    }
  };
}
