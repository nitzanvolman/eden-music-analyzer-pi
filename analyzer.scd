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
var scDir = thisProcess.nowExecutingPath.dirname +/+ "sc";

// ============================================================================
// CONFIGURATION
// ============================================================================
(scDir +/+ "config.scd").load;

// --- Startup banner (printed to console / log) ---
"==============================================".postln;
"  SC-OSC Audio Analyzer".postln;
if(~cfg[\testMode], { "  *** TEST MODE — synthetic data, no audio ***".postln });
"==============================================".postln;
("  Date: " ++ Date.localtime.asString).postln;
~dests.do({ |d|
	("  OSC destination: " ++ d.ip ++ ":" ++ d.port).postln;
});
"----------------------------------------------".postln;

// ============================================================================
// TEST MODE (or normal audio analysis)
// ============================================================================
// When SC_TEST_MODE=1, bypass the audio server entirely and send synthetic
// OSC messages from sclang. Useful for testing receivers without audio hardware.

if(~cfg[\testMode], {
	// ======================================================================
	// TEST MODE: synthetic OSC data
	// ======================================================================
	(scDir +/+ "test_mode.scd").load;

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

		// Load the SynthDef
		(scDir +/+ "synthdef.scd").load;

		// s.sync waits until the server has finished loading the SynthDef.
		s.sync;
		"  SynthDef added. Starting analyzer...".postln;

		// ========================================================================
		// START THE ANALYZER
		// ========================================================================
		// Synth(\audioAnalyzer) creates a running instance of our SynthDef.
		// From this point, audio is being analyzed in real-time.
		Synth(\audioAnalyzer);

		// Load OSC forwarding handlers
		(scDir +/+ "osc_forwarding.scd").load;

	// onFailure: runs if the audio server fails to boot
	// (e.g., JACK not running, audio device not found)
	}, onFailure: { |error|
		("ERROR: Server failed to boot: " ++ error.asString).postln;
		1.exit;
	});
}); // end if(testMode)
)
