/**
 * Authentication Service
 * Handles Cognito authentication using AWS Amplify
 */

import { Amplify } from 'aws-amplify';
import { signIn, signOut, getCurrentUser, fetchAuthSession, confirmSignIn } from 'aws-amplify/auth';
import { awsConfig } from '../config';

// Configure Amplify
Amplify.configure({
  Auth: {
    Cognito: {
      userPoolId: awsConfig.cognitoUserPoolId,
      userPoolClientId: awsConfig.cognitoClientId,
      identityPoolId: awsConfig.cognitoIdentityPoolId,
      loginWith: {
        email: true,
      },
    },
  },
});

/**
 * Sign in with email and password
 */
export async function login(email, password) {
  try {
    const result = await signIn({ username: email, password });

    // Check if new password is required
    if (result.nextStep?.signInStep === 'CONFIRM_SIGN_IN_WITH_NEW_PASSWORD_REQUIRED') {
      return { success: false, needsNewPassword: true, result };
    }

    return { success: true, result };
  } catch (error) {
    console.error('Login error:', error);
    return { success: false, error: error.message };
  }
}

/**
 * Complete new password challenge
 */
export async function completeNewPassword(newPassword) {
  try {
    const result = await confirmSignIn({ challengeResponse: newPassword });
    return { success: true, result };
  } catch (error) {
    console.error('New password error:', error);
    return { success: false, error: error.message };
  }
}

/**
 * Sign out current user
 */
export async function logout() {
  try {
    await signOut();
    return { success: true };
  } catch (error) {
    console.error('Logout error:', error);
    return { success: false, error: error.message };
  }
}

/**
 * Get current authenticated user
 */
export async function getUser() {
  try {
    const user = await getCurrentUser();
    const session = await fetchAuthSession();

    // Extract company_id from token
    const idToken = session.tokens?.idToken;
    const companyId = idToken?.payload?.['custom:company_id'] || null;

    return {
      authenticated: true,
      username: user.username,
      userId: user.userId,
      companyId,
      session,
    };
  } catch (error) {
    return { authenticated: false };
  }
}

/**
 * Get AWS credentials for IoT connection
 */
export async function getCredentials() {
  try {
    const session = await fetchAuthSession();
    return session.credentials;
  } catch (error) {
    console.error('Error getting credentials:', error);
    return null;
  }
}
