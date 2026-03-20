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
// - To disable a feature: comment out its SendReply line AND its OSCdef block
// - To change how often a feature is sent: change the Impulse.kr(N) rate
// - To change sensitivity: adjust threshold values (lower = more sensitive)
// - To add a new feature: add a UGen + SendReply in the SynthDef, and an
//   OSCdef forwarder below it
// ============================================================================

(
// In SC, everything between ( ) is executed as one block.
// "var" declares local variables — SC requires all vars at the top of their scope.
var destStr, dests;
var cfgInputChan, cfgFFTSize, cfgAmpAttack, cfgAmpRelease;
var cfgPitchMinFreq, cfgPitchMaxFreq, cfgOnsetThresh, cfgOnsetAlgo;
var cfgMFCCCount, cfgKeyDecay, cfgBeatLock;
var cfgTrigFast, cfgTrigMedium, cfgTrigSlow;
var cfgTestMode;

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
cfgOnsetThresh = ("SC_ONSET_THRESHOLD".getenv ? "0.5").asFloat;
cfgOnsetAlgo   = ("SC_ONSET_ALGORITHM".getenv ? "rcomplex").asSymbol;
cfgMFCCCount   = ("SC_MFCC_NUM_COEFF".getenv ? "13").asInteger;
cfgKeyDecay    = ("SC_KEY_DECAY_TIME".getenv ? "2.0").asFloat;
cfgBeatLock    = ("SC_BEAT_LOCK".getenv ? "0").asInteger;
cfgTrigFast    = ("SC_TRIG_RATE_FAST".getenv ? "30").asFloat;
cfgTrigMedium  = ("SC_TRIG_RATE_MEDIUM".getenv ? "10").asFloat;
cfgTrigSlow    = ("SC_TRIG_RATE_SLOW".getenv ? "2").asFloat;
cfgTestMode    = ("SC_TEST_MODE".getenv ? "0") == "1";

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
				d.sendMsg('/audio/amplitude', amp);
				d.sendMsg('/audio/pitch', freq, hasFreq);
				d.sendMsg('/audio/loudness', loud);
				d.sendMsg('/audio/spectral/centroid', centroid);
				d.sendMsg('/audio/spectral/flatness', flatness);
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
				d.sendMsg(*mfccArgs);
				d.sendMsg(*chromaArgs);
			});
			dt.wait;
		};
	}).play;

	// --- Slow features (key) ---
	Routine({
		var dt = 1.0 / cfgTrigSlow;
		loop {
			var t = Main.elapsedTime;
			var key = ((t * 0.1) % 12).asInteger;
			var mode = if((t % 20) < 10, { 1 }, { 0 }); // alternate major/minor
			dests.do({ |d| d.sendMsg('/audio/key', key, mode) });
			("  [test] key: " ++ noteNames[key] ++ if(mode == 1, { " major" }, { " minor" })).postln;
			dt.wait;
		};
	}).play;

	// --- Beat (simulated ~120 BPM) ---
	Routine({
		var bpm = 120;
		loop {
			dests.do({ |d|
				d.sendMsg('/audio/beat', 1);
				d.sendMsg('/audio/bpm', bpm.asFloat);
			});
			// Slowly drift BPM between 100-140
			bpm = (sin(Main.elapsedTime * 0.05) * 20 + 120).clip(60, 200);
			(60.0 / bpm).wait;
		};
	}).play;

	// --- Onset (simulated random hits) ---
	Routine({
		loop {
			dests.do({ |d| d.sendMsg('/audio/onset', 1) });
			(0.1 + 0.4.rand).wait; // random interval 0.1-0.5s
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
		var amp, freq, hasFreq, onset, loud, centroid, flatness;
		var mfcc, keyRaw, bt2, beatTrig, bpm;
		var chroma;

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
		// Amplitude.kr follows the volume envelope of the signal.
		// attackTime: how fast it reacts to volume increases (seconds)
		// releaseTime: how fast it reacts to volume decreases (seconds)
		// Output: 0.0 (silence) to ~1.0 (full scale)
		//
		// TWEAK: Increase attackTime for smoother response, decrease for snappier
		amp = Amplitude.kr(sig, cfgAmpAttack, cfgAmpRelease);

		// SendReply sends data from scsynth (audio server) back to sclang (client).
		// trig30 = send 30 times per second
		// '/tr_amp' = internal message name (matched by OSCdef below)
		// [amp] = the data to send (wrapped in array)
		SendReply.kr(trigFast, '/tr_amp', [amp]);

		// ====================================================================
		// FEATURE: Pitch detection
		// ====================================================================
		// Pitch.kr detects the fundamental frequency of the audio.
		// Returns two values:
		//   freq    = detected frequency in Hz (e.g., 440.0 for concert A)
		//   hasFreq = confidence (0.0 = no pitch detected, 1.0 = confident)
		//
		// The "#" syntax unpacks multiple return values into separate variables.
		//
		// minFreq/maxFreq limits the detection range.
		// TWEAK: For bass-heavy music, lower minFreq to 30.
		//        For vocals only, narrow to 80-1000.
		// Pitch.kr args: input, initFreq, minFreq, maxFreq, ...
		// We set initFreq to default (440), minFreq=50, maxFreq=4000
		# freq, hasFreq = Pitch.kr(sig, 440, cfgPitchMinFreq, cfgPitchMaxFreq);
		SendReply.kr(trigFast, '/tr_pitch', [freq, hasFreq]);

		// ====================================================================
		// FEATURE: Loudness (perceptual)
		// ====================================================================
		// Loudness.kr measures perceived loudness in sones (psychoacoustic model).
		// Unlike raw amplitude, this accounts for how humans actually hear —
		// e.g., we're more sensitive to midrange frequencies.
		// Requires an FFT chain as input.
		// Output: 0 (silence) to ~64+ (very loud)
		loud = Loudness.kr(chain);
		SendReply.kr(trigFast, '/tr_loudness', [loud]);

		// ====================================================================
		// FEATURE: Spectral Centroid ("brightness")
		// ====================================================================
		// The "center of mass" of the frequency spectrum.
		// High value = bright/trebly sound. Low value = dark/bassy sound.
		// Output: frequency in Hz (typically 200-8000 for music)
		//
		// USE CASE: Map to color temperature — low=warm/red, high=cool/blue
		centroid = SpecCentroid.kr(chain);
		SendReply.kr(trigFast, '/tr_centroid', [centroid]);

		// ====================================================================
		// FEATURE: Spectral Flatness ("noisiness")
		// ====================================================================
		// Measures how noise-like vs tone-like the sound is.
		// 0.0 = pure tone (like a flute). 1.0 = pure noise (like static).
		// Drums/percussion tend to have higher flatness than melodic instruments.
		//
		// USE CASE: Distinguish between rhythmic and melodic sections
		flatness = SpecFlatness.kr(chain);
		SendReply.kr(trigFast, '/tr_flatness', [flatness]);

		// ====================================================================
		// FEATURE: Onset detection (note/drum hits)
		// ====================================================================
		// Onsets.kr detects when a new note or drum hit starts.
		// It outputs a single trigger pulse (0 or 1) at each onset.
		//
		// threshold: sensitivity. Lower = detects more onsets (including quiet ones).
		//   0.5 is a good starting point. Try 0.3 for sensitive, 0.7 for strict.
		//
		// odftype: the detection algorithm. Options:
		//   \rcomplex — (default) good all-round, handles both pitched and percussive
		//   \phase    — good for pitched instruments
		//   \wphase   — weighted phase deviation
		//   \mkl      — good for percussive sounds
		//   \power    — simple energy-based
		//
		// TWEAK: Change threshold to adjust sensitivity.
		//        Change odftype to suit your music style.
		onset = Onsets.kr(chain, cfgOnsetThresh, cfgOnsetAlgo);

		// Unlike other features, onset only sends when triggered (not on a timer).
		// This means you'll get one OSC message per detected hit.
		SendReply.kr(onset, '/tr_onset', [1]);

		// ====================================================================
		// FEATURE: MFCC (timbre fingerprint)
		// ====================================================================
		// Mel-Frequency Cepstral Coefficients — a compact representation of the
		// sound's "texture" or "color." Used in speech recognition and music
		// classification. Each coefficient captures a different aspect of the
		// spectral shape.
		//
		// numcoeff: how many coefficients (default 13). More = more detail.
		// The first coefficient (~c0) relates to overall energy.
		// Coefficients 1-5 capture broad spectral shape.
		// Higher coefficients capture finer spectral detail.
		//
		// TWEAK: Reduce to 7 to save CPU. Increase to 20 for more detail.
		// USE CASE: Feed into a machine learning classifier for genre/mood detection.
		mfcc = MFCC.kr(chain, cfgMFCCCount);

		// mfcc is an array of cfgMFCCCount values — SendReply sends all of them
		SendReply.kr(trigMedium, '/tr_mfcc', mfcc);

		// ====================================================================
		// FEATURE: Key detection (musical key)
		// ====================================================================
		// KeyTrack.kr estimates the musical key (C major, A minor, etc.).
		// It analyzes the pattern of pitch classes (chroma) to find the best
		// matching key profile.
		//
		// keydecay: smoothing time in seconds. Higher = more stable but slower
		//   to react to key changes. 2.0 seconds is good for songs that stay
		//   in one key. Reduce to 0.5 for music with frequent key changes.
		//
		// Returns a SINGLE integer 0-23:
		//   0-11  = C major, C# major, D major, ... B major
		//   12-23 = C minor, C# minor, D minor, ... B minor
		// To get pitch class: raw % 12 (0=C, 1=C#, ... 11=B)
		// To get mode: raw < 12 means major, >= 12 means minor
		//
		// Sent at 2 Hz because key changes slowly in most music.
		keyRaw = KeyTrack.kr(chain, cfgKeyDecay);
		SendReply.kr(trigSlow, '/tr_key', [keyRaw]);

		// ====================================================================
		// FEATURE: Beat tracking (tempo and beat positions)
		// ====================================================================
		// BeatTrack2.kr detects beat positions and estimates tempo (BPM).
		// It uses a template-matching approach, testing both straight and
		// swung rhythmic patterns.
		//
		// lock: how much the tracker resists tempo changes.
		//   0 = free to change tempo quickly (good for live DJs)
		//   1 = locks to current tempo (good for steady tracks)
		//
		// Returns 6 channels (we index explicitly to get the right ones):
		//   [0] beatTrig    = 1 on each detected beat
		//   [1] eighthTrig  = 1 on eighth-note subdivisions
		//   [2] grooveTrig  = 1 on groove pattern matches
		//   [3] tempo       = estimated BPM
		//   [4] phase       = beat phase (0.0-1.0)
		//   [5] groovePhase = groove phase
		//
		// TWEAK: Set lock: 1 for tracks with steady tempo.
		//        BeatTrack2 works best with clear rhythmic content (drums, bass).
		bt2 = BeatTrack2.kr(chain, cfgBeatLock);
		beatTrig = bt2[0];  // beat trigger (index 0)
		bpm = bt2[3];       // tempo in BPM (index 3)

		// Only send on actual beats (not on a timer)
		SendReply.kr(beatTrig, '/tr_beat', [1]);
		SendReply.kr(beatTrig, '/tr_bpm', [bpm]);

		// ====================================================================
		// FEATURE: Chromagram (pitch class energy)
		// ====================================================================
		// A chromagram shows the energy of each of the 12 musical pitch classes
		// (C, C#, D, D#, E, F, F#, G, G#, A, A#, B) regardless of octave.
		// Think of it as "which notes are playing right now."
		//
		// Chromagram is from SCMIRUGens (part of sc3-plugins, included in
		// the redFrik standalone). If you built SC from source, you must also
		// build and install sc3-plugins for this to work.
		//
		// Arguments: chain (FFT buffer), fftsize (must match FFT buffer above)
		// Output: array of 12 floats (energy per pitch class, C through B)
		//
		// TROUBLESHOOTING: If SC errors with "Class not defined: Chromagram",
		// sc3-plugins are not installed. Comment out these two lines and the
		// /tr_chroma OSCdef below to run without chroma.
		//
		// USE CASE: Visualize harmonic content, detect chord changes,
		//           map note energy to colors/lights.
		chroma = Chromagram.kr(chain, cfgFFTSize);
		SendReply.kr(trigMedium, '/tr_chroma', chroma);

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
	// TO DISABLE A FEATURE: comment out both its SendReply (above) and
	// its OSCdef (below). This saves both CPU and network bandwidth.
	// ========================================================================

	// --- Amplitude → /audio/amplitude ---
	OSCdef(\fwdAmp, { |msg|
		dests.do({ |d| d.sendMsg('/audio/amplitude', msg[3].asFloat) });
	}, '/tr_amp');

	// --- Pitch → /audio/pitch ---
	// Sends: frequency (Hz), hasFreq (0.0-1.0 confidence)
	OSCdef(\fwdPitch, { |msg|
		dests.do({ |d| d.sendMsg('/audio/pitch', msg[3].asFloat, msg[4].asFloat) });
	}, '/tr_pitch');

	// --- Onset → /audio/onset ---
	// Sends: 1 (fires only when an onset is detected)
	OSCdef(\fwdOnset, { |msg|
		dests.do({ |d| d.sendMsg('/audio/onset', 1) });
	}, '/tr_onset');

	// --- Loudness → /audio/loudness ---
	OSCdef(\fwdLoudness, { |msg|
		dests.do({ |d| d.sendMsg('/audio/loudness', msg[3].asFloat) });
	}, '/tr_loudness');

	// --- Spectral Centroid → /audio/spectral/centroid ---
	OSCdef(\fwdCentroid, { |msg|
		dests.do({ |d| d.sendMsg('/audio/spectral/centroid', msg[3].asFloat) });
	}, '/tr_centroid');

	// --- Spectral Flatness → /audio/spectral/flatness ---
	OSCdef(\fwdFlatness, { |msg|
		dests.do({ |d| d.sendMsg('/audio/spectral/flatness', msg[3].asFloat) });
	}, '/tr_flatness');

	// --- MFCC → /audio/mfcc ---
	// Sends: cfgMFCCCount float coefficients
	// msg[3] through msg[3 + cfgMFCCCount - 1] = coefficients
	OSCdef(\fwdMFCC, { |msg|
		var coeffs = msg[3 .. (3 + cfgMFCCCount - 1)].collect(_.asFloat);
		dests.do({ |d| d.sendMsg(*(['/audio/mfcc'] ++ coeffs)) });
	}, '/tr_mfcc');

	// --- Key → /audio/key ---
	// KeyTrack returns a single integer 0-23. We decode it here:
	//   0-11  = C major through B major
	//   12-23 = C minor through B minor
	// We split it into key (0-11) and mode (0=minor, 1=major) for the consumer.
	OSCdef(\fwdKey, { |msg|
		var raw, key, mode;
		raw = msg[3].asInteger;
		key = raw % 12;                    // pitch class: 0=C, 1=C#, ... 11=B
		mode = if(raw < 12, { 1 }, { 0 }); // 1=major, 0=minor
		dests.do({ |d| d.sendMsg('/audio/key', key, mode) });
	}, '/tr_key');

	// --- Beat → /audio/beat ---
	// Sends: 1 (fires only on detected beats)
	OSCdef(\fwdBeat, { |msg|
		dests.do({ |d| d.sendMsg('/audio/beat', 1) });
	}, '/tr_beat');

	// --- BPM → /audio/bpm ---
	// Sends: estimated tempo in beats per minute
	OSCdef(\fwdBPM, { |msg|
		dests.do({ |d| d.sendMsg('/audio/bpm', msg[3].asFloat) });
	}, '/tr_bpm');

	// --- Chromagram → /audio/chroma ---
	// Sends: 12 floats (energy of C, C#, D, D#, E, F, F#, G, G#, A, A#, B)
	// msg[3] through msg[14] = pitch classes 0 (C) through 11 (B)
	OSCdef(\fwdChroma, { |msg|
		dests.do({ |d| d.sendMsg('/audio/chroma',
			msg[3].asFloat, msg[4].asFloat, msg[5].asFloat, msg[6].asFloat,
			msg[7].asFloat, msg[8].asFloat, msg[9].asFloat, msg[10].asFloat,
			msg[11].asFloat, msg[12].asFloat, msg[13].asFloat, msg[14].asFloat
		) });
	}, '/tr_chroma');

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
