// ============================================================================
// analyzer.scd — Real-time audio analysis with OSC output
// Designed to run headless on Raspberry Pi via sclang.
//
// WHAT THIS DOES:
// 1. Listens to audio from your microphone / line-in
// 2. Extracts musical features (pitch, beats, loudness, etc.)
// 3. Sends each feature as an OSC message over the network
//
// HOW SUPERCOLLIDER WORKS (quick primer):
// - SC has two parts: sclang (the language/client) and scsynth (the audio server)
// - scsynth runs audio processing in real-time using "SynthDefs" (like audio plugins)
// - sclang sends commands to scsynth and receives data back via OSC
// - Inside a SynthDef, "UGens" (Unit Generators) are the building blocks
// - .kr = control rate (updates ~689 times/sec), .ar = audio rate (44100/sec)
//
// HOW TO TWEAK:
// - All parameters are in config.env (see config_template.env for docs)
// - To disable a feature: set SC_FEATURE_<name>=0 in config.env
// - To change trigger rates: set SC_TRIG_RATE_FAST/MEDIUM/SLOW
// - To change sensitivity: adjust threshold values (lower = more sensitive)
// - To add a new feature: add a UGen + SendReply in the SynthDef, and an
//   OSCdef forwarder below it
// ============================================================================

(
// In SC, everything between ( ) is executed as one block.
// "var" declares local variables — SC requires all vars at the top of their scope.
var destStr, dests;
var cfgInputChan, cfgFFTSize, cfgAmpAttack, cfgAmpRelease;
var cfgPitchMinFreq, cfgPitchMaxFreq;
var cfgMFCCCount, cfgKeyDecay, cfgBeatLock;
var cfgTrigFast, cfgTrigMedium, cfgTrigSlow;
var cfgTestMode;
var cfgInputGain, cfgHPFFreq;
var cfgGateThresh, cfgGateAttack, cfgGateRelease;
var cfgCompEnabled, cfgCompThresh, cfgCompRatio, cfgCompAttack, cfgCompRelease;
var featAmp, featPitch, featLoud, featCentroid, featFlatness;
var featMFCC, featKey, featBeat, featChroma;
var featScene, featEnergy;
var cfgSceneThresh, cfgEnergyFastRelease, cfgEnergySlowRelease;
var featOnsetSuite;
var onsetKick, onsetSnare, onsetHihat, onsetPerc;
var onsetBass, onsetMelody, onsetBright;
var onsetAny, onsetDrop, onsetSoft;
var threshKick, threshSnare, threshHihat, threshPerc;
var threshBass, threshMelody, threshBright;
var threshAny, threshDrop, threshSoft;

// ============================================================================
// CONFIGURATION
// ============================================================================
// All parameters are read from environment variables (set in config.env).
// The "?" operator means "if nil (not set), use this default instead."
// These values are captured as constants when the SynthDef compiles —
// changing config.env requires restarting the analyzer.
// See config_template.env for documentation of each parameter.

// --- OSC destinations ---
// SC_OSC_DESTINATIONS: comma-separated ip:port pairs (preferred).
//   Example: "127.0.0.1:9000,192.168.1.50:9000"
// Falls back to legacy SC_OSC_DEST_IP / SC_OSC_DEST_PORT if not set.
destStr = "SC_OSC_DESTINATIONS".getenv;

if(destStr.notNil and: { destStr.size > 0 }, {
	// Parse comma-separated ip:port pairs
	dests = destStr.split($,).collect({ |pair|
		var parts = pair.stripWhiteSpace.split($:);
		var ip = parts[0];
		var port = parts[1].asInteger;
		NetAddr(ip, port);
	});
}, {
	// Legacy single-destination fallback
	var destIP = "SC_OSC_DEST_IP".getenv ? "127.0.0.1";
	var destPort = ("SC_OSC_DEST_PORT".getenv ? "9000").asInteger;
	dests = [NetAddr(destIP, destPort)];
});

// --- Analysis parameters (from env vars, with defaults matching original hardcoded values) ---
cfgInputChan   = ("SC_AUDIO_INPUT_CHANNEL".getenv ? "0").asInteger;
cfgFFTSize     = ("SC_FFT_SIZE".getenv ? "2048").asInteger;
cfgAmpAttack   = ("SC_AMP_ATTACK_TIME".getenv ? "0.01").asFloat;
cfgAmpRelease  = ("SC_AMP_RELEASE_TIME".getenv ? "0.1").asFloat;
cfgPitchMinFreq = ("SC_PITCH_MIN_FREQ".getenv ? "50").asFloat;
cfgPitchMaxFreq = ("SC_PITCH_MAX_FREQ".getenv ? "4000").asFloat;
cfgMFCCCount   = ("SC_MFCC_NUM_COEFF".getenv ? "13").asInteger;
cfgKeyDecay    = ("SC_KEY_DECAY_TIME".getenv ? "2.0").asFloat;
cfgBeatLock    = ("SC_BEAT_LOCK".getenv ? "0").asInteger;
cfgTrigFast    = ("SC_TRIG_RATE_FAST".getenv ? "30").asFloat;
cfgTrigMedium  = ("SC_TRIG_RATE_MEDIUM".getenv ? "10").asFloat;
cfgTrigSlow    = ("SC_TRIG_RATE_SLOW".getenv ? "2").asFloat;
cfgTestMode    = ("SC_TEST_MODE".getenv ? "0") == "1";

// --- Input conditioning (applied before analysis) ---
cfgInputGain   = ("SC_INPUT_GAIN".getenv ? "1.0").asFloat;
cfgHPFFreq     = ("SC_HPF_FREQ".getenv ? "20").asFloat;
cfgGateThresh  = ("SC_NOISE_GATE_THRESHOLD".getenv ? "-96").asFloat;
cfgGateAttack  = ("SC_NOISE_GATE_ATTACK".getenv ? "0.01").asFloat;
cfgGateRelease = ("SC_NOISE_GATE_RELEASE".getenv ? "0.1").asFloat;
cfgCompEnabled = ("SC_COMPRESSOR_ENABLED".getenv ? "0") == "1";
cfgCompThresh  = ("SC_COMPRESSOR_THRESHOLD".getenv ? "-12").asFloat;
cfgCompRatio   = ("SC_COMPRESSOR_RATIO".getenv ? "3").asFloat;
cfgCompAttack  = ("SC_COMPRESSOR_ATTACK".getenv ? "0.01").asFloat;
cfgCompRelease = ("SC_COMPRESSOR_RELEASE".getenv ? "0.1").asFloat;

// --- Feature toggles (1 = enabled, 0 = disabled) ---
// Disabled features are excluded from the SynthDef graph entirely, saving CPU.
featAmp      = ("SC_FEATURE_AMPLITUDE".getenv ? "1") == "1";
featPitch    = ("SC_FEATURE_PITCH".getenv ? "1") == "1";
featLoud     = ("SC_FEATURE_LOUDNESS".getenv ? "1") == "1";
featCentroid = ("SC_FEATURE_CENTROID".getenv ? "1") == "1";
featFlatness = ("SC_FEATURE_FLATNESS".getenv ? "1") == "1";
featOnsetSuite = ("SC_FEATURE_ONSET_SUITE".getenv ? "1") == "1";
featMFCC     = ("SC_FEATURE_MFCC".getenv ? "1") == "1";
featKey      = ("SC_FEATURE_KEY".getenv ? "1") == "1";
featBeat     = ("SC_FEATURE_BEAT".getenv ? "1") == "1";
featChroma   = ("SC_FEATURE_CHROMA".getenv ? "1") == "1";
featScene    = ("SC_FEATURE_SCENE".getenv ? "1") == "1";
featEnergy   = ("SC_FEATURE_ENERGY".getenv ? "1") == "1";

// --- Scene / energy config ---
cfgSceneThresh      = ("SC_SCENE_THRESHOLD".getenv ? "1.0").asFloat;
cfgEnergyFastRelease = ("SC_ENERGY_FAST_RELEASE".getenv ? "0.5").asFloat;
cfgEnergySlowRelease = ("SC_ENERGY_SLOW_RELEASE".getenv ? "8.0").asFloat;

// --- Onset suite channel toggles and thresholds ---
// Each onset channel can be enabled/disabled independently.
// Master toggle SC_FEATURE_ONSET_SUITE gates the entire suite.
onsetKick   = featOnsetSuite and: { ("SC_ONSET_KICK".getenv   ? "1") == "1" };
onsetSnare  = featOnsetSuite and: { ("SC_ONSET_SNARE".getenv  ? "1") == "1" };
onsetHihat  = featOnsetSuite and: { ("SC_ONSET_HIHAT".getenv  ? "1") == "1" };
onsetPerc   = featOnsetSuite and: { ("SC_ONSET_PERC".getenv   ? "1") == "1" };
onsetBass   = featOnsetSuite and: { ("SC_ONSET_BASS".getenv   ? "1") == "1" };
onsetMelody = featOnsetSuite and: { ("SC_ONSET_MELODY".getenv ? "1") == "1" };
onsetBright = featOnsetSuite and: { ("SC_ONSET_BRIGHT".getenv ? "1") == "1" };
onsetAny    = featOnsetSuite and: { ("SC_ONSET_ANY".getenv    ? "1") == "1" };
onsetDrop   = featOnsetSuite and: { ("SC_ONSET_DROP".getenv   ? "0") == "1" };
onsetSoft   = featOnsetSuite and: { ("SC_ONSET_SOFT".getenv   ? "0") == "1" };

threshKick   = ("SC_ONSET_KICK_THRESHOLD".getenv   ? "0.3").asFloat;
threshSnare  = ("SC_ONSET_SNARE_THRESHOLD".getenv  ? "0.4").asFloat;
threshHihat  = ("SC_ONSET_HIHAT_THRESHOLD".getenv  ? "0.3").asFloat;
threshPerc   = ("SC_ONSET_PERC_THRESHOLD".getenv   ? "0.4").asFloat;
threshBass   = ("SC_ONSET_BASS_THRESHOLD".getenv   ? "0.7").asFloat;
threshMelody = ("SC_ONSET_MELODY_THRESHOLD".getenv ? "0.7").asFloat;
threshBright = ("SC_ONSET_BRIGHT_THRESHOLD".getenv ? "0.7").asFloat;
threshAny    = ("SC_ONSET_ANY_THRESHOLD".getenv    ? "0.5").asFloat;
threshDrop   = ("SC_ONSET_DROP_THRESHOLD".getenv   ? "0.8").asFloat;
threshSoft   = ("SC_ONSET_SOFT_THRESHOLD".getenv   ? "0.9").asFloat;

// --- Startup banner (printed to console / log) ---
"==============================================".postln;
"  SC-OSC Audio Analyzer".postln;
if(cfgTestMode, { "  *** TEST MODE — synthetic data, no audio ***".postln });
"==============================================".postln;
("  Date: " ++ Date.localtime.asString).postln;
dests.do({ |d|
	("  OSC destination: " ++ d.ip ++ ":" ++ d.port).postln;
});
"----------------------------------------------".postln;

// ============================================================================
// TEST MODE (or normal audio analysis)
// ============================================================================
// When SC_TEST_MODE=1, bypass the audio server entirely and send synthetic
// OSC messages from sclang. Useful for testing receivers without audio hardware.

if(cfgTestMode, {
	// ======================================================================
	// TEST MODE: synthetic OSC data
	// ======================================================================
	// Runs entirely in sclang — no scsynth needed. Sends plausible fake
	// data on all OSC channels at the configured trigger rates.

	var noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];

	// --- Fast features (amplitude, pitch, loudness, centroid, flatness) ---
	Routine({
		var dt = 1.0 / cfgTrigFast;
		loop {
			var t = Main.elapsedTime;
			var amp = (sin(t * 0.5) * 0.3 + 0.4).clip(0, 1);
			var freq = (sin(t * 0.2) * 200 + 440).clip(cfgPitchMinFreq, cfgPitchMaxFreq);
			var hasFreq = (sin(t * 0.3) * 0.3 + 0.7).clip(0, 1);
			var loud = amp * 40;
			var centroid = (sin(t * 0.15) * 2000 + 3000).clip(200, 8000);
			var flatness = (sin(t * 0.4) * 0.3 + 0.3).clip(0, 1);

			dests.do({ |d|
				if(featAmp, { d.sendMsg('/audio/amplitude', amp) });
				if(featPitch, { d.sendMsg('/audio/pitch', freq, hasFreq) });
				if(featLoud, { d.sendMsg('/audio/loudness', loud) });
				if(featCentroid, { d.sendMsg('/audio/spectral/centroid', centroid) });
				if(featFlatness, { d.sendMsg('/audio/spectral/flatness', flatness) });
			});
			dt.wait;
		};
	}).play;

	// --- Medium features (MFCC, chroma) ---
	Routine({
		var dt = 1.0 / cfgTrigMedium;
		loop {
			var t = Main.elapsedTime;
			var mfccArgs, chromaArgs;
			// Synthetic MFCC: smoothly varying coefficients
			mfccArgs = ['/audio/mfcc'] ++ cfgMFCCCount.collect({ |i|
				(sin(t * (0.1 + (i * 0.05))) * 10).asFloat;
			});
			// Synthetic chroma: one dominant note rotating through pitch classes
			chromaArgs = ['/audio/chroma'] ++ 12.collect({ |i|
				var dominantNote = ((t * 0.5) % 12).asInteger;
				if(i == dominantNote, { 0.8 + (0.2.rand) }, { 0.1.rand });
			});
			dests.do({ |d|
				if(featMFCC, { d.sendMsg(*mfccArgs) });
				if(featChroma, { d.sendMsg(*chromaArgs) });
			});
			dt.wait;
		};
	}).play;

	// --- Slow features (key) ---
	if(featKey, {
		Routine({
			var dt = 1.0 / cfgTrigSlow;
			loop {
				var t = Main.elapsedTime;
				var key = ((t * 0.1) % 12).asInteger;
				var mode = if((t % 20) < 10, { 1 }, { 0 });
				dests.do({ |d| d.sendMsg('/audio/key', key, mode) });
				("  [test] key: " ++ noteNames[key] ++ if(mode == 1, { " major" }, { " minor" })).postln;
				dt.wait;
			};
		}).play;
	});

	// --- Beat (simulated ~120 BPM) ---
	if(featBeat, {
		Routine({
			var bpm = 120;
			loop {
				dests.do({ |d|
					d.sendMsg('/audio/beat', 1);
					d.sendMsg('/audio/bpm', bpm.asFloat);
				});
				bpm = (sin(Main.elapsedTime * 0.05) * 20 + 120).clip(60, 200);
				(60.0 / bpm).wait;
			};
		}).play;
	});

	// --- Onset suite (simulated triggers at varying rates) ---
	// Percussive channels fire faster, melodic channels slower.
	[
		[onsetKick,   '/audio/onset/kick',   0.4,  0.3],
		[onsetSnare,  '/audio/onset/snare',  0.5,  0.4],
		[onsetHihat,  '/audio/onset/hihat',  0.15, 0.1],
		[onsetPerc,   '/audio/onset/perc',   0.2,  0.2],
		[onsetBass,   '/audio/onset/bass',   0.8,  0.5],
		[onsetMelody, '/audio/onset/melody',  0.6,  0.4],
		[onsetBright, '/audio/onset/bright', 0.5,  0.3],
		[onsetAny,    '/audio/onset/any',    0.15, 0.15],
		[onsetDrop,   '/audio/onset/drop',   2.0,  2.0],
		[onsetSoft,   '/audio/onset/soft',   1.0,  1.0],
	].do({ |spec|
		var enabled = spec[0], path = spec[1], base = spec[2], jitter = spec[3];
		if(enabled, {
			Routine({
				loop {
					dests.do({ |d| d.sendMsg(path, 1) });
					(base + jitter.rand).wait;
				};
			}).play;
		});
	});

	// --- Scene change (simulated every 8–20 seconds) ---
	if(featScene, {
		Routine({
			loop {
				dests.do({ |d| d.sendMsg('/audio/scene_change', 1) });
				(8.0 + 12.0.rand).wait;
			};
		}).play;
	});

	// --- Energy direction (simulated slow sine wave: building/breaking) ---
	if(featEnergy, {
		Routine({
			var dt = 1.0 / cfgTrigMedium;
			loop {
				var t = Main.elapsedTime;
				// Slow sine cycles through building (+1) and breaking (-1)
				var dir = sin(t * 0.15).clip(-1, 1);
				dests.do({ |d| d.sendMsg('/audio/energy_direction', dir) });
				dt.wait;
			};
		}).play;
	});

	// --- Heartbeat (always active) ---
	Routine({
		loop {
			dests.do({ |d| d.sendMsg('/audio/heartbeat', 1) });
			2.wait;
		};
	}).play;

	"  Test mode running. Sending synthetic OSC data.".postln;
	("  Sending to " ++ dests.size.asString ++ " destination(s)").postln;
	"  Press Ctrl+C to stop.".postln;

}, {
// ============================================================================
// NORMAL MODE: BOOT THE AUDIO SERVER
// ============================================================================
// s = the default server (scsynth). waitForBoot runs the function once
// the audio server is ready. onFailure runs if booting fails.
s.waitForBoot({

	// Print audio device info so you can verify the right input is being used
	("  Audio device: " ++ Server.default.options.device.asString).postln;
	("  Sample rate:  " ++ s.sampleRate.asString ++ " Hz").postln;
	("  Block size:   " ++ s.options.blockSize.asString).postln;
	"==============================================".postln;
	"  Booted. Defining analysis synth...".postln;

	// ========================================================================
	// SYNTHDEF: The audio analysis engine
	// ========================================================================
	// A SynthDef is a recipe for audio processing. It runs on scsynth's
	// audio thread in compiled C++, so it's very fast.
	// \audioAnalyzer is the name (a Symbol, like a constant string).
	SynthDef(\audioAnalyzer, {

		// --- Variable declarations (SC requires these at top of function) ---
		var sig, chain;
		var amp, freq, hasFreq, loud, centroid, flatness;
		var mfcc, keyRaw, bt2, beatTrig, bpm;
		var chroma;
		var sceneChange, energyFast, energySlow, energyDir;

		// --- Trigger clocks (rates from config) ---
		// Impulse.kr(N) produces a trigger N times per second.
		// We use these to control how often each feature is sent via OSC.
		// Higher rate = more responsive but more network traffic & CPU.
		var trigFast   = Impulse.kr(cfgTrigFast);   // fast-moving features
		var trigMedium = Impulse.kr(cfgTrigMedium); // medium features (MFCC, chroma)
		var trigSlow   = Impulse.kr(cfgTrigSlow);   // slow features (key detection)

		// ====================================================================
		// AUDIO INPUT
		// ====================================================================
		// SoundIn.ar(0) reads from the first audio input channel.
		// Change 0 to 1 for the second channel, etc.
		// The audio device is configured via JACK (~/.jackdrc).
		sig = SoundIn.ar(cfgInputChan);

		// ====================================================================
		// INPUT CONDITIONING
		// ====================================================================
		// Signal chain: Gain → HPF (rumble removal) → Noise Gate → Compressor
		// All stages are transparent at default values. Tune in config.env
		// for live recordings with noise (wind, crowd, generators).

		// --- Gain: normalize input level ---
		sig = sig * cfgInputGain;

		// --- High-pass filter: remove sub-bass rumble ---
		// 20 Hz default is inaudible; set to 30–40 Hz for playa recordings
		if(cfgHPFFreq > 20, {
			sig = HPF.ar(sig, cfgHPFFreq);
		});

		// --- Noise gate: silence signal below threshold ---
		// -96 dB default is effectively off; set to -40 to -30 for noisy environments
		if(cfgGateThresh > -90, {
			var gateEnv = Amplitude.kr(sig, cfgGateAttack, cfgGateRelease);
			var gateOpen = (gateEnv.ampdb > cfgGateThresh).lag(cfgGateRelease);
			sig = sig * gateOpen;
		});

		// --- Compressor: tame dynamic range ---
		// Off by default; enable for DJ sets with huge dynamic swings
		if(cfgCompEnabled, {
			sig = Compander.ar(sig, sig,
				thresh: cfgCompThresh.dbamp,
				slopeBelow: 1,
				slopeAbove: cfgCompRatio.reciprocal,
				clampTime: cfgCompAttack,
				relaxTime: cfgCompRelease
			);
		});

		// ====================================================================
		// FFT (Fast Fourier Transform)
		// ====================================================================
		// FFT converts the audio signal from time-domain (waveform) to
		// frequency-domain (spectrum). Most analysis UGens need this.
		//
		// LocalBuf(2048) creates a buffer of 2048 samples for the FFT.
		// Larger buffer = better frequency resolution but more latency.
		// 2048 at 44100 Hz = ~46ms window, which is standard for music analysis.
		//
		// TWEAK: Change 2048 to 1024 for lower latency (but worse bass resolution)
		//        or 4096 for better frequency detail (but more latency).
		chain = FFT(LocalBuf(cfgFFTSize), sig);

		// ====================================================================
		// FEATURE: Amplitude (volume level)
		// ====================================================================
		if(featAmp, {
			amp = Amplitude.kr(sig, cfgAmpAttack, cfgAmpRelease);
			SendReply.kr(trigFast, '/tr_amp', [amp]);
		});

		// ====================================================================
		// FEATURE: Pitch detection
		// ====================================================================
		if(featPitch, {
			# freq, hasFreq = Pitch.kr(sig, 440, cfgPitchMinFreq, cfgPitchMaxFreq);
			SendReply.kr(trigFast, '/tr_pitch', [freq, hasFreq]);
		});

		// ====================================================================
		// FEATURE: Loudness (perceptual)
		// ====================================================================
		if(featLoud, {
			loud = Loudness.kr(chain);
			SendReply.kr(trigFast, '/tr_loudness', [loud]);
		});

		// ====================================================================
		// FEATURE: Spectral Centroid ("brightness")
		// ====================================================================
		if(featCentroid, {
			centroid = SpecCentroid.kr(chain);
			SendReply.kr(trigFast, '/tr_centroid', [centroid]);
		});

		// ====================================================================
		// FEATURE: Spectral Flatness ("noisiness")
		// ====================================================================
		if(featFlatness, {
			flatness = SpecFlatness.kr(chain);
			SendReply.kr(trigFast, '/tr_flatness', [flatness]);
		});

		// ====================================================================
		// FEATURE: Onset detection suite
		// ====================================================================
		// Multiple onset detectors running in parallel, each tuned for a
		// distinct musical event. Frequency-filtered channels run their own
		// FFT on a band-passed version of the signal. Full-spectrum channels
		// share the main FFT chain via PV_Copy.
		//
		// Percussive channels use \mkl (spectral shape change — sharp transients).
		// Melodic channels use \phase (phase deviation — pitched note changes).
		// Catch-all uses \rcomplex (combined magnitude+phase — general purpose).
		// Energy channel uses \power (raw energy — big impacts).

		// --- Frequency-filtered onset channels ---
		// Each applies an audio filter, then runs its own FFT + Onsets.
		if(onsetKick, {
			var sigLow = LPF.ar(sig, 100);
			var fftLow = FFT(LocalBuf(cfgFFTSize), sigLow);
			SendReply.kr(Onsets.kr(fftLow, threshKick, \mkl), '/tr_onset_kick', [1]);
		});
		if(onsetSnare, {
			var sigMid = BPF.ar(sig, 632, 2.85);  // 200–2000 Hz (geometric center)
			var fftMid = FFT(LocalBuf(cfgFFTSize), sigMid);
			SendReply.kr(Onsets.kr(fftMid, threshSnare, \mkl), '/tr_onset_snare', [1]);
		});
		if(onsetHihat, {
			var sigHi = HPF.ar(sig, 5000);
			var fftHi = FFT(LocalBuf(cfgFFTSize), sigHi);
			SendReply.kr(Onsets.kr(fftHi, threshHihat, \mkl), '/tr_onset_hihat', [1]);
		});
		if(onsetBass, {
			var sigBass = LPF.ar(sig, 200);
			var fftBass = FFT(LocalBuf(cfgFFTSize), sigBass);
			SendReply.kr(Onsets.kr(fftBass, threshBass, \phase), '/tr_onset_bass', [1]);
		});
		if(onsetMelody, {
			var sigMel = BPF.ar(sig, 1095, 3.38);  // 300–4000 Hz (geometric center)
			var fftMel = FFT(LocalBuf(cfgFFTSize), sigMel);
			SendReply.kr(Onsets.kr(fftMel, threshMelody, \phase), '/tr_onset_melody', [1]);
		});
		if(onsetBright, {
			var sigBrt = HPF.ar(sig, 3000);
			var fftBrt = FFT(LocalBuf(cfgFFTSize), sigBrt);
			SendReply.kr(Onsets.kr(fftBrt, threshBright, \phase), '/tr_onset_bright', [1]);
		});

		// --- Full-spectrum onset channels (share main FFT via PV_Copy) ---
		if(onsetPerc, {
			var chainCopy = PV_Copy(chain, LocalBuf(cfgFFTSize));
			SendReply.kr(Onsets.kr(chainCopy, threshPerc, \mkl), '/tr_onset_perc', [1]);
		});
		if(onsetAny, {
			var chainCopy = PV_Copy(chain, LocalBuf(cfgFFTSize));
			SendReply.kr(Onsets.kr(chainCopy, threshAny, \rcomplex), '/tr_onset_any', [1]);
		});
		if(onsetDrop, {
			var chainCopy = PV_Copy(chain, LocalBuf(cfgFFTSize));
			SendReply.kr(Onsets.kr(chainCopy, threshDrop, \power), '/tr_onset_drop', [1]);
		});
		if(onsetSoft, {
			var chainCopy = PV_Copy(chain, LocalBuf(cfgFFTSize));
			SendReply.kr(Onsets.kr(chainCopy, threshSoft, \rcomplex), '/tr_onset_soft', [1]);
		});

		// ====================================================================
		// FEATURE: MFCC (timbre fingerprint)
		// ====================================================================
		if(featMFCC, {
			mfcc = MFCC.kr(chain, cfgMFCCCount);
			SendReply.kr(trigMedium, '/tr_mfcc', mfcc);
		});

		// ====================================================================
		// FEATURE: Key detection (musical key)
		// ====================================================================
		if(featKey, {
			keyRaw = KeyTrack.kr(chain, cfgKeyDecay);
			SendReply.kr(trigSlow, '/tr_key', [keyRaw]);
		});

		// ====================================================================
		// FEATURE: Beat tracking (tempo and beat positions)
		// ====================================================================
		if(featBeat, {
			bt2 = BeatTrack2.kr(chain, cfgBeatLock);
			beatTrig = bt2[0];
			bpm = bt2[3];
			SendReply.kr(beatTrig, '/tr_beat', [1]);
			SendReply.kr(beatTrig, '/tr_bpm', [bpm]);
		});

		// ====================================================================
		// FEATURE: Chromagram (pitch class energy)
		// ====================================================================
		if(featChroma and: { 'Chromagram'.asClass.notNil }, {
			chroma = 'Chromagram'.asClass.kr(chain, cfgFFTSize);
			SendReply.kr(trigMedium, '/tr_chroma', chroma);
		});

		// ====================================================================
		// FEATURE: Scene change detection (spectral novelty)
		// ====================================================================
		// PV_HainsworthFoote measures spectral change between consecutive
		// FFT frames. With foot=1, hains=0 it's purely spectral novelty —
		// fires on breakdowns, drops, track transitions, filter sweeps.
		if(featScene, {
			var chainCopy = PV_Copy(chain, LocalBuf(cfgFFTSize));
			sceneChange = PV_HainsworthFoote.ar(chainCopy, 0.0, 1.0, cfgSceneThresh, 0.04);
			SendReply.kr(A2K.kr(sceneChange), '/tr_scene_change', [1]);
		});

		// ====================================================================
		// FEATURE: Energy direction (building up / breaking down)
		// ====================================================================
		// Compares short-term energy (fast envelope) to long-term energy
		// (slow envelope). Positive = building up, negative = breaking down.
		// Sent at medium rate as a continuous -1 to +1 value.
		if(featEnergy, {
			energyFast = Amplitude.kr(sig, 0.01, cfgEnergyFastRelease);
			energySlow = Amplitude.kr(sig, 0.01, cfgEnergySlowRelease);
			energyDir = ((energyFast - energySlow) / energySlow.max(0.001)).clip(-1, 1);
			SendReply.kr(trigMedium, '/tr_energy_direction', [energyDir]);
		});

		// ====================================================================
		// OUTPUT: silence (analysis only, no sound output)
		// ====================================================================
		// We must write something to the output bus or SC may optimize away
		// the synth. DC.ar(0) is digital silence.
		Out.ar(0, DC.ar(0));

	}).add;
	// .add sends the SynthDef to the server and makes it available to play.

	// s.sync waits until the server has finished loading the SynthDef.
	s.sync;
	"  SynthDef added. Starting analyzer...".postln;

	// ========================================================================
	// START THE ANALYZER
	// ========================================================================
	// Synth(\audioAnalyzer) creates a running instance of our SynthDef.
	// From this point, audio is being analyzed in real-time.
	Synth(\audioAnalyzer);

	// ========================================================================
	// OSC FORWARDING
	// ========================================================================
	// SendReply (inside the SynthDef) sends messages from scsynth to sclang.
	// But we want to send them to an EXTERNAL application (your lighting
	// controller, VJ software, etc.) via the network.
	//
	// OSCdef registers a named handler that fires whenever a matching message
	// arrives. We use it to relay each internal message to the external
	// destination configured above.
	//
	// Message format from SendReply:
	//   msg[0] = address string (e.g., '/tr_amp')
	//   msg[1] = node ID (which synth sent it — we ignore this)
	//   msg[2] = reply ID (always 0 unless specified — we ignore this)
	//   msg[3] = first data value
	//   msg[4] = second data value (if any)
	//   ...etc
	//
	// dests.do iterates over all configured OSC destinations and sends
	// the message to each one (broadcast pattern).
	//
	// TO DISABLE A FEATURE: set SC_FEATURE_<name>=0 in config.env.
	// This excludes the UGen from the graph entirely, saving CPU.
	// ========================================================================

	// --- OSCdef forwarders (only registered for enabled features) ---
	if(featAmp, {
		OSCdef(\fwdAmp, { |msg|
			dests.do({ |d| d.sendMsg('/audio/amplitude', msg[3].asFloat) });
		}, '/tr_amp');
	});
	if(featPitch, {
		OSCdef(\fwdPitch, { |msg|
			dests.do({ |d| d.sendMsg('/audio/pitch', msg[3].asFloat, msg[4].asFloat) });
		}, '/tr_pitch');
	});
	// --- Onset suite forwarders ---
	if(onsetKick, {
		OSCdef(\fwdOnsetKick, { |msg|
			dests.do({ |d| d.sendMsg('/audio/onset/kick', 1) });
		}, '/tr_onset_kick');
	});
	if(onsetSnare, {
		OSCdef(\fwdOnsetSnare, { |msg|
			dests.do({ |d| d.sendMsg('/audio/onset/snare', 1) });
		}, '/tr_onset_snare');
	});
	if(onsetHihat, {
		OSCdef(\fwdOnsetHihat, { |msg|
			dests.do({ |d| d.sendMsg('/audio/onset/hihat', 1) });
		}, '/tr_onset_hihat');
	});
	if(onsetPerc, {
		OSCdef(\fwdOnsetPerc, { |msg|
			dests.do({ |d| d.sendMsg('/audio/onset/perc', 1) });
		}, '/tr_onset_perc');
	});
	if(onsetBass, {
		OSCdef(\fwdOnsetBass, { |msg|
			dests.do({ |d| d.sendMsg('/audio/onset/bass', 1) });
		}, '/tr_onset_bass');
	});
	if(onsetMelody, {
		OSCdef(\fwdOnsetMelody, { |msg|
			dests.do({ |d| d.sendMsg('/audio/onset/melody', 1) });
		}, '/tr_onset_melody');
	});
	if(onsetBright, {
		OSCdef(\fwdOnsetBright, { |msg|
			dests.do({ |d| d.sendMsg('/audio/onset/bright', 1) });
		}, '/tr_onset_bright');
	});
	if(onsetAny, {
		OSCdef(\fwdOnsetAny, { |msg|
			dests.do({ |d| d.sendMsg('/audio/onset/any', 1) });
		}, '/tr_onset_any');
	});
	if(onsetDrop, {
		OSCdef(\fwdOnsetDrop, { |msg|
			dests.do({ |d| d.sendMsg('/audio/onset/drop', 1) });
		}, '/tr_onset_drop');
	});
	if(onsetSoft, {
		OSCdef(\fwdOnsetSoft, { |msg|
			dests.do({ |d| d.sendMsg('/audio/onset/soft', 1) });
		}, '/tr_onset_soft');
	});
	if(featLoud, {
		OSCdef(\fwdLoudness, { |msg|
			dests.do({ |d| d.sendMsg('/audio/loudness', msg[3].asFloat) });
		}, '/tr_loudness');
	});
	if(featCentroid, {
		OSCdef(\fwdCentroid, { |msg|
			dests.do({ |d| d.sendMsg('/audio/spectral/centroid', msg[3].asFloat) });
		}, '/tr_centroid');
	});
	if(featFlatness, {
		OSCdef(\fwdFlatness, { |msg|
			dests.do({ |d| d.sendMsg('/audio/spectral/flatness', msg[3].asFloat) });
		}, '/tr_flatness');
	});
	if(featMFCC, {
		OSCdef(\fwdMFCC, { |msg|
			var coeffs = msg[3 .. (3 + cfgMFCCCount - 1)].collect(_.asFloat);
			dests.do({ |d| d.sendMsg(*(['/audio/mfcc'] ++ coeffs)) });
		}, '/tr_mfcc');
	});
	if(featKey, {
		OSCdef(\fwdKey, { |msg|
			var raw, key, mode;
			raw = msg[3].asInteger;
			key = raw % 12;
			mode = if(raw < 12, { 1 }, { 0 });
			dests.do({ |d| d.sendMsg('/audio/key', key, mode) });
		}, '/tr_key');
	});
	if(featBeat, {
		OSCdef(\fwdBeat, { |msg|
			dests.do({ |d| d.sendMsg('/audio/beat', 1) });
		}, '/tr_beat');
		OSCdef(\fwdBPM, { |msg|
			dests.do({ |d| d.sendMsg('/audio/bpm', msg[3].asFloat) });
		}, '/tr_bpm');
	});
	if(featChroma, {
		OSCdef(\fwdChroma, { |msg|
			dests.do({ |d| d.sendMsg('/audio/chroma',
				msg[3].asFloat, msg[4].asFloat, msg[5].asFloat, msg[6].asFloat,
				msg[7].asFloat, msg[8].asFloat, msg[9].asFloat, msg[10].asFloat,
				msg[11].asFloat, msg[12].asFloat, msg[13].asFloat, msg[14].asFloat
			) });
		}, '/tr_chroma');
	});
	if(featScene, {
		OSCdef(\fwdSceneChange, { |msg|
			dests.do({ |d| d.sendMsg('/audio/scene_change', 1) });
		}, '/tr_scene_change');
	});
	if(featEnergy, {
		OSCdef(\fwdEnergyDir, { |msg|
			dests.do({ |d| d.sendMsg('/audio/energy_direction', msg[3].asFloat) });
		}, '/tr_energy_direction');
	});

	// --- Heartbeat (always active) ---
	Routine({
		loop {
			dests.do({ |d| d.sendMsg('/audio/heartbeat', 1) });
			2.wait;
		};
	}).play;

	"  All OSCdefs registered.".postln;
	("  Sending OSC to " ++ dests.size.asString ++ " destination(s)").postln;
	"  Analyzer running. Ctrl+C to stop.".postln;

// onFailure: runs if the audio server fails to boot
// (e.g., JACK not running, audio device not found)
}, onFailure: { |error|
	("ERROR: Server failed to boot: " ++ error.asString).postln;
	1.exit;
});
}); // end if(cfgTestMode)
)
