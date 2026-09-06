'use strict';

// SGT VoIP Web Push Browser Interop Helper
window.SgtWebPush = {
  isSupported: function() {
    return ('serviceWorker' in navigator) && ('PushManager' in window) && ('Notification' in window);
  },

  isStandalone: function() {
    const isMediaStandalone = window.matchMedia && window.matchMedia('(display-mode: standalone)').matches;
    const isNavStandalone = window.navigator.standalone === true;
    return Boolean(isMediaStandalone || isNavStandalone);
  },

  getPermission: function() {
    if (!('Notification' in window)) return 'unsupported';
    return Notification.permission;
  },

  requestPermission: async function() {
    if (!('Notification' in window)) return 'unsupported';
    return await Notification.requestPermission();
  },

  getSubscription: async function() {
    if (!this.isSupported()) return null;
    try {
      const reg = await navigator.serviceWorker.ready;
      const sub = await reg.pushManager.getSubscription();
      if (!sub) return null;
      return this._formatSubscription(sub);
    } catch (e) {
      console.warn('[SgtWebPush] Error getting subscription:', e);
      return null;
    }
  },

  subscribe: async function(vapidPublicKeyBase64) {
    if (!this.isSupported()) {
      throw new Error('Web Push is not supported in this browser');
    }
    const permission = await Notification.requestPermission();
    if (permission !== 'granted') {
      throw new Error('Notification permission was not granted: ' + permission);
    }

    const reg = await navigator.serviceWorker.ready;
    const applicationServerKey = this._urlBase64ToUint8Array(vapidPublicKeyBase64);
    const sub = await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: applicationServerKey,
    });
    return this._formatSubscription(sub);
  },

  unsubscribe: async function() {
    if (!this.isSupported()) return false;
    try {
      const reg = await navigator.serviceWorker.ready;
      const sub = await reg.pushManager.getSubscription();
      if (!sub) return true;
      return await sub.unsubscribe();
    } catch (e) {
      console.warn('[SgtWebPush] Error unsubscribing:', e);
      return false;
    }
  },

  _formatSubscription: function(sub) {
    const rawP256dh = sub.getKey ? sub.getKey('p256dh') : null;
    const rawAuth = sub.getKey ? sub.getKey('auth') : null;
    const p256dh = rawP256dh ? this._arrayBufferToBase64(rawP256dh) : '';
    const auth = rawAuth ? this._arrayBufferToBase64(rawAuth) : '';
    return JSON.stringify({
      endpoint: sub.endpoint,
      p256dh: p256dh,
      auth: auth,
    });
  },

  _urlBase64ToUint8Array: function(base64String) {
    const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
    const base64 = (base64String + padding).replace(/\-/g, '+').replace(/_/g, '/');
    const rawData = window.atob(base64);
    const outputArray = new Uint8Array(rawData.length);
    for (let i = 0; i < rawData.length; ++i) {
      outputArray[i] = rawData.charCodeAt(i);
    }
    return outputArray;
  },

  _arrayBufferToBase64: function(buffer) {
    const bytes = new Uint8Array(buffer);
    let binary = '';
    for (let i = 0; i < bytes.byteLength; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    return window.btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  }
};
