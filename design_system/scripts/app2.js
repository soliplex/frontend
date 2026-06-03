/* Soliplex DS — app bootstrap: compose content, wire tweaks, sidebar scrollspy, demo tabs */

(function () {
  // ---------- compose content ----------
  const s1 = window.__SECTIONS_1 || {};
  const s2 = window.__SECTIONS_2 || {};
  const s3 = window.__SECTIONS_3 || {};
  const main = document.getElementById('main');
  const parts = [
    s1.overview, s1.brand, s1.color,
    s2.typography, s2.spacing, s2.radii, s2.breakpoints,
    s2.componentsIntro, s2.buttons, s2.inputs, s2.cards, s2.chips, s2.chat, s2.feedback, s2.statusSection,
    s3.execution, s3.citations, s3.docPicker, s3.network, s3.quiz,
    s2.architecture, s2.usage, s2.adoption,
  ].filter(Boolean);
  main.innerHTML = parts.join('\n');

  // ---------- tweaks state ----------
  const state = { ...(window.TWEAK_DEFAULTS || { doc_style: 'clean', demo_mode: 'light' }) };

  function applyState() {
    document.body.setAttribute('data-doc', state.doc_style);
    // Apply default demo mode to all theme demos that haven't been manually switched.
    document.querySelectorAll('.theme-demo').forEach(demo => {
      if (!demo.dataset.userSet) {
        demo.setAttribute('data-mode', state.demo_mode);
        demo.querySelectorAll('.tabs button').forEach(b => {
          b.classList.toggle('active', b.dataset.set === state.demo_mode);
        });
      }
    });
    // Update tweak buttons
    document.querySelectorAll('.tweaks-panel .opt-row').forEach(row => {
      const key = row.dataset.tweak;
      row.querySelectorAll('button.opt').forEach(btn => {
        btn.classList.toggle('active', btn.dataset.value === state[key]);
      });
    });
  }

  // ---------- demo tab switching ----------
  document.addEventListener('click', (e) => {
    const tabBtn = e.target.closest('.theme-demo .tabs button');
    if (tabBtn) {
      const demo = tabBtn.closest('.theme-demo');
      demo.dataset.userSet = '1';
      demo.setAttribute('data-mode', tabBtn.dataset.set);
      demo.querySelectorAll('.tabs button').forEach(b => b.classList.toggle('active', b === tabBtn));
      return;
    }

    const opt = e.target.closest('.tweaks-panel .opt-row button.opt');
    if (opt) {
      const key = opt.closest('.opt-row').dataset.tweak;
      state[key] = opt.dataset.value;
      applyState();
      // Persist via host edit-mode protocol.
      try {
        window.parent.postMessage({ type: '__edit_mode_set_keys', edits: { [key]: state[key] } }, '*');
      } catch (_) {}
    }
  });

  // ---------- sidebar scroll-spy ----------
  const sidebarLinks = [...document.querySelectorAll('.doc-sidebar a[href^="#"]')];
  const targets = sidebarLinks
    .map(a => document.querySelector(a.getAttribute('href')))
    .filter(Boolean);

  const io = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (!entry.isIntersecting) return;
      const id = entry.target.id;
      sidebarLinks.forEach(a => a.classList.toggle('active', a.getAttribute('href') === '#' + id));
    });
  }, { rootMargin: '-40% 0px -55% 0px', threshold: 0 });

  targets.forEach(t => io.observe(t));

  // ---------- edit mode protocol ----------
  window.addEventListener('message', (ev) => {
    const data = ev.data || {};
    if (data.type === '__activate_edit_mode') {
      document.getElementById('tweaks').classList.add('visible');
    } else if (data.type === '__deactivate_edit_mode') {
      document.getElementById('tweaks').classList.remove('visible');
    }
  });
  try {
    window.parent.postMessage({ type: '__edit_mode_available' }, '*');
  } catch (_) {}

  // Initial render
  applyState();
})();
