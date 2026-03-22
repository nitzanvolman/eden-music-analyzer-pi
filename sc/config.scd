// ============================================================================
// sc/config.scd — Configuration reading from environment variables
// ============================================================================
// All parameters are read from environment variables (set in config.env).
// The "?" operator means "if nil (not set), use this default instead."
// These values are captured as constants when the SynthDef compiles —
// changing config.env requires restarting the analyzer.
// See config_template.env for documentation of each parameter.
(
var destStr;

// --- OSC destinations ---
// SC_OSC_DESTINATIONS: comma-separated ip:port pairs (preferred).
//   Example: "127.0.0.1:9000,192.168.1.50:9000"
// Falls back to legacy SC_OSC_DEST_IP / SC_OSC_DEST_PORT if not set.
destStr = "SC_OSC_DESTINATIONS".getenv;

if(destStr.notNil and: { destStr.size > 0 }, {
	// Parse comma-separated ip:port pairs
	~dests = destStr.split($,).collect({ |pair|
		var parts = pair.stripWhiteSpace.split($:);
		var ip = parts[0];
		var port = parts[1].asInteger;
		NetAddr(ip, port);
	});
}, {
	// Legacy single-destination fallback
	var destIP = "SC_OSC_DEST_IP".getenv ? "127.0.0.1";
	var destPort = ("SC_OSC_DEST_PORT".getenv ? "9000").asInteger;
	~dests = [NetAddr(destIP, destPort)];
});

// --- Analysis parameters (from env vars, with defaults matching original hardcoded values) ---
~cfg = (
	inputChan:   ("SC_AUDIO_INPUT_CHANNEL".getenv ? "0").asInteger,
	fftSize:     ("SC_FFT_SIZE".getenv ? "2048").asInteger,
	ampAttack:   ("SC_AMP_ATTACK_TIME".getenv ? "0.01").asFloat,
	ampRelease:  ("SC_AMP_RELEASE_TIME".getenv ? "0.1").asFloat,
	pitchMinFreq: ("SC_PITCH_MIN_FREQ".getenv ? "50").asFloat,
	pitchMaxFreq: ("SC_PITCH_MAX_FREQ".getenv ? "4000").asFloat,
	mfccCount:   ("SC_MFCC_NUM_COEFF".getenv ? "13").asInteger,
	keyDecay:    ("SC_KEY_DECAY_TIME".getenv ? "2.0").asFloat,
	beatLock:    ("SC_BEAT_LOCK".getenv ? "0").asInteger,
	trigFast:    ("SC_TRIG_RATE_FAST".getenv ? "30").asFloat,
	trigMedium:  ("SC_TRIG_RATE_MEDIUM".getenv ? "10").asFloat,
	trigSlow:    ("SC_TRIG_RATE_SLOW".getenv ? "2").asFloat,
	testMode:    ("SC_TEST_MODE".getenv ? "0") == "1",
	// --- Input conditioning (applied before analysis) ---
	inputGain:   ("SC_INPUT_GAIN".getenv ? "1.0").asFloat,
	hpfFreq:     ("SC_HPF_FREQ".getenv ? "20").asFloat,
	gateThresh:  ("SC_NOISE_GATE_THRESHOLD".getenv ? "-96").asFloat,
	gateAttack:  ("SC_NOISE_GATE_ATTACK".getenv ? "0.01").asFloat,
	gateRelease: ("SC_NOISE_GATE_RELEASE".getenv ? "0.1").asFloat,
	compEnabled: ("SC_COMPRESSOR_ENABLED".getenv ? "0") == "1",
	compThresh:  ("SC_COMPRESSOR_THRESHOLD".getenv ? "-12").asFloat,
	compRatio:   ("SC_COMPRESSOR_RATIO".getenv ? "3").asFloat,
	compAttack:  ("SC_COMPRESSOR_ATTACK".getenv ? "0.01").asFloat,
	compRelease: ("SC_COMPRESSOR_RELEASE".getenv ? "0.1").asFloat,
	// --- Scene / energy config ---
	sceneThresh:      ("SC_SCENE_THRESHOLD".getenv ? "0.4").asFloat,
	energyFastRelease: ("SC_ENERGY_FAST_RELEASE".getenv ? "0.5").asFloat,
	energySlowRelease: ("SC_ENERGY_SLOW_RELEASE".getenv ? "8.0").asFloat,
	vocalMinFreq: ("SC_VOCAL_MIN_FREQ".getenv ? "300").asFloat,
	vocalMaxFreq: ("SC_VOCAL_MAX_FREQ".getenv ? "4000").asFloat,
	chromaMinFreq: ("SC_CHROMA_MIN_FREQ".getenv ? "200").asFloat,
	chromaMaxFreq: ("SC_CHROMA_MAX_FREQ".getenv ? "4000").asFloat,
	chromaFFTSize: ("SC_CHROMA_FFT_SIZE".getenv ? "4096").asInteger,
);

// --- Feature toggles (1 = enabled, 0 = disabled) ---
// Disabled features are excluded from the SynthDef graph entirely, saving CPU.
~feat = (
	amp:      ("SC_FEATURE_AMPLITUDE".getenv ? "1") == "1",
	pitch:    ("SC_FEATURE_PITCH".getenv ? "1") == "1",
	loud:     ("SC_FEATURE_LOUDNESS".getenv ? "1") == "1",
	centroid: ("SC_FEATURE_CENTROID".getenv ? "1") == "1",
	flatness: ("SC_FEATURE_FLATNESS".getenv ? "1") == "1",
	onsetSuite: ("SC_FEATURE_ONSET_SUITE".getenv ? "1") == "1",
	mfcc:     ("SC_FEATURE_MFCC".getenv ? "1") == "1",
	key:      ("SC_FEATURE_KEY".getenv ? "1") == "1",
	beat:     ("SC_FEATURE_BEAT".getenv ? "1") == "1",
	chroma:   ("SC_FEATURE_CHROMA".getenv ? "1") == "1",
	scene:    ("SC_FEATURE_SCENE".getenv ? "1") == "1",
	energy:   ("SC_FEATURE_ENERGY".getenv ? "1") == "1",
	vocal:    ("SC_FEATURE_VOCAL".getenv ? "1") == "1",
);

// --- Onset suite channel toggles and thresholds ---
// Each onset channel can be enabled/disabled independently.
// Master toggle SC_FEATURE_ONSET_SUITE gates the entire suite.
~onset = (
	kick:   ~feat[\onsetSuite] and: { ("SC_ONSET_KICK".getenv   ? "1") == "1" },
	snare:  ~feat[\onsetSuite] and: { ("SC_ONSET_SNARE".getenv  ? "1") == "1" },
	hihat:  ~feat[\onsetSuite] and: { ("SC_ONSET_HIHAT".getenv  ? "1") == "1" },
	perc:   ~feat[\onsetSuite] and: { ("SC_ONSET_PERC".getenv   ? "1") == "1" },
	bass:   ~feat[\onsetSuite] and: { ("SC_ONSET_BASS".getenv   ? "1") == "1" },
	melody: ~feat[\onsetSuite] and: { ("SC_ONSET_MELODY".getenv ? "1") == "1" },
	bright: ~feat[\onsetSuite] and: { ("SC_ONSET_BRIGHT".getenv ? "1") == "1" },
	any:    ~feat[\onsetSuite] and: { ("SC_ONSET_ANY".getenv    ? "1") == "1" },
	drop:   ~feat[\onsetSuite] and: { ("SC_ONSET_DROP".getenv   ? "0") == "1" },
	soft:   ~feat[\onsetSuite] and: { ("SC_ONSET_SOFT".getenv   ? "0") == "1" },
);

~thresh = (
	kick:   ("SC_ONSET_KICK_THRESHOLD".getenv   ? "0.3").asFloat,
	snare:  ("SC_ONSET_SNARE_THRESHOLD".getenv  ? "0.4").asFloat,
	hihat:  ("SC_ONSET_HIHAT_THRESHOLD".getenv  ? "0.3").asFloat,
	perc:   ("SC_ONSET_PERC_THRESHOLD".getenv   ? "0.4").asFloat,
	bass:   ("SC_ONSET_BASS_THRESHOLD".getenv   ? "0.7").asFloat,
	melody: ("SC_ONSET_MELODY_THRESHOLD".getenv ? "0.7").asFloat,
	bright: ("SC_ONSET_BRIGHT_THRESHOLD".getenv ? "0.7").asFloat,
	any:    ("SC_ONSET_ANY_THRESHOLD".getenv    ? "0.5").asFloat,
	drop:   ("SC_ONSET_DROP_THRESHOLD".getenv   ? "0.8").asFloat,
	soft:   ("SC_ONSET_SOFT_THRESHOLD".getenv   ? "0.9").asFloat,
);
)
