// ============================================================
// STATE
// ============================================================
const NOTE_NAMES = ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'];

// Convert Hz to MIDI note number (69 = A4 = 440Hz)
function hzToMidi(hz) { return 12 * Math.log2(hz / 440) + 69; }
function midiToNote(midi) { return NOTE_NAMES[Math.round(midi) % 12]; }
function midiToOctave(midi) { return Math.floor(Math.round(midi) / 12) - 1; }

// Pitch history ring buffer (stores MIDI note numbers, null = no pitch)
const PITCH_HISTORY_LEN = 80;
const pitchHistory = new Array(PITCH_HISTORY_LEN).fill(null);

// Fixed pitch ribbon range — covers practical detection range (E1 to C7)
const RIBBON_MIN_MIDI = 28;  // E1
const RIBBON_MAX_MIDI = 96;  // C7
const RIBBON_RANGE = RIBBON_MAX_MIDI - RIBBON_MIN_MIDI;

// Raw OSC values for modal display (address → args array)
const oscRaw = {};

const state = {
  amp: 0, pitch: 0, hasFreq: 0, loud: 0,
  centroid: 0, flatness: 0, bpm: 0,
  key: 0, mode: 1,
  chroma: new Float32Array(12),
};

// Smoothed values for display
const smooth = { amp: 0, loud: 0, centroid: 0, flatness: 0 };
const SMOOTH = 0.3; // lower = smoother

// ============================================================
// WEBSOCKET
// ============================================================
let ws = null;
let reconnectTimer = null;

function connect() {
  clearTimeout(reconnectTimer);
  const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
  ws = new WebSocket(`${proto}//${location.host}/ws/osc`);

  ws.onopen = () => {
    document.getElementById('connStatus').textContent = 'live';
    document.getElementById('connStatus').className = 'conn-status connected';
  };

  ws.onclose = () => {
    document.getElementById('connStatus').textContent = 'disconnected — reconnecting...';
    document.getElementById('connStatus').className = 'conn-status error';
    reconnectTimer = setTimeout(connect, 2000);
  };

  ws.onerror = () => ws.close();

  ws.onmessage = (evt) => {
    try {
      const msg = JSON.parse(evt.data);
      handleOSC(msg.address, msg.args);
    } catch(e) { console.warn('WS parse error:', e); }
  };
}

function handleOSC(addr, args) {
  oscRaw[addr] = args;
  // Flash trigger value in modal if open
  if (TRIGGER_ADDRS.has(addr)) {
    const el = document.getElementById('osc-val-' + addr.replace(/\//g, '_'));
    if (el) { el.classList.add('flash'); setTimeout(() => el.classList.remove('flash'), 200); }
  }
  switch(addr) {
    case '/audio/amplitude':
      state.amp = args[0];
      break;
    case '/audio/pitch':
      state.pitch = args[0];
      state.hasFreq = args[1];
      // Record to history if confident (round to nearest semitone to prevent jitter)
      if (args[1] > 0.5 && args[0] > 20) {
        pitchHistory.push(Math.round(hzToMidi(args[0])));
      } else {
        pitchHistory.push(null);
      }
      if (pitchHistory.length > PITCH_HISTORY_LEN) pitchHistory.shift();
      break;
    case '/audio/loudness':
      state.loud = args[0];
      break;
    case '/audio/spectral/centroid':
      state.centroid = args[0];
      break;
    case '/audio/spectral/flatness':
      state.flatness = args[0];
      break;
    case '/audio/onset/kick':
    case '/audio/onset/snare':
    case '/audio/onset/hihat':
    case '/audio/onset/perc':
    case '/audio/onset/bass':
    case '/audio/onset/melody':
    case '/audio/onset/bright':
    case '/audio/onset/any':
    case '/audio/onset/drop':
    case '/audio/onset/soft':
      flashOnsetPip(addr.split('/').pop());
      break;
    case '/audio/beat':
      flashBeat();
      break;
    case '/audio/bpm':
      state.bpm = args[0];
      break;
    case '/audio/key':
      state.key = args[0];
      state.mode = args[1];
      break;
    case '/audio/chroma':
      for (let i = 0; i < Math.min(args.length, 12); i++) state.chroma[i] = args[i];
      break;
  }
}

// ============================================================
// FLASH EFFECTS
// ============================================================
let beatTimeout = null;
function flashBeat() {
  const el = document.getElementById('beatCard');
  el.classList.add('flash');
  clearTimeout(beatTimeout);
  beatTimeout = setTimeout(() => el.classList.remove('flash'), 150);
}

const onsetTimeouts = {};
function flashOnsetPip(channel) {
  const el = document.getElementById('onset-' + channel);
  if (!el) return;
  el.classList.add('lit');
  clearTimeout(onsetTimeouts[channel]);
  onsetTimeouts[channel] = setTimeout(() => el.classList.remove('lit'), 200);
}

// ============================================================
// OSC DETAIL MODAL
// ============================================================
let modalAddresses = [];
let modalUpdateInterval = null;

// Trigger addresses flash briefly in the modal
const TRIGGER_ADDRS = new Set([
  '/audio/beat', '/audio/onset/kick', '/audio/onset/snare', '/audio/onset/hihat',
  '/audio/onset/perc', '/audio/onset/bass', '/audio/onset/melody', '/audio/onset/bright',
  '/audio/onset/any', '/audio/onset/drop', '/audio/onset/soft'
]);

function openOscModal(title, addresses) {
  modalAddresses = addresses;
  document.getElementById('oscModalTitle').textContent = title + ' — OSC';
  const body = document.getElementById('oscModalBody');
  body.innerHTML = addresses.map(addr => {
    const isTrigger = TRIGGER_ADDRS.has(addr);
    return `<div class="osc-row">
      <span class="osc-addr">${addr}</span>
      <span class="osc-val${isTrigger ? ' trigger' : ''}" id="osc-val-${addr.replace(/\//g, '_')}">${isTrigger ? 'trigger' : '---'}</span>
    </div>`;
  }).join('');
  document.getElementById('oscModal').classList.add('open');

  // Update values at 15fps
  clearInterval(modalUpdateInterval);
  modalUpdateInterval = setInterval(updateModalValues, 66);
}

function closeOscModal(event) {
  if (event && event.target !== event.currentTarget) return;
  document.getElementById('oscModal').classList.remove('open');
  clearInterval(modalUpdateInterval);
  modalAddresses = [];
}

function updateModalValues() {
  for (const addr of modalAddresses) {
    if (TRIGGER_ADDRS.has(addr)) continue; // triggers flash via handleOSC
    const el = document.getElementById('osc-val-' + addr.replace(/\//g, '_'));
    if (!el) continue;
    const args = oscRaw[addr];
    if (args) {
      el.textContent = args.map(v => typeof v === 'number' ? v.toFixed(2) : v).join(', ');
    }
  }
}

// Attach click handlers to all cards with data-osc
document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('.card[data-osc]').forEach(card => {
    card.addEventListener('click', () => {
      const label = card.querySelector('.card-label')?.textContent || 'OSC';
      const addrs = card.dataset.osc.split(',');
      openOscModal(label, addrs);
    });
  });
});

// Close on Escape
document.addEventListener('keydown', e => {
  if (e.key === 'Escape') closeOscModal();
});

// ============================================================
// RENDER LOOP
// ============================================================
function lerp(a, b, t) { return a + (b - a) * t; }

function updateDOM() {
  // Smooth values
  smooth.amp = lerp(smooth.amp, state.amp, SMOOTH);
  smooth.loud = lerp(smooth.loud, state.loud, SMOOTH);
  smooth.centroid = lerp(smooth.centroid, state.centroid, SMOOTH);
  smooth.flatness = lerp(smooth.flatness, state.flatness, SMOOTH);

  // Amplitude
  document.getElementById('ampVal').textContent = smooth.amp.toFixed(2);
  document.getElementById('ampBar').style.width = (smooth.amp * 100) + '%';

  // Pitch
  if (state.hasFreq > 0.5 && state.pitch > 20) {
    const midi = hzToMidi(state.pitch);
    document.getElementById('pitchNote').textContent = midiToNote(midi);
    document.getElementById('pitchOctave').textContent = midiToOctave(midi);
    document.getElementById('pitchHz').textContent = Math.round(state.pitch) + ' Hz';
  } else {
    document.getElementById('pitchNote').textContent = '--';
    document.getElementById('pitchOctave').textContent = '';
    document.getElementById('pitchHz').textContent = '';
  }

  // Loudness
  document.getElementById('loudVal').textContent = smooth.loud.toFixed(1);
  document.getElementById('loudBar').style.width = Math.min(smooth.loud / 64 * 100, 100) + '%';

  // Centroid (brightness) — sliding marker on gradient
  const centPct = Math.min(Math.max((smooth.centroid - 200) / 7800, 0), 1) * 100;
  document.getElementById('brightMarker').style.left = centPct + '%';
  // Descriptive label based on centroid range
  let brightText;
  if (smooth.centroid < 800) brightText = 'dark';
  else if (smooth.centroid < 1500) brightText = 'warm';
  else if (smooth.centroid < 3000) brightText = 'neutral';
  else if (smooth.centroid < 5500) brightText = 'bright';
  else brightText = 'brilliant';
  document.getElementById('brightLabel').textContent = brightText;

  // Flatness (noisiness)
  document.getElementById('flatVal').textContent = smooth.flatness.toFixed(2);
  document.getElementById('flatBar').style.width = (smooth.flatness * 100) + '%';

  // BPM
  document.getElementById('bpmVal').textContent = state.bpm > 0 ? Math.round(state.bpm) : '---';

  // Key
  document.getElementById('keyNote').textContent = NOTE_NAMES[state.key] || '--';
  const modeEl = document.getElementById('keyMode');
  modeEl.textContent = state.mode === 1 ? 'major' : 'minor';
  modeEl.className = 'key-mode ' + (state.mode === 1 ? 'major' : 'minor');

}

// ============================================================
// CANVAS RENDERERS
// ============================================================
// Cache canvas contexts and size them once (+ on resize)
const canvases = {};

function sizeCanvases() {
  const dpr = window.devicePixelRatio || 1;

  // Pitch ribbon: sized to fill its parent card
  const pitchCanvas = document.getElementById('pitchRibbon');
  if (pitchCanvas) {
    const parent = pitchCanvas.parentElement;
    const pw = parent.offsetWidth;
    const ph = parent.offsetHeight;
    pitchCanvas.width = pw * dpr;
    pitchCanvas.height = ph * dpr;
    pitchCanvas.style.width = pw + 'px';
    pitchCanvas.style.height = ph + 'px';
    canvases.pitchRibbon = { canvas: pitchCanvas, ctx: pitchCanvas.getContext('2d'), dpr, w: pw, h: ph };
  }

  // Chroma canvas: compute available space from parent card minus label
  const chromaCanvas = document.getElementById('chromaCanvas');
  if (chromaCanvas) {
    const card = chromaCanvas.closest('.chroma-card');
    const label = card.querySelector('.card-label');
    const cardStyle = getComputedStyle(card);
    const padTop = parseFloat(cardStyle.paddingTop);
    const padBottom = parseFloat(cardStyle.paddingBottom);
    const padLeft = parseFloat(cardStyle.paddingLeft);
    const padRight = parseFloat(cardStyle.paddingRight);
    const cw = card.clientWidth - padLeft - padRight;
    const ch = card.clientHeight - padTop - padBottom - label.offsetHeight;
    const ctx = chromaCanvas.getContext('2d');
    chromaCanvas.style.width = cw + 'px';
    chromaCanvas.style.height = ch + 'px';
    chromaCanvas.width = cw * dpr;
    chromaCanvas.height = ch * dpr;
    canvases.chromaCanvas = { canvas: chromaCanvas, ctx, dpr, w: cw, h: ch };
  }
}
window.addEventListener('resize', sizeCanvases);

function drawPitchRibbon() {
  const entry = canvases.pitchRibbon;
  if (!entry || !entry.ctx) return;
  const { canvas, ctx, dpr, w, h } = entry;

  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, w, h);

  // Fixed range — no re-centering, everything always visible
  const minMidi = RIBBON_MIN_MIDI;
  const maxMidi = RIBBON_MAX_MIDI;
  const range = RIBBON_RANGE;

  // Draw piano key background
  for (let m = minMidi; m <= maxMidi; m++) {
    const note = m % 12;
    const isBlack = [1,3,6,8,10].includes(note);
    const y = h - ((m - minMidi) / range) * h;
    const yNext = h - ((m + 1 - minMidi) / range) * h;
    const keyHeight = y - yNext;

    ctx.fillStyle = isBlack ? 'rgba(20,20,40,0.6)' : 'rgba(30,30,60,0.3)';
    ctx.fillRect(0, yNext, w, keyHeight);

    // Subtle grid line between keys
    ctx.strokeStyle = 'rgba(80,80,120,0.15)';
    ctx.lineWidth = 0.5;
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(w, y);
    ctx.stroke();

    // Label C notes on the left edge
    if (note === 0) {
      ctx.fillStyle = 'rgba(200,200,220,0.3)';
      ctx.font = '500 8px "JetBrains Mono"';
      ctx.textAlign = 'left';
      ctx.textBaseline = 'middle';
      ctx.fillText('C' + (Math.floor(m/12)-1), 2, yNext + keyHeight/2);
    }
  }

  // Draw pitch history as small bars with fading opacity
  const colW = w / PITCH_HISTORY_LEN;
  const barH = h / range * 0.6; // constant height, ~60% of one semitone
  const barW = Math.max(colW - 1, 2); // small gap between bars
  for (let i = 0; i < pitchHistory.length; i++) {
    const midi = pitchHistory[i];
    if (midi === null) continue;

    const x = i * colW;
    const y = h - ((midi - minMidi) / range) * h - barH / 2;
    const age = i / pitchHistory.length; // 0=oldest, 1=newest

    const hue = (midi % 12) / 12 * 300;
    ctx.fillStyle = `hsla(${hue}, 80%, 60%, ${0.15 + age * 0.85})`;
    ctx.fillRect(x, y, barW, barH);
  }
}

function drawChroma() {
  const entry = canvases.chromaCanvas;
  if (!entry || !entry.ctx) return;
  const { canvas, ctx, dpr, w, h } = entry;

  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  const barW = (w - 11 * 3) / 12; // 3px gap
  const maxVal = Math.max(...state.chroma, 0.01);

  ctx.clearRect(0, 0, w, h);

  const bottomPad = 10; // margin from card bottom edge
  const labelH = 14;   // space reserved for note labels
  const topPad = 4;    // small top padding
  const barMaxH = h - labelH - topPad - bottomPad;

  for (let i = 0; i < 12; i++) {
    const val = state.chroma[i] / maxVal;
    const barH = Math.max(val * barMaxH, 2); // minimum 2px so low values are visible
    const x = i * (barW + 3);
    const y = topPad + barMaxH - barH;

    // Gradient per bar
    const grad = ctx.createLinearGradient(x, y, x, topPad + barMaxH);
    const hue = (i / 12) * 300; // rainbow across pitch classes
    grad.addColorStop(0, `hsla(${hue}, 90%, 65%, 0.95)`);
    grad.addColorStop(1, `hsla(${hue}, 70%, 35%, 0.6)`);

    ctx.fillStyle = grad;
    ctx.beginPath();
    ctx.roundRect(x, y, barW, barH, 3);
    ctx.fill();

    // Glow
    ctx.shadowColor = `hsla(${hue}, 90%, 55%, ${val * 0.5})`;
    ctx.shadowBlur = val * 12;
    ctx.fill();
    ctx.shadowBlur = 0;

    // Note label
    ctx.fillStyle = val > 0.5 ? '#fff' : 'rgba(200,200,220,0.5)';
    ctx.font = '500 9px "JetBrains Mono"';
    ctx.textAlign = 'center';
    ctx.fillText(NOTE_NAMES[i], x + barW / 2, h - bottomPad - 2);
  }
}

// ============================================================
// MAIN LOOP
// ============================================================
function frame() {
  if (publicMode) {
    drawPublicView();
  } else {
    updateDOM();
    drawPitchRibbon();
    drawChroma();
  }
  requestAnimationFrame(frame);
}

// ============================================================
// PUBLIC / EXPERT MODE TOGGLE
// ============================================================
let publicMode = false;

function toggleMode() {
  publicMode = !publicMode;
  const pub = document.getElementById('publicCanvas');
  const grid = document.getElementById('expertGrid');
  const nav = document.getElementById('navBar');
  const hdr = document.getElementById('headerBar');
  const toggle = document.getElementById('modeToggle');

  if (publicMode) {
    pub.style.display = 'block';
    grid.style.display = 'none';
    nav.style.display = 'none';
    hdr.style.display = 'none';
    toggle.textContent = 'Expert View';
    sizePublicCanvas();
  } else {
    pub.style.display = 'none';
    grid.style.display = '';
    nav.style.display = '';
    hdr.style.display = '';
    toggle.textContent = 'Public View';
    sizeCanvases(); // re-size expert canvases in case window was resized
  }
}

function sizePublicCanvas() {
  const c = document.getElementById('publicCanvas');
  const dpr = window.devicePixelRatio || 1;
  c.width = window.innerWidth * dpr;
  c.height = window.innerHeight * dpr;
  canvases.publicCanvas = { canvas: c, ctx: c.getContext('2d'), dpr };
}
window.addEventListener('resize', () => { if (publicMode) sizePublicCanvas(); });

function drawPublicView() {
  const { canvas, ctx, dpr } = canvases.publicCanvas || {};
  if (!ctx || !publicMode) return;

  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  const w = canvas.clientWidth;
  const h = canvas.clientHeight;
  const cx = w / 2;
  const cy = h / 2;
  const maxR = Math.min(cx, cy) * 0.85;

  // Background fade (trails)
  ctx.fillStyle = 'rgba(10,10,26,0.15)';
  ctx.fillRect(0, 0, w, h);

  const time = performance.now() / 1000;

  // Radial chromagram ring
  const baseR = maxR * 0.4 + smooth.amp * maxR * 0.3;
  const maxChroma = Math.max(...state.chroma, 0.01);

  for (let i = 0; i < 12; i++) {
    const angle = (i / 12) * Math.PI * 2 - Math.PI / 2;
    const val = state.chroma[i] / maxChroma;
    const r = baseR + val * maxR * 0.35;
    const hue = (i / 12) * 300;
    const x = cx + Math.cos(angle) * r;
    const y = cy + Math.sin(angle) * r;

    // Glow orb
    const grad = ctx.createRadialGradient(x, y, 0, x, y, 20 + val * 30);
    grad.addColorStop(0, `hsla(${hue}, 90%, 65%, ${0.3 + val * 0.7})`);
    grad.addColorStop(1, `hsla(${hue}, 90%, 45%, 0)`);
    ctx.fillStyle = grad;
    ctx.beginPath();
    ctx.arc(x, y, 20 + val * 30, 0, Math.PI * 2);
    ctx.fill();

    // Connecting line to center
    ctx.strokeStyle = `hsla(${hue}, 80%, 55%, ${val * 0.3})`;
    ctx.lineWidth = 1 + val * 2;
    ctx.beginPath();
    ctx.moveTo(cx, cy);
    ctx.lineTo(x, y);
    ctx.stroke();

    // Note label
    ctx.fillStyle = `hsla(0, 0%, 100%, ${0.3 + val * 0.7})`;
    ctx.font = `${val > 0.5 ? 'bold ' : ''}${12 + val * 6}px Orbitron`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    const labelR = r + 25 + val * 10;
    ctx.fillText(NOTE_NAMES[i], cx + Math.cos(angle) * labelR, cy + Math.sin(angle) * labelR);
  }

  // Center: BPM + Key
  ctx.fillStyle = 'rgba(255,255,255,0.9)';
  ctx.font = 'bold 48px Orbitron';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  const bpmText = state.bpm > 0 ? Math.round(state.bpm) : '---';
  ctx.fillText(bpmText, cx, cy - 16);

  ctx.fillStyle = 'rgba(200,200,220,0.6)';
  ctx.font = '14px Orbitron';
  ctx.fillText('BPM', cx, cy + 16);

  const keyText = NOTE_NAMES[state.key] + ' ' + (state.mode === 1 ? 'MAJ' : 'min');
  ctx.fillStyle = state.mode === 1 ? 'rgba(255,215,0,0.8)' : 'rgba(0,229,255,0.8)';
  ctx.font = 'bold 20px Orbitron';
  ctx.fillText(keyText, cx, cy + 42);

  // Amplitude ring pulse
  ctx.strokeStyle = `rgba(233,69,96,${0.1 + smooth.amp * 0.5})`;
  ctx.lineWidth = 2 + smooth.amp * 4;
  ctx.beginPath();
  ctx.arc(cx, cy, baseR * 0.3, 0, Math.PI * 2);
  ctx.stroke();

  // "tap to exit" hint (fades after 3s)
  if (time % 10 < 3) {
    ctx.fillStyle = `rgba(100,100,140,${Math.max(0, 1 - (time % 10))})`;
    ctx.font = '12px JetBrains Mono';
    ctx.fillText('tap to exit', cx, h - 30);
  }
}

// ============================================================
// INIT
// ============================================================
sizeCanvases();
connect();
requestAnimationFrame(frame);
