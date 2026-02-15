/**
 * API Service
 * Handles requests to the History Lambda API
 */

import { fetchAuthSession } from 'aws-amplify/auth';
import { awsConfig } from '../config';

/**
 * Make authenticated request to the API
 */
async function apiRequest(path, options = {}) {
  const session = await fetchAuthSession();
  const idToken = session.tokens?.idToken?.toString();

  if (!idToken) {
    throw new Error('Not authenticated');
  }

  const url = `${awsConfig.apiUrl}/${path}`;

  const response = await fetch(url, {
    ...options,
    headers: {
      'Authorization': `Bearer ${idToken}`,
      'Content-Type': 'application/json',
      ...options.headers,
    },
  });

  if (!response.ok) {
    const error = await response.json().catch(() => ({}));
    throw new Error(error.error || `API error: ${response.status}`);
  }

  return response.json();
}

/**
 * Get list of equipment for the current user's company
 */
export async function getEquipment() {
  return apiRequest('equipment');
}

/**
 * Get historical sensor data for an equipment
 * @param {string} serialNumber - Equipment serial number
 * @param {object} options - Query options
 * @param {number} options.startTime - Start timestamp (optional)
 * @param {number} options.endTime - End timestamp (optional)
 * @param {number} options.limit - Max records to return (default 100)
 */
export async function getHistory(serialNumber, options = {}) {
  const params = new URLSearchParams({ serial_number: serialNumber });

  if (options.startTime) params.append('start_time', options.startTime);
  if (options.endTime) params.append('end_time', options.endTime);
  if (options.limit) params.append('limit', options.limit);

  return apiRequest(`history?${params.toString()}`);
}

/**
 * Attach IoT policy to the current user's Cognito Identity.
 * This is required for WebSocket connections to AWS IoT Core.
 */
export async function attachIotPolicy() {
  const session = await fetchAuthSession();
  const identityId = session.identityId;

  if (!identityId) {
    throw new Error('No identity ID available');
  }

  return apiRequest('attach-iot-policy', {
    method: 'POST',
    body: JSON.stringify({ identityId }),
  });
}
