// Copyright Microsoft Corp. All Rights Reserved.
// The following module adds the capabilities of scaling up and down Unreal Pixel Streaming in Azure.
// Virtual Machine Scale Sets (VMSS) compute in Azure is used to host the Signaling Server and Unreal app,
// which is scaled out to allow clients their own session. Review the parameters in the altered defaultConfig
// in matchmaker.js to set the scale out policies for your specific requirements.

// A varible to the last time we scaled down, used for a reference to know how quick we should consider scaling down again (to avoid multiple scale downs too soon)
var lastScaledownTime = Date.now();
// The number of total app instances that are connecting to the matchmaker
var totalInstances = 0;
// The number of total client connections (users) streaming
var totalConnectedClients = 0;
// This stores the current Azure Virtual Machine Scale Set node count (sku.capacity), retried by client.get(rg_name, vmssName)
var currentVMSSNodeCount = -1;
// The stores the current Azure Virtual Machine Scale Set provisioning (i.e., scale) state (Succeeded, etc..)
var currentVMSSProvisioningState = null;
// The amount of percentage we need to scale up when autoscaling with a percentage policy
var scaleUpPercentage = 10;

// Azure SDK Clients
const { ComputeManagementClient, VirtualMachineScaleSets } = require('@azure/arm-compute');
const msRestNodeAuth = require('@azure/ms-rest-nodeauth');
const logger = require('@azure/logger');

var config;
var ai;

function initAutoscaleModule(configObj, aiObj) {

	logger.setLogLevel('info');
	config = configObj;
	ai = aiObj;

	return null;
}

var lastVMSSCapacity = 0;
var lastVMSSProvisioningState = "";

// This goes out to Azure and grabs the current VMSS provisioning state and current capacity
async function getVMSSNodeCountAndState() {
	return new Promise(function(resolve, reject) {
		const options = {
			resource: 'https://management.azure.com'
		}

		// Use an Azure system managed identity to get a token for managing the given resource group
		msRestNodeAuth.loginWithVmMSI(options).then((creds) => {
			const client = new ComputeManagementClient(creds, config.subscriptionId);
			var vmss = new VirtualMachineScaleSets(client);

			// Get the latest details about the VMSS in Azure
			vmss.get(config.resourceGroup, config.virtualMachineScaleSet).then((result) => {
				if (result == null || result.sku == null) {
					reject(err);
				}

				// Set our global variables so we know the totaly capacity and VMSS status
				currentVMSSNodeCount = result.sku.capacity;
				currentVMSSProvisioningState = result.provisioningState;

				// Only log if it changed
				if (currentVMSSNodeCount != lastVMSSCapacity || currentVMSSProvisioningState != lastVMSSProvisioningState) {
					console.log(`VMSS Capacity: ${currentVMSSNodeCount} and State: ${currentVMSSProvisioningState}`);
				}

				lastVMSSCapacity = currentVMSSNodeCount;
				lastVMSSProvisioningState = currentVMSSProvisioningState;
				ai.logMetric("VMSSGetSuccess", 1);

				resolve();
			}).catch((err) => {
				reject(err);
				console.error(`ERROR getting VMSS info: ${err}`);
				ai.logError(err);
				ai.logMetric("VMSSGetError", 1);
			});
		}).catch((err) => {
			reject(err);
			console.error(err);
			ai.logError(err);
			ai.logMetric("MSILoginGetError", 1);
		});
	});
}

// This returnes the amount of connected clients
function getConnectedClients(cirrusServers) {

	var connectedClients = 0;

	for (cirrusServer of cirrusServers.values()) {
		// we are interested in the amount of cirrusServers that have 1 or more players connected to them. We are not interested in the amount of players
		connectedClients += (cirrusServer.numConnectedClients > 1 ? 1 : cirrusServer.numConnectedClients);

		if (cirrusServer.numConnectedClients > 1) {
			console.log(`WARNING: cirrusServer ${cirrusServer.address} has ${cirrusServer.numConnectedClients}`);
        }
	}

	console.log(`Total Connected Clients Found: ${connectedClients}`);
	return connectedClients;
}

// This scales out the Azure VMSS servers with a new capacity
function scaleSignalingWebServers(newCapacity) {

	const options = {
		resource: 'https://management.azure.com'
	}

	//msRestNodeAuth.interactiveLogin().then((creds) => {  // Used for local testing
	// Use an Azure system managed identity to get a token for managing the given resource group
	msRestNodeAuth.loginWithVmMSI(options).then((creds) => {
		const client = new ComputeManagementClient(creds, config.subscriptionId);
		var vmss = new VirtualMachineScaleSets(client);

		var updateOptions = new Object();
		updateOptions.sku = new Object();
		updateOptions.sku.capacity = newCapacity;

		// Update the VMSS with the new capacity
		vmss.update(config.resourceGroup, config.virtualMachineScaleSet, updateOptions).then((result) => {
			console.log(`Success Scaling VMSS: ${result}`);
			ai.logMetric("VMSSScaleSuccess", 1);
		}).catch((err) => {
			console.error(`ERROR Scaling VMSS: ${err}`);
			ai.logError(err);
			ai.logMetric("VMSSScaleUpdateError", 1);
		});
	}).catch((err) => {
		console.error(err);
		ai.logError(err);
		ai.logMetric("MSILoginError", 1);
	});
}

// This scales up a VMSS cluster for Unreal streams to a new node count
function scaleupInstances(newNodeCount) {
	// Make sure we don't try to scale past our desired max instances
	if(newNodeCount > config.maxInstanceCount) {
		console.log(`New Node Count is higher than Max Node Count. Setting New Node Count to Max.`);
		newNodeCount = config.maxInstanceCount;
	}

	ai.logEvent("ScaleUp", newNodeCount);

	lastScaleupTime = Date.now();

	scaleSignalingWebServers(newNodeCount);
}

// This scales down a VMSS cluster for Unreal streams to a new node count
function scaledownInstances(newNodeCount) {
	console.log(`Scaling down to ${newNodeCount}!!!`);
	lastScaledownTime = Date.now();

	// If set, make sure we don't try to scale below our desired min node count
	if ((config.minInstanceCount > 0) && (newNodeCount < config.minInstanceCount)) {
		console.log(`Using minInstanceCount to scale down: ${config.minInstanceCount}`);
		newNodeCount = config.minInstanceCount;
	}

	// Mode sure we keep at least 1 node
	if (newNodeCount <= 0)
		newNodeCount = 1;

	ai.logEvent("ScaleDown", newNodeCount);

	scaleSignalingWebServers(newNodeCount);
}

// Called when we want to review the autoscale policy to see if there needs to be scaling up or down
function evaluateAutoScalePolicy(cirrusServers) {
	// first refresh what we know of the current VMSS state before we do anything
	getVMSSNodeCountAndState().then(() => {
		totalInstances = cirrusServers.size;
		totalConnectedClients = getConnectedClients(cirrusServers);

		console.log(`Current VMSS count: ${currentVMSSNodeCount} - Current Cirrus Servers Connected: ${totalInstances} - Current Cirrus Servers with clients: ${totalConnectedClients}`);
		ai.logMetric("TotalInstances", totalInstances);
		ai.logMetric("TotalConnectedClients", totalConnectedClients);

		var availableConnections = Math.max(totalInstances - totalConnectedClients, 0);

		var timeElapsedSinceScaledown = Date.now() - lastScaledownTime;
		var minutesSinceScaledown = Math.round(timeElapsedSinceScaledown / 60000);
		var percentUtilized = 0;
		var remainingUtilization = 100;

		// Get the percentage of total available signaling servers taken by users
		if (totalConnectedClients > 0 && totalInstances > 0) {
			percentUtilized = (totalConnectedClients / totalInstances) * 100;
			remainingUtilization = 100 - percentUtilized;
		}

		//console.log(`Minutes since last scaleup: ${minutesSinceScaleup} and scaledown: ${minutesSinceScaledown} and availConnections: ${availableConnections} and % used: ${percentUtilized}`);
		ai.logMetric("PercentUtilized", percentUtilized);
		ai.logMetric("AvailableConnections", availableConnections);

		// Don't try and scale up/down if there is already a scaling operation in progress
		if (currentVMSSProvisioningState != 'Succeeded') {
			console.log(`Ignoring scale check as VMSS provisioning state isn't in Succeeded state: ${currentVMSSProvisioningState}`);
			ai.logMetric("VMSSProvisioningStateNotReady", 1);
			ai.logEvent("VMSSNotReady", currentVMSSProvisioningState);
			return;
		}

		// Make sure all the cirrus servers on the VMSS have caught up and connected to the MM before considering scaling, or at least 15 minutes since starting up 
		if ((totalInstances/config.instancesPerNode) < currentVMSSNodeCount) {
			console.log(`Ignoring scale check as only ${totalInstances/config.instancesPerNode} VMSS nodes out of ${currentVMSSNodeCount} total VMSS nodes have connected`);
			ai.logMetric("CirrusServersNotAllReady", 1);
			ai.logEvent("CirrusServersNotAllReady", currentVMSSNodeCount - totalInstances);
			return;
		}

		// When scaling out, we overprovision the scale out for performance reasons. So scale out from 1 to 2 nodes actually goes 1 -> 3 -> 2 instead of expected 1 -> 2
		// We want to wait till Azure kills the overprovisioned node
		if ((totalInstances/config.instancesPerNode) > currentVMSSNodeCount) {
			console.log(`Ignoring scale check as VMSS overprovisioning left us with more VMSS instances than we asked for - in a few seconds Azure will delete that extra node and then we continue with our evaluations`);
			ai.logMetric("VMSSOverprovisioningUnderway", 1);
			ai.logEvent("VMSSOverprovisioningUnderway", currentVMSSNodeCount - totalInstances);
			return;
		}

		console.log('---------------------------------------');
		for (cirrusServer of cirrusServers.values()) {
			console.log(`${cirrusServer.address}:${cirrusServer.port} - ${cirrusServer.ready === true ? "": "not "}ready`);	
		}
		console.log('minutesSinceScaledown:       			'+minutesSinceScaledown);
		console.log('config.minMinutesBetweenScaledowns:	'+config.minMinutesBetweenScaledowns);
		console.log('percentUtilized:             			'+percentUtilized);
		console.log('config.instanceCountBuffer:  			'+config.instanceCountBuffer);
		console.log('availableConnections:        			'+availableConnections);
		console.log('totalConnectedClients:       			'+totalConnectedClients);
		console.log('currentVMSSNodeCount:        			'+currentVMSSNodeCount);
		console.log('---------------------------------------');

		// If available user connections is less than our desired buffer level scale up
		if ((config.instanceCountBuffer > 0) && (availableConnections < config.instanceCountBuffer)) {
			var newNodeCount = Math.ceil((config.instanceCountBuffer + totalConnectedClients)/config.instancesPerNode);
			console.log(`Not enough available connections in buffer -- scale up from ${currentVMSSNodeCount} to ${newNodeCount}`);
			ai.logMetric("VMSSNodeCountScaleUp", 1);
			ai.logEvent("Scaling up VMSS node count", availableConnections);
			scaleupInstances(newNodeCount);
			return;
		}
		// Else if the remaining utilization percent is less than our desired min percentage. scale up 10% of total instances
		else if ((config.percentBuffer > 0) && (remainingUtilization < config.percentBuffer)) {
			var newNodeCount = Math.ceil((totalInstances * (1+(scaleUpPercentage * .01)))/config.instancesPerNode);
			console.log(`Below percent buffer -- scaling up from ${currentVMSSNodeCount} to ${newNodeCount}`);
			ai.logMetric("VMSSPercentageScaleUp", 1);
			ai.logEvent("Scaling up VMSS percentage", newNodeCount);
			scaleupInstances(newNodeCount);
			return;
		}
		// Else if our current VMSS nodes are less than the desired node count buffer (i.e., we started with 2 VMSS but we wanted a buffer of 5)
		else if ((config.instanceCountBuffer > 0) && ((currentVMSSNodeCount*config.instancesPerNode) < config.instanceCountBuffer)) {
			var newNodeCount = Math.ceil(config.instanceCountBuffer / config.instancesPerNode);
			console.log(`Requested buffer is higher than available instance count -- scale up from ${currentVMSSNodeCount} to ${newNodeCount}`);
			ai.logMetric("VMSSDesiredBufferScaleUp", 1);
			ai.logEvent("Scaling up VMSS to meet initial desired buffer", newNodeCount);
			scaleupInstances(currentVMSSNodeCount + newNodeCount);
			return;
		}

		// Adding hysteresis check to make sure we didn't just scale down and should wait until the scaling has enough time to react
		if (minutesSinceScaledown < config.minMinutesBetweenScaledowns) {
			console.log(`Waiting to evaluate scale down since we already recently scaled down or started the service`);
			ai.logEvent("Waiting to scale down due to recent scale down", minutesSinceScaledown);
			return;
		}
		// Else if we've went long enough without scaling down to consider scaling down when we reach a low enough usage ratio
		else {
			var calculatedNodeCount = currentVMSSNodeCount;
			var scalingType = "";
			var minCurrentInstanceCount = -1;
			if(config.instanceCountBuffer > 0) {
				minCurrentInstanceCount = Math.ceil(config.instanceCountBuffer / config.instancesPerNode);
				calculatedNodeCount = Math.ceil((totalInstances-availableConnections+config.instanceCountBuffer)/config.instancesPerNode);
				scalingType = "InstanceCountBuffer";
			}
			else if(config.percentBuffer > 0) {
				minCurrentInstanceCount = Math.ceil((1*(1+(config.percentBuffer*.01)))/config.instancesPerNode); // in case of buffer sizes > 100%
				calculatedNodeCount = Math.ceil(((totalInstances-availableConnections)*(1+(config.percentBuffer*0.1)))/config.instancesPerNode);
				scalingType = "PercentBuffer";
			}

			var gracefulScaledownCount = -1
			// check if we need to do a graceful scaledown
			if(config.scaleDownByAmount && config.scaleDownByAmount > 0) {
				gracefulScaledownCount = currentVMSSNodeCount - config.scaleDownByAmount;
			}

			// the new node count is either:
			// - the minimum current instance count, calculated based on what is configured
			// - the calculated new node count, based on the current load and buffers
			// - the configured minimum instance count
			// - the graceful scaledown count
			// we will take the highest value of the above
			var newNodeCount = Math.max(calculatedNodeCount, minCurrentInstanceCount, config.minInstanceCount, gracefulScaledownCount);

			if(newNodeCount != currentVMSSNodeCount)
			{
				console.log(`Scaling down for scale config ${scalingType}: Current node count: ${currentVMSSNodeCount} - Minimum current node count (calculated): ${minCurrentInstanceCount} - Minimum node count (configured): ${config.minInstanceCount} - Graceful scaledown count: ${gracefulScaledownCount} ---> New node count: ${newNodeCount}`);
				ai.logMetric("VMSSScaleDown", 1);
				ai.logEvent("Scaling down VMSS due to idling", percentUtilized + "%, count:" + newNodeCount);
				scaledownInstances(newNodeCount);
			}
		}
	});
}

module.exports = {
	init: initAutoscaleModule,
	evaluateAutoScalePolicy,
}