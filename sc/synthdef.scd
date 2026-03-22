// ============================================================================
// sc/synthdef.scd — SynthDef definition for audio analysis
// ============================================================================
// Reads from ~cfg, ~feat, ~onset, ~thresh environment variables.
// Does NOT call s.sync or Synth(\audioAnalyzer) — the entry point does that.
(
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
	var mfcc, keyRaw, beatTrig, bpm;
	var chroma;
	var sceneChange, energyFast, energySlow, energyDir;
	var vocalLikelihood;

	// --- Trigger clocks (rates from config) ---
	// Impulse.kr(N) produces a trigger N times per second.
	// We use these to control how often each feature is sent via OSC.
	// Higher rate = more responsive but more network traffic & CPU.
	var trigFast   = Impulse.kr(~cfg[\trigFast]);   // fast-moving features
	var trigMedium = Impulse.kr(~cfg[\trigMedium]); // medium features (MFCC, chroma)
	var trigSlow   = Impulse.kr(~cfg[\trigSlow]);   // slow features (key detection)

	// ====================================================================
	// AUDIO INPUT
	// ====================================================================
	// SoundIn.ar(0) reads from the first audio input channel.
	// Change 0 to 1 for the second channel, etc.
	// The audio device is configured via JACK (~/.jackdrc).
	sig = SoundIn.ar(~cfg[\inputChan]);

	// ====================================================================
	// INPUT CONDITIONING
	// ====================================================================
	// Signal chain: Gain -> HPF (rumble removal) -> Noise Gate -> Compressor
	// All stages are transparent at default values. Tune in config.env
	// for live recordings with noise (wind, crowd, generators).

	// --- Gain: normalize input level ---
	sig = sig * ~cfg[\inputGain];

	// --- High-pass filter: remove sub-bass rumble ---
	// 20 Hz default is inaudible; set to 30-40 Hz for playa recordings
	if(~cfg[\hpfFreq] > 20, {
		sig = HPF.ar(sig, ~cfg[\hpfFreq]);
	});

	// --- Noise gate: silence signal below threshold ---
	// -96 dB default is effectively off; set to -40 to -30 for noisy environments
	if(~cfg[\gateThresh] > -90, {
		var gateEnv = Amplitude.kr(sig, ~cfg[\gateAttack], ~cfg[\gateRelease]);
		var gateOpen = (gateEnv.ampdb > ~cfg[\gateThresh]).lag(~cfg[\gateRelease]);
		sig = sig * gateOpen;
	});

	// --- Compressor: tame dynamic range ---
	// Off by default; enable for DJ sets with huge dynamic swings
	if(~cfg[\compEnabled], {
		sig = Compander.ar(sig, sig,
			thresh: ~cfg[\compThresh].dbamp,
			slopeBelow: 1,
			slopeAbove: ~cfg[\compRatio].reciprocal,
			clampTime: ~cfg[\compAttack],
			relaxTime: ~cfg[\compRelease]
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
	chain = FFT(LocalBuf(~cfg[\fftSize]), sig);

	// ====================================================================
	// FEATURE: Amplitude (volume level)
	// ====================================================================
	if(~feat[\amp], {
		amp = Amplitude.kr(sig, ~cfg[\ampAttack], ~cfg[\ampRelease]);
		SendReply.kr(trigFast, '/tr_amp', [amp]);
	});

	// ====================================================================
	// FEATURE: Pitch detection
	// ====================================================================
	if(~feat[\pitch], {
		# freq, hasFreq = Pitch.kr(sig, 440, ~cfg[\pitchMinFreq], ~cfg[\pitchMaxFreq]);
		SendReply.kr(trigFast, '/tr_pitch', [freq, hasFreq]);
	});

	// ====================================================================
	// FEATURE: Loudness (perceptual)
	// ====================================================================
	if(~feat[\loud], {
		loud = Loudness.kr(chain);
		SendReply.kr(trigFast, '/tr_loudness', [loud]);
	});

	// ====================================================================
	// FEATURE: Spectral Centroid ("brightness")
	// ====================================================================
	if(~feat[\centroid], {
		centroid = SpecCentroid.kr(chain);
		SendReply.kr(trigFast, '/tr_centroid', [centroid]);
	});

	// ====================================================================
	// FEATURE: Spectral Flatness ("noisiness")
	// ====================================================================
	if(~feat[\flatness], {
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
	if(~onset[\kick], {
		var sigLow = LPF.ar(sig, 100);
		var fftLow = FFT(LocalBuf(~cfg[\fftSize]), sigLow);
		SendReply.kr(Onsets.kr(fftLow, ~thresh[\kick], \mkl), '/tr_onset_kick', [1]);
	});
	if(~onset[\snare], {
		var sigMid = BPF.ar(sig, 632, 2.85);  // 200-2000 Hz (geometric center)
		var fftMid = FFT(LocalBuf(~cfg[\fftSize]), sigMid);
		SendReply.kr(Onsets.kr(fftMid, ~thresh[\snare], \mkl), '/tr_onset_snare', [1]);
	});
	if(~onset[\hihat], {
		var sigHi = HPF.ar(sig, 5000);
		var fftHi = FFT(LocalBuf(~cfg[\fftSize]), sigHi);
		SendReply.kr(Onsets.kr(fftHi, ~thresh[\hihat], \mkl), '/tr_onset_hihat', [1]);
	});
	if(~onset[\bass], {
		var sigBass = LPF.ar(sig, 200);
		var fftBass = FFT(LocalBuf(~cfg[\fftSize]), sigBass);
		SendReply.kr(Onsets.kr(fftBass, ~thresh[\bass], \phase), '/tr_onset_bass', [1]);
	});
	if(~onset[\melody], {
		var sigMel = BPF.ar(sig, 1095, 3.38);  // 300-4000 Hz (geometric center)
		var fftMel = FFT(LocalBuf(~cfg[\fftSize]), sigMel);
		SendReply.kr(Onsets.kr(fftMel, ~thresh[\melody], \phase), '/tr_onset_melody', [1]);
	});
	if(~onset[\bright], {
		var sigBrt = HPF.ar(sig, 3000);
		var fftBrt = FFT(LocalBuf(~cfg[\fftSize]), sigBrt);
		SendReply.kr(Onsets.kr(fftBrt, ~thresh[\bright], \phase), '/tr_onset_bright', [1]);
	});

	// --- Full-spectrum onset channels (share main FFT via PV_Copy) ---
	if(~onset[\perc], {
		var chainCopy = PV_Copy(chain, LocalBuf(~cfg[\fftSize]));
		SendReply.kr(Onsets.kr(chainCopy, ~thresh[\perc], \mkl), '/tr_onset_perc', [1]);
	});
	if(~onset[\any], {
		var chainCopy = PV_Copy(chain, LocalBuf(~cfg[\fftSize]));
		SendReply.kr(Onsets.kr(chainCopy, ~thresh[\any], \rcomplex), '/tr_onset_any', [1]);
	});
	if(~onset[\drop], {
		var chainCopy = PV_Copy(chain, LocalBuf(~cfg[\fftSize]));
		SendReply.kr(Onsets.kr(chainCopy, ~thresh[\drop], \power), '/tr_onset_drop', [1]);
	});
	if(~onset[\soft], {
		var chainCopy = PV_Copy(chain, LocalBuf(~cfg[\fftSize]));
		SendReply.kr(Onsets.kr(chainCopy, ~thresh[\soft], \rcomplex), '/tr_onset_soft', [1]);
	});

	// ====================================================================
	// FEATURE: MFCC (timbre fingerprint)
	// ====================================================================
	if(~feat[\mfcc], {
		mfcc = MFCC.kr(chain, ~cfg[\mfccCount]);
		SendReply.kr(trigMedium, '/tr_mfcc', mfcc);
	});

	// ====================================================================
	// FEATURE: Key detection (musical key)
	// ====================================================================
	if(~feat[\key], {
		keyRaw = KeyTrack.kr(chain, ~cfg[\keyDecay]);
		SendReply.kr(trigSlow, '/tr_key', [keyRaw]);
	});

	// ====================================================================
	// FEATURE: Beat tracking (tempo and beat positions)
	// ====================================================================
	if(~feat[\beat], {
		// BeatTrack requires FFT size 1024 — use a dedicated FFT chain.
		// Returns [beatTrig, phase, tempo, clock].
		// tempo is in beats per second — multiply by 60 for BPM.
		// lock: 0 = free (adapts quickly), 1 = locked (steady tempo)
		var beatChain = FFT(LocalBuf(1024), sig);
		var bt = BeatTrack.kr(beatChain, ~cfg[\beatLock]);
		beatTrig = bt[0];
		bpm = bt[2] * 60;  // beats/sec -> BPM
		SendReply.kr(beatTrig, '/tr_beat', [1]);
		SendReply.kr(beatTrig, '/tr_bpm', [bpm]);
	});

	// ====================================================================
	// FEATURE: Chromagram (pitch class energy)
	// ====================================================================
	// Band-pass to melodic range and use a dedicated larger FFT for
	// better frequency resolution. Filters out percussion, sub-bass,
	// and noise that would splash energy across all pitch classes.
	if(~feat[\chroma] and: { 'Chromagram'.asClass.notNil }, {
		var chromaCenter, sigChroma, chromaFlatChain, chromaFlat, tonalGate, chromaChain;
		chromaCenter = (~cfg[\chromaMinFreq] * ~cfg[\chromaMaxFreq]).sqrt;
		sigChroma = BPF.ar(sig,
			chromaCenter,
			(~cfg[\chromaMaxFreq] - ~cfg[\chromaMinFreq]) / chromaCenter
		);
		// Gate by spectral flatness: attenuate percussive/noisy content.
		// Low flatness = tonal (pass through), high flatness = percussion (suppress).
		chromaFlatChain = FFT(LocalBuf(~cfg[\fftSize]), sigChroma);
		chromaFlat = SpecFlatness.kr(chromaFlatChain);
		tonalGate = (1 - chromaFlat).clip(0, 1).lag(0.05);
		sigChroma = sigChroma * tonalGate;
		// Dedicated larger FFT for chromagram analysis
		chromaChain = FFT(LocalBuf(~cfg[\chromaFFTSize]), sigChroma);
		chroma = 'Chromagram'.asClass.kr(chromaChain, ~cfg[\chromaFFTSize]);
		// Apply exponent for contrast: dominant notes pop, weak ones suppressed
		chroma = chroma.pow(~cfg[\chromaExponent]);
		SendReply.kr(trigMedium, '/tr_chroma', chroma);
	});

	// ====================================================================
	// FEATURE: Scene change detection (spectral novelty)
	// ====================================================================
	// Composite novelty score: compares short-term (0.3s) vs long-term
	// (15s) averages of both spectral centroid and loudness. A real
	// scene change shifts both simultaneously. Single drum hits only
	// spike one briefly and get smoothed out by the 0.3s window.
	// The OSC forwarding layer applies adaptive thresholding + cooldown.
	if(~feat[\scene], {
		var sceneCentroid, sceneLoud;
		var shortCentroid, longCentroid, shortLoud, longLoud;
		var centroidShift, loudShift, sceneNovelty;
		sceneCentroid = SpecCentroid.kr(chain);
		sceneLoud = Loudness.kr(chain);
		// Short-term: fast enough to catch a drop, slow enough to ignore single hits
		shortCentroid = Lag.kr(sceneCentroid, 0.3);
		shortLoud = Lag.kr(sceneLoud, 0.3);
		// Long-term: stable baseline of current scene
		longCentroid = Lag.kr(sceneCentroid, 15.0);
		longLoud = Lag.kr(sceneLoud, 15.0);
		// Normalized divergence of each feature
		centroidShift = (shortCentroid - longCentroid).abs / longCentroid.max(1);
		loudShift = (shortLoud - longLoud).abs / longLoud.max(0.1);
		// Composite: both shifting = scene change, one shifting = transient
		sceneNovelty = centroidShift + loudShift;
		SendReply.kr(trigMedium, '/tr_scene_novelty', [sceneNovelty]);
	});

	// ====================================================================
	// FEATURE: Energy direction (building up / breaking down)
	// ====================================================================
	// Compares short-term energy (fast envelope) to long-term energy
	// (slow envelope). Positive = building up, negative = breaking down.
	// Sent at medium rate as a continuous -1 to +1 value.
	if(~feat[\energy], {
		energyFast = Amplitude.kr(sig, 0.01, ~cfg[\energyFastRelease]);
		energySlow = Amplitude.kr(sig, 2.0, ~cfg[\energySlowRelease]);
		energyDir = ((energyFast - energySlow) / energySlow.max(0.001)).clip(-1, 1);
		SendReply.kr(trigMedium, '/tr_energy_direction', [energyDir]);
	});

	// ====================================================================
	// FEATURE: Vocal likelihood (heuristic)
	// ====================================================================
	// Band-pass to the vocal range, then combine pitch confidence
	// (tonal content) with inverse spectral flatness (not noise).
	// Produces a 0-1 "vocal likelihood" score. Also triggers on
	// tonal synth leads — acceptable for EDM lighting use.
	if(~feat[\vocal], {
		var vocalCenter = (~cfg[\vocalMinFreq] * ~cfg[\vocalMaxFreq]).sqrt;
		var sigVocal = BPF.ar(sig,
			vocalCenter,                                             // geometric center
			(~cfg[\vocalMaxFreq] - ~cfg[\vocalMinFreq]) / vocalCenter        // rq = bandwidth / center
		);
		var fftVocal = FFT(LocalBuf(~cfg[\fftSize]), sigVocal);
		var vocalFreq, vocalHasFreq, vocalFlatness, vocalAmp;
		# vocalFreq, vocalHasFreq = Pitch.kr(sigVocal, 440, ~cfg[\vocalMinFreq], ~cfg[\vocalMaxFreq]);
		vocalFlatness = SpecFlatness.kr(fftVocal);
		vocalAmp = Amplitude.kr(sigVocal, 0.01, 0.1);
		// Combine: high pitch confidence + low flatness + audible level
		vocalLikelihood = (vocalHasFreq * (1 - vocalFlatness) * (vocalAmp > 0.01).lag(0.1)).clip(0, 1);
		SendReply.kr(trigMedium, '/tr_vocal', [vocalLikelihood]);
	});

	// ====================================================================
	// OUTPUT: silence (analysis only, no sound output)
	// ====================================================================
	// We must write something to the output bus or SC may optimize away
	// the synth. DC.ar(0) is digital silence.
	Out.ar(0, DC.ar(0));

}).add;
// .add sends the SynthDef to the server and makes it available to play.
)
