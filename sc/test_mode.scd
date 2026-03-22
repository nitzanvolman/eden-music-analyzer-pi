// ============================================================================
// sc/test_mode.scd — Test mode: synthetic OSC data
// ============================================================================
// Runs entirely in sclang — no scsynth needed. Sends plausible fake
// data on all OSC channels at the configured trigger rates.
// Reads from ~dests, ~feat, ~onset, ~cfg environment variables.
(
var noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];

// --- Fast features (amplitude, pitch, loudness, centroid, flatness) ---
Routine({
	var dt = 1.0 / ~cfg[\trigFast];
	loop {
		var t = Main.elapsedTime;
		var amp = (sin(t * 0.5) * 0.3 + 0.4).clip(0, 1);
		var freq = (sin(t * 0.2) * 200 + 440).clip(~cfg[\pitchMinFreq], ~cfg[\pitchMaxFreq]);
		var hasFreq = (sin(t * 0.3) * 0.3 + 0.7).clip(0, 1);
		var loud = amp * 40;
		var centroid = (sin(t * 0.15) * 2000 + 3000).clip(200, 8000);
		var flatness = (sin(t * 0.4) * 0.3 + 0.3).clip(0, 1);

		~dests.do({ |d|
			if(~feat[\amp], { d.sendMsg('/audio/amplitude', amp) });
			if(~feat[\pitch], { d.sendMsg('/audio/pitch', freq, hasFreq) });
			if(~feat[\loud], { d.sendMsg('/audio/loudness', loud) });
			if(~feat[\centroid], { d.sendMsg('/audio/spectral/centroid', centroid) });
			if(~feat[\flatness], { d.sendMsg('/audio/spectral/flatness', flatness) });
		});
		dt.wait;
	};
}).play;

// --- Medium features (MFCC, chroma) ---
Routine({
	var dt = 1.0 / ~cfg[\trigMedium];
	loop {
		var t = Main.elapsedTime;
		var mfccArgs, chromaArgs;
		// Synthetic MFCC: smoothly varying coefficients
		mfccArgs = ['/audio/mfcc'] ++ ~cfg[\mfccCount].collect({ |i|
			(sin(t * (0.1 + (i * 0.05))) * 10).asFloat;
		});
		// Synthetic chroma: one dominant note rotating through pitch classes
		chromaArgs = ['/audio/chroma'] ++ 12.collect({ |i|
			var dominantNote = ((t * 0.5) % 12).asInteger;
			if(i == dominantNote, { 0.8 + (0.2.rand) }, { 0.1.rand });
		});
		~dests.do({ |d|
			if(~feat[\mfcc], { d.sendMsg(*mfccArgs) });
			if(~feat[\chroma], { d.sendMsg(*chromaArgs) });
		});
		dt.wait;
	};
}).play;

// --- Slow features (key) ---
if(~feat[\key], {
	Routine({
		var dt = 1.0 / ~cfg[\trigSlow];
		loop {
			var t = Main.elapsedTime;
			var key = ((t * 0.1) % 12).asInteger;
			var mode = if((t % 20) < 10, { 1 }, { 0 });
			~dests.do({ |d| d.sendMsg('/audio/key', key, mode) });
			("  [test] key: " ++ noteNames[key] ++ if(mode == 1, { " major" }, { " minor" })).postln;
			dt.wait;
		};
	}).play;
});

// --- Beat (simulated ~120 BPM) ---
if(~feat[\beat], {
	Routine({
		var bpm = 120;
		loop {
			~dests.do({ |d|
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
	[~onset[\kick],   '/audio/onset/kick',   0.4,  0.3],
	[~onset[\snare],  '/audio/onset/snare',  0.5,  0.4],
	[~onset[\hihat],  '/audio/onset/hihat',  0.15, 0.1],
	[~onset[\perc],   '/audio/onset/perc',   0.2,  0.2],
	[~onset[\bass],   '/audio/onset/bass',   0.8,  0.5],
	[~onset[\melody], '/audio/onset/melody',  0.6,  0.4],
	[~onset[\bright], '/audio/onset/bright', 0.5,  0.3],
	[~onset[\any],    '/audio/onset/any',    0.15, 0.15],
	[~onset[\drop],   '/audio/onset/drop',   2.0,  2.0],
	[~onset[\soft],   '/audio/onset/soft',   1.0,  1.0],
].do({ |spec|
	var enabled = spec[0], path = spec[1], base = spec[2], jitter = spec[3];
	if(enabled, {
		Routine({
			loop {
				~dests.do({ |d| d.sendMsg(path, 1) });
				(base + jitter.rand).wait;
			};
		}).play;
	});
});

// --- Scene change (simulated every 8-20 seconds) ---
if(~feat[\scene], {
	Routine({
		loop {
			~dests.do({ |d| d.sendMsg('/audio/scene_change', 1) });
			(8.0 + 12.0.rand).wait;
		};
	}).play;
});

// --- Energy direction (simulated slow sine wave: building/breaking) ---
if(~feat[\energy], {
	Routine({
		var dt = 1.0 / ~cfg[\trigMedium];
		loop {
			var t = Main.elapsedTime;
			// Slow sine cycles through building (+1) and breaking (-1)
			var dir = sin(t * 0.15).clip(-1, 1);
			~dests.do({ |d| d.sendMsg('/audio/energy_direction', dir) });
			dt.wait;
		};
	}).play;
});

// --- Vocal likelihood (simulated: peaks periodically like vocal phrases) ---
if(~feat[\vocal], {
	Routine({
		var dt = 1.0 / ~cfg[\trigMedium];
		loop {
			var t = Main.elapsedTime;
			// Simulate vocal phrases: periodic peaks with silence between
			var phrase = (sin(t * 1.5) * 0.5 + 0.5).clip(0, 1);
			var inPhrase = (sin(t * 0.2) > 0).asInteger;
			var vocal = phrase * inPhrase;
			~dests.do({ |d| d.sendMsg('/audio/vocal', vocal) });
			dt.wait;
		};
	}).play;
});

// --- Heartbeat (always active) ---
Routine({
	loop {
		~dests.do({ |d| d.sendMsg('/audio/heartbeat', 1) });
		2.wait;
	};
}).play;

"  Test mode running. Sending synthetic OSC data.".postln;
("  Sending to " ++ ~dests.size.asString ++ " destination(s)").postln;
"  Press Ctrl+C to stop.".postln;
)
