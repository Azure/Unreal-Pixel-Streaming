// Copyright Epic Games, Inc. All Rights Reserved.

// -- Communicates with the PixelStreaming SessionMonitor

const argv = require('yargs').argv;
var net = require('net');
var sessionMonitorPort = 0;
var	socket;
var heartbeatIntervalId;

function sendMsg(type) {
	// NOTE: Adding a null character at the end explicitly, so socket.write
	// sends that too
	let msg = `{"type":"${type}"}\0`;
	console.log(`Sending ${msg} to session monitor.`);
	socket.write(msg);
}

function initHeartbeat() {
	sendMsg('heartbeat');
	console.log(`Starting heartbeat timer`);
	heartbeatIntervalId = setInterval(function () {
		sendMsg('heartbeat');
	}, 5000);
}

function init() {
	sessionMonitorPort = (typeof argv.PixelStreamingSessionMonitorPort != 'undefined') ? argv.PixelStreamingSessionMonitorPort : 0;
	if (sessionMonitorPort === 0) {
		console.log('No --PixelStreamingMonitorPort specified (or is 0). Running unmonitored.');
		return;
	}

	console.log(`Connecting to session monitor at ${sessionMonitorPort}`);
	socket = net.Socket();
	socket.setEncoding('utf8');
	socket.connect(sessionMonitorPort, '127.0.0.1', function () {
		console.log('Connected to session monitor');
		initHeartbeat();
	});

	socket.on('error', function (error) {
		console.log(`ERROR: Error connecting to the session monitor: ${error.message}. Running unmonitored.`);
	});

	// Because of .setEncoding('utf8'), 'data' event will receive full strings,
	socket.on('data', function (data) {
		// NOTE: It seems the null character itself stays in the string, so lets remove it
		data = data.replace('\0', '');
		console.log(`Received data ${data} from session monitor`);
		let buffer = Buffer.from(data, 'utf8');
		let msg = JSON.parse(data);
		if (msg.type === 'exit') {
			console.log(`Shutting down, as requested by the session monitor.`);
			process.exit(0);
		}
	});

	socket.on('close', function () {
		if (typeof socket.remoteAddress != 'undefined') {
			console.log('Connection to session monitor closed');
		}
	});

}

module.exports = {
	// Functions
	init
};
