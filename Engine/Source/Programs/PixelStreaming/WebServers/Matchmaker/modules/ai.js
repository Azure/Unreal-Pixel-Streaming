// Copyright Microsoft Corp. All Rights Reserved.

// Azure SDK Clients
const appInsights = require('applicationinsights');

var config;
var telemetryClient;

function initAIModule(configObj) {

	config = configObj;

	if (config.appInsightsInstrumentationKey) {
		appInsights.setup(config.appInsightsInstrumentationKey).setSendLiveMetrics(true).start();
		telemetryClient = appInsights.defaultClient;
		telemetryClient.commonProperties["region"] = config.region;
	}
	if (!telemetryClient) {
		console.log("No valid appInsights object to use");
	}
}

function logError(err) {
	
	if (!telemetryClient) {
		return;
	}

	telemetryClient.trackMetric({ name: "Errors", value: 1 });
	telemetryClient.trackException({ exception: err });
}

function logEvent(eventName, eventCustomValue) {

	if (!telemetryClient) {
		return;
	}

	telemetryClient.trackEvent({ name: eventName, properties: { customProperty: eventCustomValue } });
}

function logMetric(metricName, metricValue) {

	if (!telemetryClient) {
		return;
	}

	telemetryClient.trackMetric({ name: metricName, value: metricValue });
}

module.exports = {
	init: initAIModule,
	logError,
	logEvent,
	logMetric
}