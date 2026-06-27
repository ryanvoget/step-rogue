const AUDIO_SRC = 'assets/audio/11. Tractor Audit.wav';
const VOLUME_KEY = 'parsec_music_volume';
const DEFAULT_VOLUME = 0.5;

let audio = null;
let started = false;

export function initAudio() {
  if (audio) return;
  audio = new Audio(AUDIO_SRC);
  audio.loop = true;
  audio.volume = getSavedVolume();

  const tryPlay = () => {
    if (started) return;
    audio.play().then(() => { started = true; }).catch(() => {});
  };

  // Try immediately in case a prior user gesture already unlocked audio
  audio.play().then(() => { started = true; }).catch(() => {
    document.addEventListener('click', tryPlay, { once: true });
    document.addEventListener('keydown', tryPlay, { once: true });
    document.addEventListener('touchstart', tryPlay, { once: true });
  });
}

export function getVolume() {
  return getSavedVolume();
}

export function setVolume(value) {
  const vol = Math.max(0, Math.min(1, value));
  if (audio) audio.volume = vol;
  localStorage.setItem(VOLUME_KEY, String(vol));
}

function getSavedVolume() {
  const saved = localStorage.getItem(VOLUME_KEY);
  return saved !== null ? parseFloat(saved) : DEFAULT_VOLUME;
}
