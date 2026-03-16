{{flutter_js}}
{{flutter_build_config}}

const bar = document.getElementById('progress-bar');
const status = document.getElementById('loading-status');
let progress = 0;

function setProgress(value) {
  progress = value;
  if (bar) bar.style.width = progress + '%';
}

function setStatus(text) {
  if (status) status.textContent = text;
}

const trickle = setInterval(() => {
  if (progress < 85) {
    setProgress(progress + (85 - progress) * 0.04);
  }
}, 200);

(function() {
  const nativeLoad = _flutter.loader.load.bind(_flutter.loader);
  _flutter.loader.load = function(options) {
    return nativeLoad(Object.assign({
      onEntrypointLoaded: async function(engineInitializer) {
        try {
          setStatus('Initializing...');
          setProgress(90);

          const appRunner = await engineInitializer.initializeEngine(options?.config);

          setStatus('Starting...');
          setProgress(95);

          await appRunner.runApp();

          setProgress(100);
        } finally {
          clearInterval(trickle);
        }
      }
    }, options));
  };
})();

_flutter.loader.load()
