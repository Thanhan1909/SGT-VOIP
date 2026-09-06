'use strict';

// SGT VoIP Softphone Standards-Based Web Push Service Worker
// Scope: /softphone/

const SW_VERSION = '1.0.1';

self.addEventListener('install', (event) => {
  console.log(`[SW ${SW_VERSION}] Installed`);
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  console.log(`[SW ${SW_VERSION}] Activated`);
  event.waitUntil(self.clients.claim());
});

self.addEventListener('push', (event) => {
  console.log(`[SW ${SW_VERSION}] Push notification received`);

  let data = {};
  if (event.data) {
    try {
      data = event.data.json();
    } catch (e) {
      try {
        data = { body: event.data.text() };
      } catch (err) {
        data = {};
      }
    }
  }

  const callId = data.callId || data.call_uuid || '';
  const title = data.title || 'SGT VoIP Softphone';
  const body = data.body || (callId ? `Cuộc gọi đến (${callId.substring(0, 8)}...)` : 'Cuộc gọi đến');
  const url = data.url || (callId ? `/softphone/calls/${encodeURIComponent(callId)}` : '/softphone/');

  const options = {
    body: body,
    icon: 'icons/Icon-192.png',
    badge: 'icons/Icon-192.png',
    tag: callId ? `call-${callId}` : 'sgt-incoming-call',
    renotify: true,
    requireInteraction: true,
    vibrate: [300, 150, 300, 150, 300, 200, 500],
    data: {
      url: url,
      callId: callId,
      expiresAt: data.expiresAt || null,
      receivedAt: Date.now(),
    },
    actions: [
      { action: 'answer', title: 'Nhận cuộc gọi' },
      { action: 'dismiss', title: 'Bỏ qua' },
    ],
  };

  event.waitUntil(
    self.registration.showNotification(title, options)
  );
});

self.addEventListener('notificationclick', (event) => {
  console.log(`[SW ${SW_VERSION}] Notification clicked:`, event.action);
  event.notification.close();

  if (event.action === 'dismiss') {
    return;
  }

  const notificationData = event.notification.data || {};
  let targetPath = notificationData.url || '/softphone/';

  // Strict Same-Origin URL validation to prevent open-redirect vulnerabilities
  let targetUrl;
  try {
    const parsed = new URL(targetPath, self.location.origin);
    if (parsed.origin !== self.location.origin) {
      targetUrl = self.location.origin + '/softphone/';
    } else {
      targetUrl = parsed.href;
    }
  } catch (e) {
    targetUrl = self.location.origin + '/softphone/';
  }

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      // 1. Check if a window is already open within the app origin
      for (const client of clientList) {
        if (client.url && client.url.startsWith(self.location.origin)) {
          if ('navigate' in client) {
            return client.navigate(targetUrl).then((navClient) => {
              if (navClient && 'focus' in navClient) {
                return navClient.focus();
              }
              return client.focus();
            });
          }
          return client.focus();
        }
      }
      // 2. Otherwise open a new window
      if (self.clients.openWindow) {
        return self.clients.openWindow(targetUrl);
      }
    })
  );
});
