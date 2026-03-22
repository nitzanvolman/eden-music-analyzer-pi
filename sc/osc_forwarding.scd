// ============================================================================
// sc/osc_forwarding.scd — OSC forwarding handlers + heartbeat
// ============================================================================
// Reads from ~dests, ~feat, ~onset, ~cfg environment variables.
//
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
(
// --- OSCdef forwarders (only registered for enabled features) ---
if(~feat[\amp], {
	OSCdef(\fwdAmp, { |msg|
		~dests.do({ |d| d.sendMsg('/audio/amplitude', msg[3].asFloat) });
	}, '/tr_amp');
});
if(~feat[\pitch], {
	OSCdef(\fwdPitch, { |msg|
		~dests.do({ |d| d.sendMsg('/audio/pitch', msg[3].asFloat, msg[4].asFloat) });
	}, '/tr_pitch');
});
// --- Onset suite forwarders ---
if(~onset[\kick], {
	OSCdef(\fwdOnsetKick, { |msg|
		~dests.do({ |d| d.sendMsg('/audio/onset/kick', 1) });
	}, '/tr_onset_kick');
});
if(~onset[\snare], {
	OSCdef(\fwdOnsetSnare, { |msg|
		~dests.do({ |d| d.sendMsg('/audio/onset/snare', 1) });
	}, '/tr_onset_snare');
});
if(~onset[\hihat], {
	OSCdef(\fwdOnsetHihat, { |msg|
		~dests.do({ |d| d.sendMsg('/audio/onset/hihat', 1) });
	}, '/tr_onset_hihat');
});
if(~onset[\perc], {
	OSCdef(\fwdOnsetPerc, { |msg|
		~dests.do({ |d| d.sendMsg('/audio/onset/perc', 1) });
	}, '/tr_onset_perc');
});
if(~onset[\bass], {
	OSCdef(\fwdOnsetBass, { |msg|
		~dests.do({ |d| d.sendMsg('/audio/onset/bass', 1) });
	}, '/tr_onset_bass');
});
if(~onset[\melody], {
	OSCdef(\fwdOnsetMelody, { |msg|
		~dests.do({ |d| d.sendMsg('/audio/onset/melody', 1) });
	}, '/tr_onset_melody');
});
if(~onset[\bright], {
	OSCdef(\fwdOnsetBright, { |msg|
		~dests.do({ |d| d.sendMsg('/audio/onset/bright', 1) });
	}, '/tr_onset_bright');
});
if(~onset[\any], {
	OSCdef(\fwdOnsetAny, { |msg|
		~dests.do({ |d| d.sendMsg('/audio/onset/any', 1) });
	}, '/tr_onset_any');
});
if(~onset[\drop], {
	OSCdef(\fwdOnsetDrop, { |msg|
		~dests.do({ |d| d.sendMsg('/audio/onset/drop', 1) });
	}, '/tr_onset_drop');
});
if(~onset[\soft], {
	OSCdef(\fwdOnsetSoft, { |msg|
		~dests.do({ |d| d.sendMsg('/audio/onset/soft', 1) });
	}, '/tr_onset_soft');
});
if(~feat[\loud], {
	OSCdef(\fwdLoudness, { |msg|
		~dests.do({ |d| d.sendMsg('/audio/loudness', msg[3].asFloat) });
	}, '/tr_loudness');
});
if(~feat[\centroid], {
	OSCdef(\fwdCentroid, { |msg|
		~dests.do({ |d| d.sendMsg('/audio/spectral/centroid', msg[3].asFloat) });
	}, '/tr_centroid');
});
if(~feat[\flatness], {
	OSCdef(\fwdFlatness, { |msg|
		~dests.do({ |d| d.sendMsg('/audio/spectral/flatness', msg[3].asFloat) });
	}, '/tr_flatness');
});
if(~feat[\mfcc], {
	OSCdef(\fwdMFCC, { |msg|
		var coeffs = msg[3 .. (3 + ~cfg[\mfccCount] - 1)].collect(_.asFloat);
		~dests.do({ |d| d.sendMsg(*(['/audio/mfcc'] ++ coeffs)) });
	}, '/tr_mfcc');
});
if(~feat[\key], {
	OSCdef(\fwdKey, { |msg|
		var raw, key, mode;
		raw = msg[3].asInteger;
		key = raw % 12;
		mode = if(raw < 12, { 1 }, { 0 });
		~dests.do({ |d| d.sendMsg('/audio/key', key, mode) });
	}, '/tr_key');
});
if(~feat[\beat], {
	OSCdef(\fwdBeat, { |msg|
		~dests.do({ |d| d.sendMsg('/audio/beat', 1) });
	}, '/tr_beat');
	OSCdef(\fwdBPM, { |msg|
		~dests.do({ |d| d.sendMsg('/audio/bpm', msg[3].asFloat) });
	}, '/tr_bpm');
});
if(~feat[\chroma], {
	OSCdef(\fwdChroma, { |msg|
		~dests.do({ |d| d.sendMsg('/audio/chroma',
			msg[3].asFloat, msg[4].asFloat, msg[5].asFloat, msg[6].asFloat,
			msg[7].asFloat, msg[8].asFloat, msg[9].asFloat, msg[10].asFloat,
			msg[11].asFloat, msg[12].asFloat, msg[13].asFloat, msg[14].asFloat
		) });
	}, '/tr_chroma');
});
if(~feat[\scene], {
	// Adaptive scene change detection:
	// - Maintain a ring buffer of recent novelty scores
	// - Trigger only when current value exceeds running average * sensitivity
	// - Enforce a cooldown period between triggers
	var bufSize = (~cfg[\sceneWindow] * ~cfg[\trigMedium]).asInteger.max(10);
	var noveltyBuf = Array.fill(bufSize, { 0.0 });
	var bufIdx = 0;
	var lastTrigTime = 0;

	OSCdef(\fwdSceneNovelty, { |msg|
		var novelty = msg[3].asFloat;
		var now = Main.elapsedTime;
		var avg, threshold;

		// Update ring buffer
		noveltyBuf[bufIdx] = novelty;
		bufIdx = (bufIdx + 1) % bufSize;

		// Compute running average
		avg = noveltyBuf.mean;

		// Adaptive threshold: trigger when novelty exceeds average * sensitivity
		threshold = avg * ~cfg[\sceneSensitivity];

		if((novelty > threshold) and: { (now - lastTrigTime) > ~cfg[\sceneCooldown] } and: { avg > 0 }, {
			lastTrigTime = now;
			~dests.do({ |d| d.sendMsg('/audio/scene_change', 1) });
		});

		// Always forward the raw novelty score for visualization
		~dests.do({ |d| d.sendMsg('/audio/scene_novelty', novelty) });
	}, '/tr_scene_novelty');
});
if(~feat[\energy], {
	OSCdef(\fwdEnergyDir, { |msg|
		~dests.do({ |d| d.sendMsg('/audio/energy_direction', msg[3].asFloat) });
	}, '/tr_energy_direction');
});
if(~feat[\vocal], {
	OSCdef(\fwdVocal, { |msg|
		~dests.do({ |d| d.sendMsg('/audio/vocal', msg[3].asFloat) });
	}, '/tr_vocal');
});

// --- Heartbeat (always active) ---
Routine({
	loop {
		~dests.do({ |d| d.sendMsg('/audio/heartbeat', 1) });
		2.wait;
	};
}).play;

"  All OSCdefs registered.".postln;
("  Sending OSC to " ++ ~dests.size.asString ++ " destination(s)").postln;
"  Analyzer running. Ctrl+C to stop.".postln;
)
