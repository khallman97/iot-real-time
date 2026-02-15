/**
 * MQTT Service
 * Handles real-time IoT Core connection via AWS Amplify PubSub
 */

import { Amplify } from 'aws-amplify';
import { PubSub } from '@aws-amplify/pubsub';
import { fetchAuthSession } from 'aws-amplify/auth';
import { awsConfig } from '../config';

let subscriptions = new Map();
let pubsubInstance = null;

/**
 * Get or create PubSub instance with proper credentials
 */
async function getPubSub() {
  if (!pubsubInstance) {
    const session = await fetchAuthSession();

    if (!session.credentials) {
      throw new Error('No credentials available for PubSub');
    }

    const currentConfig = Amplify.getConfig();
    Amplify.configure({
      ...currentConfig,
      PubSub: {
        aws_pubsub_region: awsConfig.region,
        aws_pubsub_endpoint: awsConfig.iotEndpoint,
      }
    });

    pubsubInstance = new PubSub({
      region: awsConfig.region,
      endpoint: awsConfig.iotEndpoint,
    });
  }
  return pubsubInstance;
}

/**
 * Initialize MQTT/PubSub client
 */
export async function initializeMqtt() {
  const pubsub = await getPubSub();
  return pubsub;
}

/**
 * Subscribe to equipment data
 */
export async function subscribeToEquipment(companyId, serialNumber, onMessage) {
  const topic = serialNumber === '*'
    ? `companies/${companyId}/#`
    : `companies/${companyId}/${serialNumber}`;

  const subscriptionKey = `${companyId}-${serialNumber}`;

  try {
    const pubsub = await getPubSub();
    const observable = pubsub.subscribe({ topics: [topic] });

    const subscription = observable.subscribe({
      next: (data) => {
        onMessage({
          topic: topic,
          value: data
        });
      },
      error: (error) => {
        console.error('Subscription error:', error);
      },
      complete: () => {}
    });

    subscriptions.set(subscriptionKey, {
      topic,
      subscription
    });

    return {
      unsubscribe: () => unsubscribeFromEquipment(companyId, serialNumber)
    };
  } catch (error) {
    console.error('Failed to subscribe:', error);
    return { unsubscribe: () => {} };
  }
}

/**
 * Unsubscribe from equipment data
 */
export function unsubscribeFromEquipment(companyId, serialNumber) {
  const subscriptionKey = `${companyId}-${serialNumber}`;
  const sub = subscriptions.get(subscriptionKey);

  if (sub && sub.subscription) {
    sub.subscription.unsubscribe();
  }

  subscriptions.delete(subscriptionKey);
}

/**
 * Unsubscribe from all topics
 */
export function unsubscribeAll() {
  for (const sub of subscriptions.values()) {
    if (sub.subscription) {
      sub.subscription.unsubscribe();
    }
  }
  subscriptions.clear();
}

/**
 * Get connection state
 */
export function isConnected() {
  return pubsubInstance !== null;
}
