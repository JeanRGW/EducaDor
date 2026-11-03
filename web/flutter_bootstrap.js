{{flutter_js}}
{{flutter_build_config}}

// Omit Flutter service worker settings: its generated worker unregisters itself.
// Registration failure must not prevent an online launch.
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('flutter_service_worker.js', {
    updateViaCache: 'none',
  }).catch(() => {});
}
_flutter.loader.load({config: {canvasKitBaseUrl: 'canvaskit/'}});
