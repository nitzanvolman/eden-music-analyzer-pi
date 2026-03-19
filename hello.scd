// hello.scd — Minimal SC test script
// Use this to verify SuperCollider + JACK + OSC work BEFORE trying analyzer.scd.
// If this doesn't work, analyzer.scd won't either.
//
// What it does:
//   1. Boots the audio server
//   2. Reads audio input and measures volume (amplitude)
//   3. Sends amplitude as an OSC message 10 times per second
//   4. Prints each value to the console
//
// Run:
//   export QT_QPA_PLATFORM=offscreen
//   cd ~/supercolliderStandaloneRPI64
//   ./sclang ~/sc-osc/hello.scd
//
// Verify with oscdump (in another terminal):
//   oscdump 9000
//
// You should see:
//   /hello/amplitude f 0.003215
//   /hello/amplitude f 0.012847
//   ...
//
// If you see values > 0 when making noise, everything works.
// If you only see 0.0, your audio input is not working (check JACK device).

(
var dest = NetAddr("127.0.0.1", 9000);

"--- SC-OSC Hello World ---".postln;

s.waitForBoot({

	"Server booted.".postln;
	("Sample rate: " ++ s.sampleRate).postln;

	SynthDef(\hello, {
		var sig, amp;
		sig = SoundIn.ar(0);
		amp = Amplitude.kr(sig, 0.01, 0.1);
		SendReply.kr(Impulse.kr(10), '/tr_hello', [amp]);
		Out.ar(0, DC.ar(0));
	}).add;

	s.sync;

	Synth(\hello);

	OSCdef(\fwdHello, { |msg|
		var amp = msg[3];
		dest.sendMsg('/hello/amplitude', amp.asFloat);
		("  amp: " ++ amp.round(0.001)).postln;
	}, '/tr_hello');

	"Sending /hello/amplitude to 127.0.0.1:9000 (10 Hz)".postln;
	"Make some noise! Ctrl+C to stop.".postln;

}, onFailure: {
	"ERROR: Server failed to boot. Is JACK running? Check ~/.jackdrc".postln;
	1.exit;
});
)
